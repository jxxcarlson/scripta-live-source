module Parser.Expression exposing (parse)

{-|

    > import Types exposing(..)
    > import Parser.Expression exposing(parse)

    > parse 0 "hello"
    [Text "hello" { begin = 0, end = 4, index = 0, id = "e-0.0" }]

    > parse 0 "This is [b important]"
    [Text "This is " ..., Fun "b" [Text "important" ...] ...]

    > parse 0 "I like $a^2 + b^2 = c^2$"
    [Text "I like " ..., VFun "math" "a^2 + b^2 = c^2" ...]

-}

import List.Extra
import Parser.Match as M
import Parser.Symbol as Symbol exposing (Symbol(..))
import Parser.Tokenizer as Token exposing (Meta, Token, Token_(..))
import Tools.Loop exposing (Step(..), loop)
import V3.Types exposing (Expr(..), ExprMeta, Expression)


type alias State =
    { tokens : List Token -- tokens not yet consumed
    , allTokens : List Token -- the full token list, for resuming after an error
    , committed : List Expression
    , stack : List Token
    , depth : Int -- net bracket value of the stack: [ is +1, [[ is +2, ] is -1
    , lineNumber : Int
    , source : String
    }


parse : Int -> String -> List Expression
parse lineNumber str =
    str
        |> Token.run
        |> initWithTokens lineNumber str
        |> run
        |> .committed
        |> List.map trimFirstArg


{-| Trim the leading text argument of a top-level function (the space after its name).
-}
trimFirstArg : Expression -> Expression
trimFirstArg expr =
    case expr of
        Fun name ((Text str meta_) :: tail) meta ->
            Fun name (Text (String.trim str) meta_ :: tail) meta

        _ ->
            expr


initWithTokens : Int -> String -> List Token -> State
initWithTokens lineNumber source tokens =
    let
        tokens_ =
            List.reverse tokens
    in
    { tokens = tokens_
    , allTokens = tokens_
    , committed = []
    , stack = []
    , depth = 0
    , lineNumber = lineNumber
    , source = source
    }


run : State -> State
run state =
    loop state nextStep
        |> (\state_ -> { state_ | committed = List.reverse state_.committed })


nextStep : State -> Step State State
nextStep state =
    case state.tokens of
        [] ->
            if stackIsEmpty state then
                Done state

            else
                recoverFromError state

        token :: rest ->
            { state | tokens = rest }
                |> pushOrCommit token
                |> reduceState
                |> Loop


stackIsEmpty : State -> Bool
stackIsEmpty state =
    List.isEmpty state.stack


pushOrCommit : Token -> State -> State
pushOrCommit token state =
    case ( token, state.stack ) of
        ( S _ _, [] ) ->
            commit token state

        ( W _ _, [] ) ->
            commit token state

        _ ->
            push token state


push : Token -> State -> State
push token state =
    { state | stack = token :: state.stack, depth = state.depth + bracketValue token }


bracketValue : Token -> Int
bracketValue token =
    case token of
        LB _ ->
            1

        DLB _ ->
            2

        RB _ ->
            -1

        _ ->
            0


commit : Token -> State -> State
commit token state =
    case stringTokenToExpr state.lineNumber token of
        Nothing ->
            state

        Just expr ->
            { state | committed = expr :: state.committed }


stringTokenToExpr : Int -> Token -> Maybe Expression
stringTokenToExpr lineNumber token =
    case token of
        S str loc ->
            Just (Text str (boostMeta lineNumber loc.index loc))

        W str loc ->
            Just (Text str (boostMeta lineNumber loc.index loc))

        _ ->
            Nothing


reduceState : State -> State
reduceState state =
    if tokensAreReducible state then
        { state | stack = [], depth = 0, committed = reduceStack state ++ state.committed }

    else
        state


{-| `M.isReducible` walks the whole stack, so only call it when the stack could
be reducible. A reducible stack always has net bracket value 0 (a function's
arguments are balanced, and math/code segments contain no bracket tokens), and
its last non-space token closes something: `]`, `$`, or a backtick. Pushing a
space never changes reducibility, because `isReducible` ignores spaces. So when
this precheck fails, `isReducible` would have returned False.
-}
tokensAreReducible : State -> Bool
tokensAreReducible state =
    let
        couldReduce =
            state.depth
                == 0
                && (case state.stack of
                        (RB _) :: _ ->
                            True

                        (MathToken _) :: _ ->
                            True

                        (CodeToken _) :: _ ->
                            True

                        _ ->
                            False
                   )
    in
    couldReduce && M.isReducible (state.stack |> Symbol.toSymbols |> List.reverse)


reduceStack : State -> List Expression
reduceStack state =
    reduceTokens state.lineNumber state.source (state.stack |> List.reverse)


reduceTokens : Int -> String -> List Token -> List Expression
reduceTokens lineNumber source tokens =
    case tokens of
        (DLB dlbMeta) :: rest ->
            reduceWikilink lineNumber source dlbMeta rest

        _ ->
            reduceTokensNonWikilink lineNumber source tokens


reduceTokensNonWikilink : Int -> String -> List Token -> List Expression
reduceTokensNonWikilink lineNumber source tokens =
    if isExpr tokens then
        let
            args =
                unbracket tokens
        in
        case args of
            (S name meta) :: rest ->
                if List.member name verbatimFunctionNames then
                    -- For verbatim functions like [m ...], [math ...], [chem ...],
                    -- collect all remaining tokens as a single string
                    let
                        content =
                            rest
                                |> List.filterMap tokenToString
                                |> String.join ""
                                |> String.trim
                    in
                    [ VFun name content (boostMeta lineNumber meta.index meta) ]

                else
                    [ Fun name (reduceRestOfTokens lineNumber source (List.drop 1 args)) (boostMeta lineNumber meta.index meta) ]

            _ ->
                [ errorMessage "[????]" ]

    else
        case tokens of
            (MathToken meta) :: (S str _) :: (MathToken closeMeta) :: rest ->
                VFun "math" str (boostMeta lineNumber meta.index { meta | end = closeMeta.begin }) :: reduceRestOfTokens lineNumber source rest

            (MathToken meta) :: rest ->
                -- Multi-token math content: collect everything up to closing MathToken
                let
                    inner =
                        List.Extra.takeWhile (not << isMathToken) rest

                    closingToken =
                        List.drop (List.length inner) rest |> List.head

                    closeEnd =
                        case closingToken of
                            Just (MathToken cm) ->
                                cm.begin

                            _ ->
                                meta.end

                    after =
                        List.drop (List.length inner + 1) rest

                    content =
                        inner
                            |> List.filterMap tokenToString
                            |> String.join ""
                in
                VFun "math" content (boostMeta lineNumber meta.index { meta | end = closeEnd }) :: reduceRestOfTokens lineNumber source after

            (CodeToken meta) :: (S str _) :: (CodeToken closeMeta) :: rest ->
                VFun "code" str (boostMeta lineNumber meta.index { meta | end = closeMeta.begin }) :: reduceRestOfTokens lineNumber source rest

            _ ->
                [ errorMessage "[????]" ]


reduceRestOfTokens : Int -> String -> List Token -> List Expression
reduceRestOfTokens lineNumber source tokens =
    reduceRestOfTokensHelp lineNumber source tokens []


{-| Accumulator loop, so a function with thousands of arguments does not grow the stack.
-}
reduceRestOfTokensHelp : Int -> String -> List Token -> List Expression -> List Expression
reduceRestOfTokensHelp lineNumber source tokens acc =
    case tokens of
        [] ->
            List.reverse acc

        token :: rest ->
            if startsSegment token then
                case splitTokens tokens of
                    Nothing ->
                        List.reverse (Text "error on match" dummyLocWithId :: acc)

                    Just ( a, b ) ->
                        reduceRestOfTokensHelp lineNumber source b (List.reverse (reduceTokens lineNumber source a) ++ acc)

            else
                case stringTokenToExpr lineNumber token of
                    Just expr ->
                        reduceRestOfTokensHelp lineNumber source rest (expr :: acc)

                    Nothing ->
                        List.reverse (Text "error converting Token" dummyLocWithId :: acc)


{-| Tokens that open a segment: a function `[`, a wikilink `[[`, math `$`, or code `` ` ``.
-}
startsSegment : Token -> Bool
startsSegment token =
    case token of
        LB _ ->
            True

        DLB _ ->
            True

        MathToken _ ->
            True

        CodeToken _ ->
            True

        _ ->
            False


recoverFromError : State -> Step State State
recoverFromError state =
    case List.reverse state.stack of
        (DLB dlbMeta) :: _ ->
            let
                closeMeta =
                    case List.head state.stack of
                        Just t ->
                            Token.getMeta t

                        Nothing ->
                            dlbMeta
            in
            stopWith (redLiteral state.lineNumber dlbMeta closeMeta state.source) state

        (LB _) :: (RB meta) :: _ ->
            resumeAfter meta (errorMessage "[?]") state

        (LB _) :: (S fName meta) :: _ ->
            resumeAfter meta (errorMessage ("[" ++ fName ++ "]?")) state

        (LB _) :: (W " " meta) :: _ ->
            resumeAfter meta (errorMessage "[ - can't have space after the bracket ") state

        (LB _) :: [] ->
            stopWith (errorMessage "[...?") state

        (RB meta) :: _ ->
            resumeAfter meta (errorMessage " extra ]?") state

        (MathToken meta) :: _ ->
            resumeAfter meta (errorMessage "$?$") state

        (CodeToken meta) :: _ ->
            resumeAfter meta (errorMessage "`?`") state

        _ ->
            stopWith (errorMessage " ?!? ") state


{-| Commit an error expression, clear the stack, and resume parsing after the given token.
-}
resumeAfter : Meta -> Expression -> State -> Step State State
resumeAfter meta expr state =
    Loop
        { state
            | committed = expr :: state.committed
            , stack = []
            , depth = 0
            , tokens = List.drop (meta.index + 1) state.allTokens
        }


{-| Commit an error expression and stop parsing.
-}
stopWith : Expression -> State -> Step State State
stopWith expr state =
    Done { state | committed = expr :: state.committed, stack = [], depth = 0 }



-- HELPERS


unbracket : List a -> List a
unbracket list =
    List.drop 1 (List.take (List.length list - 1) list)


isExpr : List Token -> Bool
isExpr tokens =
    case ( tokens, List.reverse tokens ) of
        ( (LB _) :: _, (RB _) :: _ ) ->
            True

        _ ->
            False


boostMeta : Int -> Int -> { begin : Int, end : Int, index : Int } -> ExprMeta
boostMeta lineNumber tokenIndex { begin, end, index } =
    { begin = begin, end = end, index = index, id = makeId lineNumber tokenIndex }


splitTokens : List Token -> Maybe ( List Token, List Token )
splitTokens tokens =
    M.splitMatchedBy Symbol.toSymbol tokens


makeId : Int -> Int -> String
makeId lineNumber tokenIndex =
    "e-" ++ String.fromInt lineNumber ++ "." ++ String.fromInt tokenIndex


dummyLocWithId : ExprMeta
dummyLocWithId =
    { begin = 0, end = 0, index = 0, id = "dummy" }


errorMessage : String -> Expression
errorMessage message =
    Fun "errorHighlight" [ Text message dummyLocWithId ] dummyLocWithId


{-| List of function names that should be parsed as VFun (verbatim functions).
These functions receive their content as a raw string rather than parsed expressions.
-}
verbatimFunctionNames : List String
verbatimFunctionNames =
    [ "m", "math", "chem", "code" ]


isMathToken : Token -> Bool
isMathToken token =
    case token of
        MathToken _ ->
            True

        _ ->
            False


{-| Convert a token to its string representation for verbatim functions.
-}
tokenToString : Token -> Maybe String
tokenToString token =
    case token of
        S str _ ->
            Just str

        W str _ ->
            Just str

        LB _ ->
            Just "["

        RB _ ->
            Just "]"

        _ ->
            Nothing


reduceWikilink : Int -> String -> Meta -> List Token -> List Expression
reduceWikilink lineNumber source dlbMeta rest =
    case splitOffWikilinkBody rest of
        Just ( body, closeMeta ) ->
            if List.any isSToken body then
                let
                    spanMeta =
                        boostMeta lineNumber dlbMeta.index { dlbMeta | end = closeMeta.end }
                in
                [ Fun "wikilink" (wikilinkArgs lineNumber body) spanMeta ]

            else
                [ redLiteral lineNumber dlbMeta closeMeta source ]

        Nothing ->
            [ redLiteral lineNumber dlbMeta (lastMeta rest) source ]


splitOffWikilinkBody : List Token -> Maybe ( List Token, Meta )
splitOffWikilinkBody tokens =
    case List.reverse tokens of
        (RB m2) :: (RB _) :: revBody ->
            let
                body =
                    List.reverse revBody
            in
            if List.all isFlatBodyToken body then
                Just ( body, m2 )

            else
                Nothing

        _ ->
            Nothing


isFlatBodyToken : Token -> Bool
isFlatBodyToken token =
    case token of
        S _ _ ->
            True

        W _ _ ->
            True

        _ ->
            False


isSToken : Token -> Bool
isSToken token =
    case token of
        S str _ ->
            String.trim str /= ""

        _ ->
            False


wikilinkArgs : Int -> List Token -> List Expression
wikilinkArgs lineNumber tokens =
    List.filterMap (stringTokenToExpr lineNumber) tokens


lastMeta : List Token -> Meta
lastMeta tokens =
    case List.reverse tokens of
        t :: _ ->
            Token.getMeta t

        [] ->
            { begin = 0, end = 0, index = 0 }


redLiteral : Int -> Meta -> Meta -> String -> Expression
redLiteral lineNumber dlbMeta closeMeta source =
    let
        sliced =
            String.slice dlbMeta.begin (closeMeta.end + 1) source

        spanMeta =
            boostMeta lineNumber dlbMeta.index
                { begin = dlbMeta.begin, end = closeMeta.end, index = dlbMeta.index }
    in
    Fun "red" [ Text sliced spanMeta ] spanMeta
