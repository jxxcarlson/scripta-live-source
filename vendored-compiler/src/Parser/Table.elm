module Parser.Table exposing (parseTable)

import Parser.Expression
import V3.Types


{-| Parse table rows into one ExprList per row, each holding one ExprList per cell.
`firstLineNumber` is the source line of the first row; expression ids in row `k`
use line `firstLineNumber + k`.
-}
parseTable : Int -> List String -> List V3.Types.Expression
parseTable firstLineNumber rows =
    List.indexedMap (\row -> parseRow (firstLineNumber + row) row) rows


parseRow : Int -> Int -> String -> V3.Types.Expression
parseRow lineNumber row str =
    List.indexedMap (\col -> parseCell lineNumber row col) (String.split "&" str)
        |> (\exprs -> V3.Types.ExprList 0 exprs { begin = 0, end = String.length str, index = 0, id = "row-" ++ String.fromInt row })


parseCell : Int -> Int -> Int -> String -> V3.Types.Expression
parseCell lineNumber row col str =
    str
        |> String.trim
        |> Parser.Expression.parse lineNumber
        |> (\exprs -> V3.Types.ExprList 0 exprs { begin = 0, end = String.length str, index = 0, id = "cell-" ++ String.fromInt row ++ "-" ++ String.fromInt col })
