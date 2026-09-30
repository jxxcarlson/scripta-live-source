module Parser.Line exposing (Line, classify)

{-| Line classification for the parser.
-}


type alias Line =
    { indent : Int
    , content : String
    , lineNumber : Int
    , position : Int
    }


{-| Classify a raw string into a Line record.
-}
classify : Int -> Int -> String -> Line
classify position lineNumber str =
    { indent = countLeadingSpaces str
    , content = str
    , lineNumber = lineNumber
    , position = position
    }


{-| Count leading space characters only; tabs do not count as indentation.
-}
countLeadingSpaces : String -> Int
countLeadingSpaces str =
    String.length str - String.length (dropLeadingSpaces str)


dropLeadingSpaces : String -> String
dropLeadingSpaces str =
    if String.startsWith " " str then
        dropLeadingSpaces (String.dropLeft 1 str)

    else
        str
