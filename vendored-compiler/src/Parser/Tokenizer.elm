module Parser.Tokenizer exposing
    ( Meta
    , Token
    , Token_(..)
    , getMeta
    , run
    )

import Parser.Advanced as Parser exposing (DeadEnd)
import Tools.Loop exposing (Step(..), loop)
import Tools.ParserTools as PT exposing (Context, Problem(..))


type Token_ meta
    = LB meta
    | DLB meta
    | RB meta
    | S String meta
    | W String meta
    | MathToken meta
    | CodeToken meta
    | TokenError (List (DeadEnd Context Problem)) meta


type alias Token =
    Token_ Meta


type alias Meta =
    { begin : Int, end : Int, index : Int }


type alias State a =
    { source : String
    , scanpointer : Int
    , tokenIndex : Int
    , sourceLength : Int
    , tokens : List a
    , currentToken : Maybe Token
    , mode : Mode
    }


type Mode
    = Normal
    | InMath
    | InCode


setIndex : Int -> Token -> Token
setIndex k token =
    case token of
        LB meta ->
            LB { meta | index = k }

        DLB meta ->
            DLB { meta | index = k }

        RB meta ->
            RB { meta | index = k }

        S str meta ->
            S str { meta | index = k }

        W str meta ->
            W str { meta | index = k }

        MathToken meta ->
            MathToken { meta | index = k }

        CodeToken meta ->
            CodeToken { meta | index = k }

        TokenError list meta ->
            TokenError list { meta | index = k }


getMeta : Token -> Meta
getMeta token =
    case token of
        LB m ->
            m

        DLB m ->
            m

        RB m ->
            m

        S _ m ->
            m

        W _ m ->
            m

        MathToken m ->
            m

        CodeToken m ->
            m

        TokenError _ m ->
            m


stringValue : Token -> String
stringValue token =
    case token of
        LB _ ->
            "["

        DLB _ ->
            "[["

        RB _ ->
            "]"

        S str _ ->
            str

        W str _ ->
            str

        MathToken _ ->
            "$"

        CodeToken _ ->
            "`"

        TokenError _ _ ->
            "tokenError"


length : Token -> Int
length token =
    let
        meta =
            getMeta token
    in
    meta.end - meta.begin


init : String -> State a
init str =
    { source = str
    , scanpointer = 0
    , sourceLength = String.length str
    , tokens = []
    , currentToken = Nothing
    , tokenIndex = 0
    , mode = Normal
    }


type alias TokenParser =
    Parser.Parser Context Problem Token


run : String -> List Token
run source =
    loop (init source) nextStep


get : State Token -> Int -> String -> Token
get state start input =
    case Parser.run (tokenParser state.mode start state.tokenIndex) input of
        Ok token ->
            token

        Err errorList ->
            TokenError errorList { begin = start, end = start + 1, index = state.tokenIndex }


