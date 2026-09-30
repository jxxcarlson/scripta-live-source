module Parser.Match exposing (getSegment, isReducible, match, splitAt, splitMatchedBy)

import List.Extra
import Parser.Symbol exposing (Symbol(..), value)


isReducible : List Symbol -> Bool
isReducible symbols_ =
    let
        symbols =
            List.filter (\sym -> sym /= WS) symbols_
    in
    case symbols of
        M :: rest ->
            List.head (List.reverse rest) == Just M

        C :: rest ->
            List.head (List.reverse rest) == Just C

        L :: ST :: rest ->
            case List.head (List.reverse rest) of
                Just R ->
                    hasReducibleArgs (dropLast rest)

                _ ->
                    False

        DL :: rest ->
            case lastTwo rest of
                Just ( R, R ) ->
                    isFlatBody (dropLast2 rest)

                _ ->
                    False

        _ ->
            False


{-| True if the symbols are a sequence of strings and reducible segments.
Self-recursive in tail position, so long argument lists do not grow the stack.
-}
hasReducibleArgs : List Symbol -> Bool
hasReducibleArgs symbols =
    case symbols of
        [] ->
            True

        ST :: rest ->
            hasReducibleArgs rest

        M :: _ ->
            let
                seg =
                    getSegment M symbols
            in
            if isReducible seg then
                hasReducibleArgs (List.drop (List.length seg) symbols)

            else
                False

        first :: _ ->
            if first == L || first == DL || first == C then
                case splitMatchedBy identity symbols of
                    Nothing ->
                        False

                    Just ( a, b ) ->
                        if isReducible a then
                            hasReducibleArgs b

                        else
                            False

            else
                False


{-| Split `items` just after the segment that `matchBy` finds at its head.
-}
splitMatchedBy : (a -> Symbol) -> List a -> Maybe ( List a, List a )
splitMatchedBy toSymbol items =
    matchBy toSymbol items |> Maybe.map (\k -> splitAt (k + 1) items)


dropLast : List a -> List a
dropLast list =
    let
        n =
            List.length list
    in
    List.take (n - 1) list


splitAt : Int -> List a -> ( List a, List a )
splitAt k list =
    ( List.take k list, List.drop k list )


getSegment : Symbol -> List Symbol -> List Symbol
getSegment sym symbols =
    let
        seg_ =
            List.Extra.takeWhile (\sym_ -> sym_ /= sym) (List.drop 1 symbols)

        n =
            List.length seg_
    in
    case List.Extra.getAt (n + 1) symbols of
        Nothing ->
            sym :: seg_

        Just last ->
            sym :: seg_ ++ [ last ]


{-| Index of the last item of the segment at the head of the list, or Nothing
if there is no such segment. A `$` or backtick segment runs to the next matching
delimiter (or to the end of the list if unclosed); a bracket segment runs until
the brackets balance.
-}
match : List Symbol -> Maybe Int
match =
    matchBy identity


{-| `match` over any list, given a way to view each item as a Symbol.
Items are converted only as far as the segment extends, so callers can pass a
long list without converting all of it.
-}
matchBy : (a -> Symbol) -> List a -> Maybe Int
matchBy toSymbol items =
    case items of
        [] ->
            Nothing

        first :: rest ->
            let
                symbol =
                    toSymbol first
            in
            if symbol == C || symbol == M then
                Just (delimiterEnd toSymbol symbol 1 rest)

            else if value symbol < 0 then
                Nothing

            else
                bracketEnd toSymbol (value symbol) 1 rest


delimiterEnd : (a -> Symbol) -> Symbol -> Int -> List a -> Int
delimiterEnd toSymbol delimiter index items =
    case items of
        [] ->
            -- unclosed: the segment runs to the last item
            index - 1

        item :: rest ->
            if toSymbol item == delimiter then
                index

            else
                delimiterEnd toSymbol delimiter (index + 1) rest


bracketEnd : (a -> Symbol) -> Int -> Int -> List a -> Maybe Int
bracketEnd toSymbol brackets index items =
    case items of
        [] ->
            Nothing

        item :: rest ->
            let
                newBrackets =
                    brackets + value (toSymbol item)
            in
            if newBrackets < 0 then
                Nothing

            else if newBrackets == 0 then
                Just index

            else
                bracketEnd toSymbol newBrackets (index + 1) rest



-- LIST HELPERS

lastTwo : List a -> Maybe ( a, a )
lastTwo list =
    case List.reverse list of
        b :: a :: _ ->
            Just ( a, b )

        _ ->
            Nothing


dropLast2 : List a -> List a
dropLast2 list =
    let
        n =
            List.length list
    in
    List.take (n - 2) list


isFlatBody : List Symbol -> Bool
isFlatBody symbols =
    List.all (\s -> s == ST) symbols

