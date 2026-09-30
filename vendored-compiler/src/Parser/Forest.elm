module Parser.Forest exposing (IncrementalResult, parse, parseIncrementally, parseIncrementallySkipAcc, parseToForestWithAccumulator)

{-| Parse source lines into a forest of ExpressionBlocks.

    import Parser.Forest

    lines
        |> Parser.Forest.parse
        --> Forest ExpressionBlock

    params
        |> Parser.Forest.parseToForestWithAccumulator lines
        --> ( Accumulator, Forest ExpressionBlock )

-}

import Dict
import Either exposing (Either(..))
import Generic.Acc
import Generic.BlockUtilities
import Generic.ForestTransform
import Parser.Pipeline
import Parser.PrimitiveBlock
import RoseTree.Tree as Tree exposing (Tree)
import V3.Types exposing (Accumulator, CompilerParameters, Expr(..), ExprMeta, Expression, ExpressionBlock, ExpressionCache, Filter(..), Heading(..), PrimitiveBlock)


{-| Parse source lines into a forest of expression blocks.

Pipeline:

1.  Parse lines into PrimitiveBlocks
2.  Build forest structure based on indentation
3.  Convert each PrimitiveBlock to ExpressionBlock

-}
parse : List String -> List (Tree ExpressionBlock)
parse lines =
    parseWith Parser.Pipeline.toExpressionBlock lines


{-| Parse lines into PrimitiveBlocks, build the forest by indentation, and
convert each block with the given function.
-}
parseWith : (PrimitiveBlock -> ExpressionBlock) -> List String -> List (Tree ExpressionBlock)
parseWith toExpressionBlock lines =
    lines
        |> Parser.PrimitiveBlock.parse
        |> Generic.ForestTransform.forestFromBlocks .indent
        |> mapForest toExpressionBlock


{-| Parse source lines into a forest with accumulator.

Pipeline:

1.  Parse lines into forest of ExpressionBlocks
2.  Filter forest based on CompilerParameters
3.  Transform with accumulator (numbering, references, etc.)

-}
parseToForestWithAccumulator : CompilerParameters -> List String -> ( Accumulator, List (Tree ExpressionBlock) )
parseToForestWithAccumulator params lines =
    parse lines |> accumulate params


{-| Filter the forest, then run the accumulator pass (numbering, references, etc.).
-}
accumulate : CompilerParameters -> List (Tree ExpressionBlock) -> ( Accumulator, List (Tree ExpressionBlock) )
accumulate params forest =
    forest
        |> filterForest params.filter
        |> Generic.Acc.transformAccumulate Generic.Acc.initialData


{-| Filter the forest based on filter settings.
-}
filterForest : Filter -> List (Tree ExpressionBlock) -> List (Tree ExpressionBlock)
filterForest filter forest =
    case filter of
        NoFilter ->
            forest

        SuppressDocumentBlocks ->
            forest
                |> filterForestOnName (\name -> name /= Just "document")
                |> filterForestOnName (\name -> name /= Just "title")


{-| Filter forest by block name predicate.
-}
filterForestOnName : (Maybe String -> Bool) -> List (Tree ExpressionBlock) -> List (Tree ExpressionBlock)
filterForestOnName predicate forest =
    List.filter (\tree -> predicate (Generic.BlockUtilities.getExpressionBlockName (Tree.value tree))) forest


{-| Parse source lines incrementally, reusing cached expression parse results.
-}
parseIncrementally :
    CompilerParameters
    -> ExpressionCache
    -> List String
    -> ( ExpressionCache, Accumulator, List (Tree ExpressionBlock) )
parseIncrementally params cache lines =
    let
        ( acc, forest ) =
            parseWith (Parser.Pipeline.toExpressionBlockCached cache) lines
                |> accumulate params
    in
    ( buildExpressionCache forest, acc, forest )


{-| Result of an incremental parse with accumulator skip optimization.
-}
type alias IncrementalResult =
    { cache : ExpressionCache
    , acc : Accumulator
    , forest : List (Tree ExpressionBlock)
    , accWasSkipped : Bool
    }


{-| Parse incrementally, skipping the accumulator pass when safe.

If the forest structure hasn't changed and the only modified blocks are
accumulator-independent (plain text paragraphs, code blocks, etc.),
reuse the previous Accumulator and splice the new block content into
the previous forest. Otherwise fall back to the full accumulator pass.

-}
parseIncrementallySkipAcc :
    CompilerParameters
    -> ExpressionCache
    -> ( Accumulator, List (Tree ExpressionBlock) )
    -> List String
    -> IncrementalResult
parseIncrementallySkipAcc params cache ( prevAcc, prevForest ) lines =
    let
        newForest =
            parseWith (Parser.Pipeline.toExpressionBlockCached cache) lines
                |> filterForest params.filter
    in
    case spliceIfAccIndependent prevForest newForest of
        Just splicedForest ->
            { cache = buildExpressionCache splicedForest, acc = prevAcc, forest = splicedForest, accWasSkipped = True }

        Nothing ->
            let
                ( acc, forest ) =
                    Generic.Acc.transformAccumulate Generic.Acc.initialData newForest
            in
            { cache = buildExpressionCache forest, acc = acc, forest = forest, accWasSkipped = False }


