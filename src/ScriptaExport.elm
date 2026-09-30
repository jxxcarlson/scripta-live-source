module ScriptaExport exposing (imageUrls, latex, rawLatex)

{-| Exports that need the parsed forest, which the public `Scripta` API keeps
opaque. The source is re-parsed without the display filter, because the
rendered-text panel hides `title` and `document` blocks at parse time, while
the LaTeX exporter needs them.
-}

import Either exposing (Either(..))
import Generic.ASTTools
import Library.Tree
import List.Extra
import Render.Export.LaTeX
import Render.Settings
import Render.Types
import RoseTree.Tree exposing (Tree)
import Scripta
import Scripta.Internal exposing (Document(..))
import Time
import V3.Types exposing (ExpressionBlock, Heading(..))


{-| Complete LaTeX document (preamble, title, body).
-}
latex : { title : String, date : Time.Posix } -> String -> String
latex { title, date } source =
    Render.Export.LaTeX.export
        { title = title
        , authorList = []
        , kind = Render.Types.DKArticle
        , date = Left date
        }
        Render.Settings.defaultRenderSettings
        (forest source)


{-| LaTeX body only, without preamble.
-}
rawLatex : String -> String
rawLatex source =
    Render.Export.LaTeX.rawExport Render.Settings.defaultRenderSettings (forest source)


{-| Urls of all images, from `[image ...]` elements and `| image` blocks.
-}
imageUrls : String -> List String
imageUrls source =
    let
        blocks =
            forest source
                |> List.concatMap Library.Tree.flatten

        fromExpressions =
            blocks
                |> List.concatMap (\block -> Either.toList block.body |> List.concat)
                |> Generic.ASTTools.filterExpressionsOnName_ "image"
                |> List.filterMap (Generic.ASTTools.getText >> Maybe.map String.trim)
                |> List.filterMap (String.split " " >> List.head)

        fromBlocks =
            blocks
                |> List.filter (\block -> block.heading == Verbatim "image" || block.heading == Ordinary "image")
                |> List.filterMap verbatimContent
    in
    (fromExpressions ++ fromBlocks)
        |> List.sort
        |> List.Extra.unique


forest : String -> List (Tree ExpressionBlock)
forest source =
    let
        (Document data) =
            Scripta.parse (Scripta.defaultOptions |> Scripta.withFilter Scripta.NoFilter) source
    in
    data.forest


verbatimContent : ExpressionBlock -> Maybe String
verbatimContent block =
    case block.body of
        Left str ->
            Just (String.trim str)

        Right _ ->
            Nothing
