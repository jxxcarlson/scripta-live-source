module Parser.Pipeline exposing (toExpressionBlock, toExpressionBlockCached, toExpressionBlockWithBody)

{-| Convert PrimitiveBlock to ExpressionBlock by parsing inline expressions.

    import Parser.Pipeline exposing (toExpressionBlock)

    primitiveBlock
        |> toExpressionBlock
        --> ExpressionBlock with parsed expressions in body

-}

import Dict
import Edit.Map
import Either exposing (Either(..))
import Parser.Expression as Expression
import Parser.ListItem as ListItem
import Parser.Table
import V3.Types exposing (BlockMeta, Expr(..), ExprMeta, Expression, ExpressionBlock, ExpressionCache, Heading(..), PrimitiveBlock)


{-| Convert a PrimitiveBlock to an ExpressionBlock.

For Verbatim blocks, the body is preserved as raw text (Left String).
For all other blocks, the body is parsed into expressions (Right (List Expression)).

-}
toExpressionBlock : PrimitiveBlock -> ExpressionBlock


toExpressionBlock block =
    toExpressionBlockWithBody (parseBody block) block


{-| Build an ExpressionBlock with a pre-computed body.
-}
toExpressionBlockWithBody : Either String (List Expression) -> PrimitiveBlock -> ExpressionBlock
toExpressionBlockWithBody body block =
    { heading = block.heading
    , indent = block.indent
    , args = block.args
    , properties = block.properties |> Dict.insert "id" block.meta.id
    , firstLine = block.firstLine
    , body = body
    , meta = block.meta
    , style = block.style
    }


{-| Convert a PrimitiveBlock to an ExpressionBlock, using the cache for expression parsing.
On a hit for a block that has moved, expression ids are shifted to the block's
new line, giving exactly what a fresh parse would.
-}
toExpressionBlockCached : ExpressionCache -> PrimitiveBlock -> ExpressionBlock
toExpressionBlockCached cache block =
    case Dict.get block.meta.sourceText cache of
        Just cached ->
            toExpressionBlockWithBody (shiftBodyIds (block.meta.lineNumber - cached.lineNumber) cached.body) block

        Nothing ->
            toExpressionBlock block


shiftBodyIds : Int -> Either String (List Expression) -> Either String (List Expression)
shiftBodyIds dL body =
    if dL == 0 then
        body

    else
        Either.map (List.map (Edit.Map.mapExprMeta (\m -> { m | id = Edit.Map.shiftExprId dL m.id }))) body


{-| Parse the body based on block heading type.
-}
parseBody : PrimitiveBlock -> Either String (List Expression)
parseBody block =
    case block.heading of
        Paragraph ->
            Right (parseLines block.meta.lineNumber block.body)

        Ordinary "item" ->
            Right (parseSingleItem block)

        Ordinary "numbered" ->
            Right (parseSingleItem block)

        Ordinary "itemList" ->
            Right (parseListItems block.meta.lineNumber (block.firstLine :: block.body))

        Ordinary "numberedList" ->
            Right (parseListItems block.meta.lineNumber (block.firstLine :: block.body))

        Ordinary "table" ->
            Right (Parser.Table.parseTable block.meta.bodyLineNumber block.body)

        Ordinary _ ->
            Right (parseLines block.meta.lineNumber block.body)

        Verbatim _ ->
            Left (String.join "\n" block.body)


{-| Single item: parse firstLine + body as one paragraph.
-}
parseSingleItem : PrimitiveBlock -> List Expression
parseSingleItem block =
    let
        content =
            (ListItem.stripPrefix block.firstLine :: block.body)
                |> String.join " "
    in
    [ ExprList block.indent (Expression.parse block.meta.lineNumber content) emptyExprMeta ]


{-| Multiple items: parse firstLine + each body line as a separate ExprList.
Each item becomes an ExprList with its own indent level.
Lines that don't start with "- " or ". " are appended to the previous item.
-}
parseListItems : Int -> List String -> List Expression
parseListItems lineNumber items =
    items
        |> groupListItems
        |> List.map
            (\item ->
                let
                    itemIndent =
                        measureIndent item
                in
                ExprList itemIndent (Expression.parse lineNumber (ListItem.stripPrefix item)) emptyExprMeta
            )


{-| Measure the indentation of a line (number of leading spaces).
-}
measureIndent : String -> Int
measureIndent str =
    String.length str - String.length (String.trimLeft str)


{-| Group list items: a line that is not itself a list item continues the
previous item.
-}
groupListItems : List String -> List String
groupListItems items =
    List.foldl
        (\line acc ->
            case ( ListItem.kind line, acc ) of
                ( Nothing, prev :: rest ) ->
                    (prev ++ " " ++ String.trim line) :: rest

                _ ->
                    line :: acc
        )
        []
        items
        |> List.reverse


{-| Parse multiple lines into a list of expressions.
-}
parseLines : Int -> List String -> List Expression
parseLines lineNumber lines =
    String.join "\n" lines |> Expression.parse lineNumber


{-| Empty expression metadata for synthetic expressions.
-}
emptyExprMeta : ExprMeta
emptyExprMeta =
    { begin = 0, end = 0, index = 0, id = "list" }