nextStep : State Token -> Step (State Token) (List Token)
nextStep state =
    if state.scanpointer >= state.sourceLength then
        case state.currentToken of
            Just token ->
                Done (token :: state.tokens)

            Nothing ->
                Done state.tokens

    else
        let
            token =
                get state state.scanpointer (String.dropLeft state.scanpointer state.source)

            newScanPointer =
                state.scanpointer + length token + 1

            -- Adjacent text tokens accumulate in currentToken (already indexed
            -- at state.tokenIndex) and are flushed when a non-text token arrives.
            -- Text right after [ or [[ is the function name and is emitted alone.
            ( tokens, tokenIndex, currentToken ) =
                if isTextToken token then
                    if lastIsOpenBracket state.tokens then
                        ( setIndex state.tokenIndex token :: state.tokens, state.tokenIndex + 1, Nothing )

                    else
                        ( state.tokens, state.tokenIndex, updateCurrentToken state.tokenIndex token state.currentToken )

                else
                    case state.currentToken of
                        Nothing ->
                            ( setIndex state.tokenIndex token :: state.tokens, state.tokenIndex + 1, Nothing )

                        Just textToken ->
                            ( setIndex (state.tokenIndex + 1) token :: textToken :: state.tokens, state.tokenIndex + 2, Nothing )
        in
        Loop
            { state
                | tokens = tokens
                , scanpointer = newScanPointer
                , tokenIndex = tokenIndex
                , currentToken = currentToken
                , mode = newMode token state.mode
            }


updateCurrentToken : Int -> Token -> Maybe Token -> Maybe Token
updateCurrentToken index token currentToken =
    case currentToken of
        Nothing ->
            Just (setIndex index token)

        Just token_ ->
            Just <| setIndex index (mergeToken token_ token)


isTextToken : Token -> Bool
isTextToken token =
    case token of
        S _ _ ->
            True

        W _ _ ->
            True

        _ ->
            False


{-| True if the most recently emitted token (head of the reversed list) is `[` or `[[`.
-}
lastIsOpenBracket : List Token -> Bool
lastIsOpenBracket tokens =
    case tokens of
        (LB _) :: _ ->
            True

        (DLB _) :: _ ->
            True

        _ ->
            False


mergeToken : Token -> Token -> Token
mergeToken lastToken currentToken =
    let
        lastTokenMeta =
            getMeta lastToken

        currentTokenMeta =
            getMeta currentToken

        meta =
            { begin = lastTokenMeta.begin, end = currentTokenMeta.end, index = -1 }
    in
    S (stringValue lastToken ++ stringValue currentToken) meta


newMode : Token -> Mode -> Mode
newMode token currentMode =
    case currentMode of
        Normal ->
            case token of
                MathToken _ ->
                    InMath

                CodeToken _ ->
                    InCode

                _ ->
                    Normal

        InMath ->
            case token of
                MathToken _ ->
                    Normal

                _ ->
                    InMath

        InCode ->
            case token of
                CodeToken _ ->
                    Normal

                _ ->
                    InCode


tokenParser : Mode -> Int -> Int -> TokenParser
tokenParser mode start index =
    case mode of
        Normal ->
            tokenParser_ start index

        InMath ->
            mathParser_ start index

        InCode ->
            codeParser_ start index


languageChars =
    [ '[', ']', '`', '$', '\\' ]


mathChars =
    [ '$' ]


codeChars =
    [ '`' ]


tokenParser_ : Int -> Int -> TokenParser
tokenParser_ start index =
    Parser.oneOf
        [ whiteSpaceParser start index
        , textParser start index
        , parenMathOpenParser start index
        , parenMathCloseParser start index
        , backslashTextParser start index
        , doubleLeftBracketParser start index
        , leftBracketParser start index
        , rightBracketParser start index
        , mathParser start index
        , codeParser start index
        ]


{-| Parse backslash followed by letters as a single text token.
This ensures `\alpha` in Normal mode becomes `S "\\alpha"` rather than a TokenError.
-}
parenMathOpenParser : Int -> Int -> TokenParser
parenMathOpenParser start index =
    Parser.symbol (Parser.Token "\\(" (ExpectingSymbol "\\("))
        |> Parser.map (\_ -> MathToken { begin = start, end = start + 1, index = index })


parenMathCloseParser : Int -> Int -> TokenParser
parenMathCloseParser start index =
    Parser.symbol (Parser.Token "\\)" (ExpectingSymbol "\\)"))
        |> Parser.map (\_ -> MathToken { begin = start, end = start + 1, index = index })


backslashTextParser : Int -> Int -> TokenParser
backslashTextParser start index =
    PT.text (\c -> c == '\\') (\c -> Char.isAlpha c)
        |> Parser.map (\data -> S data.content { begin = start, end = start + data.end - data.begin - 1, index = index })


mathParser_ : Int -> Int -> TokenParser
mathParser_ start index =
    Parser.oneOf
        [ parenMathCloseParser start index
        , mathTextParser start index
        , mathParser start index
        , whiteSpaceParser start index
        ]


codeParser_ : Int -> Int -> TokenParser
codeParser_ start index =
    Parser.oneOf
        [ codeTextParser start index
        , codeParser start index
        , whiteSpaceParser start index
        ]


whiteSpaceParser : Int -> Int -> TokenParser
whiteSpaceParser start index =
    PT.text (\c -> c == ' ') (\c -> c == ' ')
        |> Parser.map (\data -> W data.content { begin = start, end = start, index = index })


doubleLeftBracketParser : Int -> Int -> TokenParser
doubleLeftBracketParser start index =
    Parser.symbol (Parser.Token "[[" (ExpectingSymbol "[["))
        |> Parser.map (\_ -> DLB { begin = start, end = start + 1, index = index })


leftBracketParser : Int -> Int -> TokenParser
leftBracketParser start index =
    PT.text (\c -> c == '[') (\_ -> False)
        |> Parser.map (\_ -> LB { begin = start, end = start, index = index })


rightBracketParser : Int -> Int -> TokenParser
rightBracketParser start index =
    PT.text (\c -> c == ']') (\_ -> False)
        |> Parser.map (\_ -> RB { begin = start, end = start, index = index })


textParser : Int -> Int -> TokenParser
textParser =
    textParserStoppingAt languageChars


mathTextParser : Int -> Int -> TokenParser
mathTextParser =
    textParserStoppingAt mathChars


codeTextParser : Int -> Int -> TokenParser
codeTextParser =
    textParserStoppingAt codeChars


{-| A run of text. The first character may not be a space or one of `firstStopChars`;
subsequent characters may not be a space or any language character.
-}
textParserStoppingAt : List Char -> Int -> Int -> TokenParser
textParserStoppingAt firstStopChars start index =
    PT.text (\c -> not <| List.member c (' ' :: firstStopChars)) (\c -> not <| List.member c (' ' :: languageChars))
        |> Parser.map (\data -> S data.content { begin = start, end = start + data.end - data.begin - 1, index = index })


mathParser : Int -> Int -> TokenParser
mathParser start index =
    PT.text (\c -> c == '$') (\_ -> False)
        |> Parser.map (\_ -> MathToken { begin = start, end = start, index = index })


codeParser : Int -> Int -> TokenParser
codeParser start index =
    PT.text (\c -> c == '`') (\_ -> False)
        |> Parser.map (\_ -> CodeToken { begin = start, end = start, index = index })
