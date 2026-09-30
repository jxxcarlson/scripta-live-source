module Common.Model exposing
    ( CommonModel
    , CommonMsg(..)
    , DisplaySettings
    , Flags
    , PdfError
    , PdfResponse
    , PrintingState(..)
    , SortOrder(..)
    , getTitle
    , getTitleFromContent
    , applyEdit
    , compilerEventCmd
    , contentWidth
    , initCommon
    , loadSource
    , makeOptions
    , refreshOptions
    , updateSource
    )

import Browser.Dom
import Document exposing (Document)
import Http
import Json.Decode as Decode
import Keyboard
import List.Extra
import Ports
import Scripta
import Theme
import Time


type PrintingState
    = PrintWaiting
    | PrintProcessing
    | PrintReady


type SortOrder
    = Alphabetical
    | Recent


type alias PdfError =
    { latexBegin : Int
    , latexEnd : Int
    , latexLine : Int
    , latexText : String
    , scriptaLine : Int
    }


type alias PdfResponse =
    { pdf : Maybe String
    , errorReport : Maybe String
    , hasErrors : Bool
    , pdfFailed : Bool
    , errorJson : Maybe (List PdfError)
    }


type alias DisplaySettings =
    { windowWidth : Int }


type alias CommonModel =
    { displaySettings : DisplaySettings
    , options : Scripta.Options
    , document : Scripta.Document
    , compilerOutput : Scripta.Output Scripta.Event
    , sourceText : String
    , count : Int
    , windowWidth : Int
    , windowHeight : Int
    , selectId : String
    , title : String
    , theme : Theme.Theme
    , pressedKeys : List Keyboard.Key
    , currentTime : Time.Posix
    , documents : List Document
    , currentDocument : Maybe Document
    , showDocumentList : Bool
    , sortOrder : SortOrder
    , documentSearchText : String
    , lastSaved : Time.Posix
    , lastChanged : Time.Posix
    , userName : Maybe String
    , printingState : PrintingState
    , pdfLink : String
    , pdfResponse : Maybe PdfResponse
    , pdfErrors : List PdfError
    , showPdfErrors : Bool

    -- EDITOR
    , lastLoadedDocumentId : Maybe String
    , initialText : String
    , loadDocumentIntoEditor : Bool
    , lastSavedDocumentId : Maybe String
    }


type CommonMsg
    = NoOp
    | InputText String
    | InputText2 { position : Int, source : String }
    | CompilerEvent Scripta.Event
    | GotNewWindowDimensions Int Int
    | KeyMsg Keyboard.Msg
    | ToggleTheme
    | CreateNewDocument
    | SaveDocument
    | LoadDocument String
    | DeleteDocument String
    | ToggleDocumentList
    | ToggleSortOrder
    | InputDocumentSearchText String
    | AutoSave Time.Posix
    | Tick Time.Posix
    | GeneratedId String
    | InitialDocumentId String String Time.Posix Theme.Theme String
    | ExportToLaTeX
    | ExportToRawLaTeX
    | ExportScriptaFile
    | ImportScriptaFile
    | ImportLaTeXFile
    | ImportMarkdownFile
    | PrintToPDF
    | GotPdfLink (Result Http.Error String)
    | GotPdfResponse (Result Http.Error PdfResponse)
    | DownloadScript
    | InputUserName String
    | LoadUserNameDelayed
    | LoadContentIntoEditorDelayed
    | ResetLoadFlag
    | PortMsgReceived (Result Decode.Error Ports.IncomingMsg)
    | LoadLastSavedDocumentId (Maybe String)
    | UpdateFileName String
    | UpdateFileDescription String
    | Export String
    | ReceiveFileContents String
    | AskForFileNameAndSave
    | AskForInitialFileNameAndLoad
    | ToggleEditMode
    | MarkCurrentDocumentDirty
    | SetCurrentDocument Document
    | GotViewPort (Result Browser.Dom.Error Browser.Dom.Viewport)
    | FocusOnEditorLine Int
    | TogglePdfErrors


type alias Flags =
    { window : { windowWidth : Int, windowHeight : Int }
    , currentTime : Int
    , theme : Maybe String
    }


