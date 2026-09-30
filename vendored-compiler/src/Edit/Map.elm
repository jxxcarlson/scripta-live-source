module Edit.Map exposing
    ( Edit
    , charDelta, lineDelta
    , shiftBlockId, shiftExprId
    , mapExprMeta
    , applyEditToForest
    )

{-| Fast, pure metadata shift for RL-sync. See mydocs/diff-update-map-strategy.md.

@docs Edit
@docs charDelta, lineDelta
@docs shiftBlockId, shiftExprId
@docs mapExprMeta
@docs applyEditToForest

-}

import Either
import RoseTree.Tree as Tree exposing (Tree)
import V3.Types exposing (Expr(..), ExprMeta, Expression, ExpressionBlock)


{-| A single edit against the pre-edit document (CodeMirror-style change).
-}
type alias Edit =
    { offset : Int
    , removed : String
    , inserted : String
    }


{-| Net change in character count produced by the edit.
-}
charDelta : Edit -> Int
charDelta edit =
    String.length edit.inserted - String.length edit.removed


{-| Net change in newline count produced by the edit.
-}
lineDelta : Edit -> Int
lineDelta edit =
    countNewlines edit.inserted - countNewlines edit.removed


countNewlines : String -> Int
countNewlines s =
    List.length (String.indexes "\n" s)


{-| Bump the leading line-number component of a block id ("L-I") by dL.
Leaves the id unchanged if it is not of the expected form.
-}
shiftBlockId : Int -> String -> String
shiftBlockId dL id =
    case String.split "-" id of
        lineStr :: rest ->
            case String.toInt lineStr of
                Just l ->
                    String.join "-" (String.fromInt (l + dL) :: rest)

                Nothing ->
                    id

        _ ->
            id


{-| Bump the line-number component of an expression id ("e-L.T") by dL.
Leaves the id unchanged if it is not of the expected form.
-}
shiftExprId : Int -> String -> String
shiftExprId dL id =
    if String.startsWith "e-" id then
        case String.split "." (String.dropLeft 2 id) of
            lineStr :: rest ->
                case String.toInt lineStr of
                    Just l ->
                        "e-" ++ String.fromInt (l + dL) ++ "." ++ String.join "." rest

                    Nothing ->
                        id

            _ ->
                id

    else
        id


{-| Apply f to every ExprMeta in an expression tree.
-}
mapExprMeta : (ExprMeta -> ExprMeta) -> Expression -> Expression
mapExprMeta f expr =
    case expr of
        Text s m ->
            Text s (f m)

        Fun name args m ->
            Fun name (List.map (mapExprMeta f) args) (f m)

        VFun name s m ->
            VFun name s (f m)

        ExprList indent args m ->
            ExprList indent (List.map (mapExprMeta f) args) (f m)


{-| Apply one edit's metadata shift across the whole forest.
-}
applyEditToForest : Edit -> List (Tree ExpressionBlock) -> List (Tree ExpressionBlock)
applyEditToForest edit forest =
    let
        p =
            edit.offset

        dC =
            charDelta edit

        dL =
            lineDelta edit
    in
    if p < 0 || (dC == 0 && dL == 0) then
        forest

    else
        List.map (Tree.mapValues (shiftBlock p dC dL)) forest


shiftBlock : Int -> Int -> Int -> ExpressionBlock -> ExpressionBlock
shiftBlock p dC dL block =
    let
        m =
            block.meta
    in
    if m.end < p then
        -- entirely above the edit
        block

    else if m.begin > p then
        -- entirely below the edit: shift offsets, line numbers, ids
        { block
            | meta =
                { m
                    | position = m.position + dC
                    , begin = m.begin + dC
                    , end = m.end + dC
                    , contentBegin = m.contentBegin + dC
                    , contentEnd = m.contentEnd + dC
                    , lineNumber = m.lineNumber + dL
                    , bodyLineNumber = m.bodyLineNumber + dL
                    , id =
                        if dL == 0 then
                            m.id

                        else
                            shiftBlockId dL m.id
                }
            , body =
                if dL == 0 then
                    block.body

                else
                    shiftBodyIds dL block.body
        }

    else
        -- the edit lands inside this block: grow it, do not reparse content
        { block
            | meta =
                { m
                    | end = m.end + dC
                    , contentEnd = m.contentEnd + dC
                    , numberOfLines = m.numberOfLines + dL
                }
        }


shiftBodyIds : Int -> Either.Either String (List Expression) -> Either.Either String (List Expression)
shiftBodyIds dL body =
    Either.map
        (List.map (mapExprMeta (\meta -> { meta | id = shiftExprId dL meta.id })))
        body