{-| Walk the old and new forests together, and return the forest to use with
the previous accumulator, or Nothing if the previous accumulator can't be reused.

Reuse requires:

  - the same shape: the same number of trees and children at every level, with
    matching headings and indents;
  - every block keeps its id. The accumulator stores block ids and expression
    ids (references, footnotes, terms, numbered items), and both embed the
    line number, so a changed block that gains or loses lines invalidates it;
  - every block whose source text changed is accumulator-independent, in both
    its old and new versions.

Unchanged blocks keep their accumulator-derived properties from the old forest,
but take position metadata (offsets) from the new parse. Changed blocks are the
new versions. Stops at the first mismatch.
-}
spliceIfAccIndependent : List (Tree ExpressionBlock) -> List (Tree ExpressionBlock) -> Maybe (List (Tree ExpressionBlock))
spliceIfAccIndependent oldForest newForest =
    spliceForestHelp oldForest newForest []


{-| Accumulator loop over sibling trees, so long documents do not grow the stack.
Recursion into children goes only as deep as the document's nesting.
-}
spliceForestHelp : List (Tree ExpressionBlock) -> List (Tree ExpressionBlock) -> List (Tree ExpressionBlock) -> Maybe (List (Tree ExpressionBlock))
spliceForestHelp oldForest newForest acc =
    case ( oldForest, newForest ) of
        ( [], [] ) ->
            Just (List.reverse acc)

        ( oldTree :: oldRest, newTree :: newRest ) ->
            case spliceTree oldTree newTree of
                Just tree ->
                    spliceForestHelp oldRest newRest (tree :: acc)

                Nothing ->
                    Nothing

        _ ->
            Nothing


spliceTree : Tree ExpressionBlock -> Tree ExpressionBlock -> Maybe (Tree ExpressionBlock)
spliceTree oldTree newTree =
    let
        oldBlock =
            Tree.value oldTree

        newBlock =
            Tree.value newTree
    in
    if oldBlock.heading /= newBlock.heading || oldBlock.indent /= newBlock.indent || oldBlock.meta.id /= newBlock.meta.id then
        Nothing

    else
        let
            maybeBlock =
                if oldBlock.meta.sourceText == newBlock.meta.sourceText then
                    Just { oldBlock | meta = newBlock.meta }

                else if isAccumulatorIndependent oldBlock && isAccumulatorIndependent newBlock then
                    -- the old version must be checked too: removing a footnote,
                    -- reference, etc. also changes the accumulator
                    Just newBlock

                else
                    Nothing
        in
        case maybeBlock of
            Nothing ->
                Nothing

            Just block ->
                spliceIfAccIndependent (Tree.children oldTree) (Tree.children newTree)
                    |> Maybe.map (Tree.branch block)


{-| A block is accumulator-independent if it neither updates nor consumes
accumulator state. Currently: paragraphs without footnote/term/cite/ref/etc.,
and code blocks.
-}
isAccumulatorIndependent : ExpressionBlock -> Bool
isAccumulatorIndependent block =
    case block.heading of
        Paragraph ->
            case block.body of
                Left _ ->
                    True

                Right exprs ->
                    not (List.any exprUsesAccumulator exprs)

        Verbatim "code" ->
            True

        _ ->
            False


{-| Function names that interact with the accumulator during rendering or updating.
-}
accDependentNames : List String
accDependentNames =
    [ "footnote", "term", "index", "cite", "ref", "eqref", "label" ]


{-| Check if an expression tree references any accumulator-dependent functions.
-}
exprUsesAccumulator : Expression -> Bool
exprUsesAccumulator expr =
    case expr of
        Fun name children _ ->
            List.member name accDependentNames
                || List.any exprUsesAccumulator children

        Text _ _ ->
            False

        VFun _ _ _ ->
            False

        ExprList _ children _ ->
            List.any exprUsesAccumulator children


{-| Build an expression cache from a forest of ExpressionBlocks.
-}
buildExpressionCache : List (Tree ExpressionBlock) -> ExpressionCache
buildExpressionCache forest =
    forest
        |> List.concatMap flattenTree
        |> List.map (\block -> ( block.meta.sourceText, { lineNumber = block.meta.lineNumber, body = block.body } ))
        |> Dict.fromList


{-| Flatten a tree into a list of all blocks.
-}
flattenTree : Tree ExpressionBlock -> List ExpressionBlock
flattenTree tree =
    Tree.value tree
        :: List.concatMap flattenTree (Tree.children tree)


{-| Map a function over all values in a forest.
-}
mapForest : (a -> b) -> List (Tree a) -> List (Tree b)
mapForest f forest =
    List.map (Tree.mapValues f) forest