initCommon : Flags -> CommonModel
initCommon flags =
    let
        theme =
            case flags.theme of
                Just "dark" ->
                    Theme.Dark

                _ ->
                    Theme.Light

        currentTime =
            Time.millisToPosix flags.currentTime

        displaySettings =
            { windowWidth = contentWidth flags.window.windowWidth }

        options =
            makeOptions theme displaySettings
    in
    { displaySettings = displaySettings
    , options = options
    , document = Scripta.parse options ""
    , compilerOutput = Scripta.render options (Scripta.parse options "")
    , sourceText = ""
    , count = 0
    , windowWidth = flags.window.windowWidth
    , windowHeight = flags.window.windowHeight
    , selectId = ""
    , title = ""
    , theme = theme
    , pressedKeys = []
    , currentTime = currentTime
    , documents = []
    , currentDocument = Nothing
    , showDocumentList = False
    , sortOrder = Alphabetical
    , documentSearchText = ""
    , lastSaved = currentTime
    , lastChanged = currentTime
    , userName = Just ""
    , printingState = PrintWaiting
    , pdfLink = ""
    , pdfResponse = Nothing
    , pdfErrors = []
    , showPdfErrors = False

    -- EDITOR
    , lastLoadedDocumentId = Nothing
    , initialText = ""
    , loadDocumentIntoEditor = False
    , lastSavedDocumentId = Nothing
    }


{-| Compiler options for the rendered-text panel. Document and title blocks
are hidden because the app shows the title in its own header.
-}
makeOptions : Theme.Theme -> DisplaySettings -> Scripta.Options
makeOptions theme displaySettings =
    Scripta.defaultOptions
        |> Scripta.withTheme (Theme.mapTheme theme)
        |> Scripta.withWindowWidth displaySettings.windowWidth
        |> Scripta.withContentWidth displaySettings.windowWidth
        |> Scripta.withTOC True
        |> Scripta.withFilter Scripta.SuppressDocumentBlocks


{-| Parse a new source from scratch (initial load, document switch).
-}
loadSource : String -> CommonModel -> CommonModel
loadSource source model =
    let
        document =
            Scripta.parse model.options source
    in
    { model
        | sourceText = source
        , document = document
        , compilerOutput = Scripta.render model.options document
    }


{-| Incrementally re-parse after an edit to the current source.
-}
updateSource : String -> CommonModel -> CommonModel
updateSource source model =
    let
        document =
            Scripta.reparse model.options model.document source
    in
    { model
        | sourceText = source
        , document = document
        , compilerOutput = Scripta.render model.options document
    }


{-| Rebuild the options from the theme and display settings (after a theme
toggle or window resize) and re-render.
-}
refreshOptions : CommonModel -> CommonModel
refreshOptions model =
    let
        options =
            makeOptions model.theme model.displaySettings
    in
    { model
        | options = options
        , compilerOutput = Scripta.render options model.document
    }


{-| Apply an edit from the editor: incremental reparse, title and change tracking.
-}
applyEdit : String -> CommonModel -> CommonModel
applyEdit source model =
    let
        newModel =
            updateSource source model
    in
    { newModel
        | title = getTitleFromContent source
        , lastChanged = model.currentTime
        , count = model.count + 1
    }


{-| Width of the rendered text column for a given window width:
half of what is left after the sidebar (230), TOC (221, shown from 1000px)
and borders, minus padding.
-}
contentWidth : Int -> Int
contentWidth windowWidth =
    let
        panelWidth =
            max 350
                ((windowWidth
                    - 230
                    - (if windowWidth >= 1000 then
                        221

                       else
                        0
                      )
                    - 3
                 )
                    // 2
                )
    in
    max 310 (panelWidth - 40)


{-| Clicks in the rendered text. Plain text clicks emit nothing in v3;
selecting rendered text is synced to the editor in JS (assets/editor-sync.js).
-}
compilerEventCmd : Scripta.Event -> Cmd msg
compilerEventCmd event =
    case event of
        Scripta.ClickedId id ->
            Ports.scrollToElement id

        Scripta.ClickedFootnote { targetId } ->
            Ports.scrollToElement targetId

        Scripta.ClickedCitation { targetId } ->
            Ports.scrollToElement targetId

        Scripta.HighlightedId _ ->
            Cmd.none

        Scripta.ClickedImage _ ->
            Cmd.none

        Scripta.ClickedLink _ ->
            Cmd.none


getTitle : CommonModel -> String
getTitle model =
    case model.currentDocument of
        Nothing ->
            "Scripta (No document)"

        Just doc ->
            "Scripta: " ++ doc.title


getTitleFromContent : String -> String
getTitleFromContent str =
    str
        |> String.lines
        |> List.map String.trim
        |> List.Extra.dropWhile (\line -> line == "" || String.startsWith "|" line)
        |> List.head
        |> Maybe.withDefault "No title yet"
