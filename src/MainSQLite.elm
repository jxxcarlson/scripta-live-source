module MainSQLite exposing (main)

import AppData
import Browser
import Browser.Dom
import Browser.Events
import Common.Model as Common
import Common.View
import Constants exposing (constants)
import Dict
import Document exposing (Document)
import Either
import LaTeXToScripta
import Element exposing (..)
import File
import File.Download
import File.Select
import Frontend.PDF
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Keyboard
import List.Extra
import MarkdownToScripta
import Ports
import Process
import Random
import Scripta
import ScriptaExport
import Storage.Interface as Storage
import Storage.SQLite
import Task
import Theme
import Time



-- MAIN


main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { common : Common.CommonModel
    , storageState : Storage.SQLite.State
    }


type Msg
    = CommonMsg Common.CommonMsg
    | StorageMsg Storage.StorageMsg
    | FileSelected File.File
    | FileLoaded String
    | LaTeXFileSelected File.File
    | LaTeXFileLoaded { filename : String, content : String }
    | MarkdownFileSelected File.File
    | MarkdownFileLoaded { filename : String, content : String }



-- INIT


init : Common.Flags -> ( Model, Cmd Msg )
init flags =
    let
        common =
            Common.initCommon flags

        storage =
            Storage.SQLite.storage StorageMsg

        updatedCommon =
            { common
                | showDocumentList = True
            }
    in
    ( { common = updatedCommon
      , storageState = Storage.SQLite.init
      }
    , Cmd.batch
        [ storage.init
        , Task.perform (CommonMsg << Common.Tick) Time.now
        , Process.sleep 100
            |> Task.perform (always (CommonMsg Common.LoadUserNameDelayed))
        ]
    )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CommonMsg commonMsg ->
            updateCommon commonMsg model

        StorageMsg storageMsg ->
            handleStorageMsg storageMsg model

        FileSelected file ->
            ( model
            , Task.perform FileLoaded (File.toString file)
            )

        FileLoaded content ->
            let
                -- First update the content in the editor
                ( modelWithContent, cmdFromUpdate ) =
                    updateCommon (Common.InputText content) model

                -- Extract the title from the content
                title =
                    Common.getTitleFromContent content

                -- Generate a new document ID
                newId =
                    "imported-" ++ String.fromInt (Time.posixToMillis modelWithContent.common.currentTime // 1)

                -- Create a new document
                newDoc =
                    Document.newDocument
                        newId
                        title
                        (Maybe.withDefault "" modelWithContent.common.userName)
                        content
                        modelWithContent.common.theme
                        modelWithContent.common.currentTime

                -- Update the model with the new document
                updatedCommon =
                    let
                        oldCommon =
                            modelWithContent.common
                    in
                    { oldCommon
                        | currentDocument = Just newDoc
                        , documents = newDoc :: modelWithContent.common.documents
                        , lastLoadedDocumentId = Just newId
                        , sourceText = content
                        , initialText = content
                        , loadDocumentIntoEditor = True
                    }

                updatedModel =
                    { modelWithContent | common = updatedCommon }

                -- Get the storage command to save the document
                storage =
                    Storage.SQLite.storage StorageMsg
            in
            ( updatedModel
            , Cmd.batch
                [ cmdFromUpdate
                , storage.saveDocument newDoc
                , Process.sleep 100
                    |> Task.perform (always (CommonMsg Common.ResetLoadFlag))
                ]
            )

        LaTeXFileSelected file ->
            ( model
            , Task.perform (\content -> LaTeXFileLoaded { filename = File.name file, content = content }) (File.toString file)
            )

        LaTeXFileLoaded { filename, content } ->
            let
                -- Extract basename from filename (remove .tex extension if present)
                basename =
                    if String.endsWith ".tex" filename then
                        String.dropRight 4 filename

                    else
                        filename

                -- Translate LaTeX to Scripta
                translatedContent =
                    LaTeXToScripta.convert content

                -- Add title block at the top
                scriptaContent =
                    "| title\n" ++ basename ++ "\n\n" ++ translatedContent

                -- First update the content in the editor
                ( modelWithContent, cmdFromUpdate ) =
                    updateCommon (Common.InputText scriptaContent) model

                -- Generate a new document ID with .scripta extension indication
                newId =
                    "latex-import-" ++ String.fromInt (Time.posixToMillis modelWithContent.common.currentTime // 1000)

                -- Create a new document
                newDoc =
                    Document.newDocument
                        newId
                        basename
                        (Maybe.withDefault "" modelWithContent.common.userName)
                        scriptaContent
                        modelWithContent.common.theme
                        modelWithContent.common.currentTime

                -- Update the model with the new document
                updatedCommon =
                    let
                        oldCommon =
                            modelWithContent.common
                    in
                    { oldCommon
                        | currentDocument = Just newDoc
                        , documents = newDoc :: modelWithContent.common.documents
                        , lastLoadedDocumentId = Just newId
                        , sourceText = scriptaContent
                        , initialText = scriptaContent
                        , loadDocumentIntoEditor = True
                    }

                updatedModel =
                    { modelWithContent | common = updatedCommon }

                -- Get the storage command to save the document
                storage =
                    Storage.SQLite.storage StorageMsg
            in
            ( updatedModel
            , Cmd.batch
                [ cmdFromUpdate
                , storage.saveDocument newDoc
                , Process.sleep 100
                    |> Task.perform (always (CommonMsg Common.ResetLoadFlag))
                ]
            )

        MarkdownFileSelected file ->
            ( model
            , Task.perform (\content -> MarkdownFileLoaded { filename = File.name file, content = content }) (File.toString file)
            )

        MarkdownFileLoaded { filename, content } ->
            let
                -- Extract basename from filename (remove .md extension if present)
                basename =
                    if String.endsWith ".md" filename then
                        String.dropRight 3 filename

                    else
                        filename

                -- Convert non-alphanumeric characters to spaces, then map runs of spaces to hyphens
                title =
                    basename
                        |> String.toList
                        |> List.map
                            (\char ->
                                if Char.isAlphaNum char then
                                    char

                                else
                                    ' '
                            )
                        |> String.fromList
                        |> String.words
                        |> String.join "-"

                -- Convert Markdown to Scripta
                scriptaContent =
                    MarkdownToScripta.convert content

                -- First update the content in the editor
                ( modelWithContent, cmdFromUpdate ) =
                    updateCommon (Common.InputText scriptaContent) model

                -- Generate a new document ID
                newId =
                    "markdown-import-" ++ String.fromInt (Time.posixToMillis modelWithContent.common.currentTime // 1000)

                -- Create a new document
                newDoc =
                    Document.newDocument
                        newId
                        title
                        (Maybe.withDefault "" modelWithContent.common.userName)
                        scriptaContent
                        modelWithContent.common.theme
                        modelWithContent.common.currentTime

                -- Update the model with the new document
                updatedCommon =
                    let
                        oldCommon =
                            modelWithContent.common
                    in
                    { oldCommon
                        | currentDocument = Just newDoc
                        , documents = newDoc :: modelWithContent.common.documents
                        , lastLoadedDocumentId = Just newId
                        , sourceText = scriptaContent
                        , initialText = scriptaContent
                        , loadDocumentIntoEditor = True
                    }

                updatedModel =
                    { modelWithContent | common = updatedCommon }

                -- Get the storage command to save the document
                storage =
                    Storage.SQLite.storage StorageMsg
            in
            ( updatedModel
            , Cmd.batch
                [ cmdFromUpdate
                , storage.saveDocument newDoc
                , Process.sleep 100
                    |> Task.perform (always (CommonMsg Common.ResetLoadFlag))
                ]
            )


updateCommon : Common.CommonMsg -> Model -> ( Model, Cmd Msg )
updateCommon msg model =
    let
        storage =
            Storage.SQLite.storage StorageMsg

        common =
            model.common
    in
    case msg of
        Common.NoOp ->
            ( model, Cmd.none )

        Common.InputText str ->
            ( { model | common = Common.applyEdit str common }, Cmd.none )

        Common.InputText2 { source } ->
            let
                newCommon =
                    Common.applyEdit source common
            in
            ( { model | common = { newCommon | loadDocumentIntoEditor = False } }, Cmd.none )

        Common.CompilerEvent event ->
            ( model, Common.compilerEventCmd event )

        Common.GotNewWindowDimensions width height ->
            let
                newCommon =
                    { common
                        | windowWidth = width
                        , windowHeight = height
                        , displaySettings = { windowWidth = Common.contentWidth width }
                    }
                        |> Common.refreshOptions
            in
            ( { model | common = newCommon }, Cmd.none )

        Common.KeyMsg keyMsg ->
            let
                newCommon =
                    { common | pressedKeys = Keyboard.update keyMsg common.pressedKeys }
            in
            ( { model | common = newCommon }, Cmd.none )

        Common.ToggleTheme ->
            let
                newTheme : Theme.Theme
                newTheme =
                    if common.theme == Theme.Dark then
                        Theme.Light

                    else
                        Theme.Dark

                updatedCommon =
                    Common.refreshOptions { common | theme = newTheme }
            in
            ( { model | common = updatedCommon }
            , Cmd.none
              -- Theme is saved with each document
            )

        Common.CreateNewDocument ->
            case common.currentDocument of
                Just doc ->
                    if common.sourceText /= doc.content then
                        -- Save current document first
                        let
                            ( newModel, saveCmd ) =
                                update (CommonMsg Common.SaveDocument) model
                        in
                        ( newModel
                        , Cmd.batch
                            [ saveCmd
                            , Random.generate (CommonMsg << Common.GeneratedId) generateId
                            ]
                        )

                    else
                        ( model
                        , Random.generate (CommonMsg << Common.GeneratedId) generateId
                        )

                Nothing ->
                    ( model
                    , Random.generate (CommonMsg << Common.GeneratedId) generateId
                    )

        Common.GeneratedId id ->
            let
                newDocumentContent =
                    "| title\nNew Document\n"

                newDoc =
                    Document.newDocument id "New Document" (Maybe.withDefault "" common.userName) newDocumentContent common.theme common.currentTime

                loadedCommon =
                    Common.loadSource newDocumentContent common

                newCommon =
                    { loadedCommon
                        | currentDocument = Just newDoc
                        , documents = newDoc :: common.documents
                        , initialText = newDocumentContent
                        , title = "New Document"
                        , lastLoadedDocumentId = Just id
                        , loadDocumentIntoEditor = True
                        , printingState = Common.PrintWaiting
                        , pdfLink = ""
                    }
            in
            ( { model | common = { newCommon | lastSavedDocumentId = Just newDoc.id } }
            , Cmd.batch
                [ storage.saveDocument newDoc
                , storage.saveLastDocumentId newDoc.id
                ]
            )

        Common.SaveDocument ->
            case common.currentDocument of
                Just doc ->
                    let
                        updatedDoc =
                            { doc
                                | content = common.sourceText
                                , title = common.title
                                , modifiedAt = common.currentTime
                                , theme = common.theme
                            }

                        updatedDocs =
                            updatedDoc :: List.filter (\d -> d.id /= doc.id) common.documents

                        newCommon =
                            { common
                                | currentDocument = Just updatedDoc
                                , documents = updatedDocs
                                , lastSaved = common.currentTime
                                , lastSavedDocumentId = Just doc.id
                            }
                    in
                    ( { model | common = newCommon }
                    , Cmd.batch
                        [ storage.saveDocument updatedDoc
                        , storage.saveLastDocumentId doc.id
                        ]
                    )

                Nothing ->
                    update (CommonMsg Common.CreateNewDocument) model

        Common.LoadDocument id ->
            ( { model | common = { common | printingState = Common.PrintWaiting, pdfLink = "" } }
            , storage.loadDocument id
            )

        Common.DeleteDocument id ->
            let
                newCommon =
                    if common.currentDocument |> Maybe.map .id |> (==) (Just id) then
                        { common | currentDocument = Nothing, sourceText = "" }

                    else
                        common
            in
            ( { model | common = newCommon }
            , storage.deleteDocument id
            )

        Common.ToggleDocumentList ->
            ( { model | common = { common | showDocumentList = not common.showDocumentList } }
            , Cmd.none
            )

        Common.ToggleSortOrder ->
            let
                newSortOrder =
                    case common.sortOrder of
                        Common.Alphabetical ->
                            Common.Recent

                        Common.Recent ->
                            Common.Alphabetical
            in
            ( { model | common = { common | sortOrder = newSortOrder } }
            , Cmd.none
            )

        Common.InputDocumentSearchText text ->
            ( { model | common = { common | documentSearchText = text } }
            , Cmd.none
            )

        Common.ToggleMenu menu ->
            ( { model
                | common =
                    { common
                        | openMenu =
                            if common.openMenu == Just menu then
                                Nothing

                            else
                                Just menu
                    }
              }
            , Cmd.none
            )

        Common.CloseMenu ->
            ( { model | common = { common | openMenu = Nothing } }, Cmd.none )

        Common.MenuItemSelected itemMsg ->
            updateCommon itemMsg { model | common = { common | openMenu = Nothing } }

        Common.Tick time ->
            let
                newModel =
                    { model | common = { common | currentTime = time } }
            in
            if Common.shouldAutoSave time newModel.common then
                update (CommonMsg Common.SaveDocument) newModel

            else
                ( newModel, Cmd.none )

        Common.LoadUserNameDelayed ->
            ( model
            , storage.loadUserName
            )

        Common.InputUserName name ->
            ( { model | common = { common | userName = Just name } }
            , storage.saveUserName name
            )

        Common.UpdateFileName name ->
            ( { model | common = { common | title = name } }
            , Cmd.none
            )

        Common.ExportToLaTeX ->
            ( model
            , File.Download.string (common.title ++ ".tex")
                "application/x-latex"
                (ScriptaExport.latex { title = common.title, date = common.currentTime } common.sourceText)
            )

        Common.ExportToRawLaTeX ->
            ( model
            , File.Download.string (common.title ++ ".tex")
                "application/x-latex"
                (ScriptaExport.rawLatex common.sourceText)
            )

        Common.ExportScriptaFile ->
            let
                fileName =
                    if String.trim common.title == "" then
                        "document.scripta"

                    else
                        common.title ++ ".scripta"
            in
            ( model
            , File.Download.string fileName "text/plain" common.sourceText
            )

        Common.ImportScriptaFile ->
            ( model
            , File.Select.file [ "text/plain", ".scripta", ".txt" ] FileSelected
            )

        Common.ImportLaTeXFile ->
            ( model
            , File.Select.file [ "text/x-tex", "text/x-latex", ".tex", "application/x-tex" ] LaTeXFileSelected
            )

        Common.ImportMarkdownFile ->
            ( model
            , File.Select.file [ "text/markdown", ".md", ".markdown" ] MarkdownFileSelected
            )

        Common.PrintToPDF ->
            let
                exportData =
                    { title = common.title
                    , content = ScriptaExport.latex { title = common.title, date = common.currentTime } common.sourceText
                    , sourceText = common.sourceText
                    }
            in
            ( { model | common = { common | printingState = Common.PrintProcessing } }
            , Cmd.map CommonMsg (Frontend.PDF.requestPDF exportData)
            )

        Common.GotPdfLink result ->
            -- This is kept for backwards compatibility but should not be used
            case result of
                Ok pdfLink ->
                    ( { model | common = { common | printingState = Common.PrintReady, pdfLink = pdfLink } }
                    , Cmd.none
                    )

                Err httpError ->
                    ( { model | common = { common | printingState = Common.PrintWaiting } }
                    , Cmd.none
                    )

        Common.GotPdfResponse result ->
            case result of
                Ok pdfResponse ->
                    let
                        _ =
                            Debug.log "@@ GotPdfResponse - hasErrors" pdfResponse.hasErrors

                        _ =
                            Debug.log "@@ GotPdfResponse - pdfFailed" pdfResponse.pdfFailed

                        _ =
                            Debug.log "@@ GotPdfResponse - errorReport" pdfResponse.errorReport

                        _ =
                            Debug.log "@@ GotPdfResponse - errorJson" pdfResponse.errorJson

                        rawErrors =
                            pdfResponse.errorJson |> Maybe.withDefault []

                        _ =
                            Debug.log "@@ GotPdfResponse - raw errors count" (List.length rawErrors)

                        _ =
                            Debug.log "@@ GotPdfResponse - raw errors" rawErrors

                        pdfErrors =
                            deduplicatePdfErrors rawErrors

                        _ =
                            Debug.log "@@ GotPdfResponse - deduplicated errors count" (List.length pdfErrors)

                        _ =
                            Debug.log "@@ GotPdfResponse - deduplicated errors" pdfErrors
                    in
                    ( { model | common = { common | printingState = Common.PrintReady, pdfResponse = Just pdfResponse, pdfErrors = pdfErrors } }
                    , Cmd.none
                    )

                Err httpError ->
                    let
                        -- Extract error message and filter out geometry warnings if it's a BadBody error
                        errorMsg =
                            case httpError of
                                Http.BadBody body ->
                                    body
                                        |> String.lines
                                        |> List.filter (\line -> not (String.contains "*geometry* driver" line))
                                        |> String.join "\n"

                                _ ->
                                    "HTTP Error"
                    in
                    ( { model | common = { common | printingState = Common.PrintWaiting } }
                    , Cmd.none
                    )

        Common.LoadContentIntoEditorDelayed ->
            ( { model | common = { common | loadDocumentIntoEditor = True } }
            , Process.sleep 300
                |> Task.perform (always (CommonMsg Common.ResetLoadFlag))
            )

        Common.ResetLoadFlag ->
            ( { model | common = { common | loadDocumentIntoEditor = False } }
            , Cmd.none
            )

        Common.InitialDocumentId content title currentTime theme id ->
            let
                initialDoc =
                    Document.newDocument id title (Maybe.withDefault "" common.userName) content theme currentTime

                loadedCommon =
                    Common.loadSource content common

                newCommon =
                    { loadedCommon
                        | currentDocument = Just initialDoc
                        , documents = initialDoc :: common.documents
                        , initialText = content
                        , title = title
                        , loadDocumentIntoEditor = False -- Will be set by LoadContentIntoEditorDelayed
                    }
            in
            ( { model | common = { newCommon | lastSavedDocumentId = Just initialDoc.id } }
            , Cmd.batch
                [ storage.saveDocument initialDoc
                , storage.saveLastDocumentId initialDoc.id
                , Process.sleep 500
                    |> Task.perform (always (CommonMsg Common.LoadContentIntoEditorDelayed))
                ]
            )

        Common.FocusOnEditorLine lineNumber ->
            ( model, Common.focusEditorOnLine lineNumber common )

        Common.TogglePdfErrors ->
            ( { model | common = { common | showPdfErrors = not common.showPdfErrors } }
            , Cmd.none
            )

        _ ->
            -- Handle other messages with no-op for now
            ( model, Cmd.none )


handleStorageMsg : Storage.StorageMsg -> Model -> ( Model, Cmd Msg )
handleStorageMsg msg model =
    let
        common =
            model.common
    in
    case msg of
        Storage.DocumentsListed (Ok docs) ->
            if List.isEmpty docs then
                -- No documents in storage, create default document
                ( { model | common = { common | documents = docs } }
                , Random.generate
                    (CommonMsg << Common.InitialDocumentId (String.trim AppData.defaultDocumentText) "Announcement" common.currentTime common.theme)
                    generateId
                )

            else
                ( { model | common = { common | documents = docs } }
                , Cmd.none
                )

        Storage.DocumentsListed (Err error) ->
            ( model, Cmd.none )

        Storage.DocumentLoaded (Ok doc) ->
            let
                loadedCommon =
                    Common.loadSource doc.content common

                newCommon =
                    { loadedCommon
                        | currentDocument = Just doc
                        , initialText = doc.content
                        , title = doc.title
                        , loadDocumentIntoEditor = True
                        , lastLoadedDocumentId = Just doc.id
                        , printingState = Common.PrintWaiting
                        , pdfLink = ""
                    }
            in
            ( { model | common = newCommon }
            , Cmd.none
            )

        Storage.DocumentLoaded (Err error) ->
            -- Document failed to load, try to load the first document from the list
            let
                firstDoc =
                    List.head common.documents
            in
            case firstDoc of
                Just doc ->
                    -- Load the first available document
                    let
                        storage =
                            Storage.SQLite.storage StorageMsg
                    in
                    ( model
                    , storage.loadDocument doc.id
                    )

                Nothing ->
                    -- No documents available, create a new one
                    ( model
                    , Random.generate (CommonMsg << Common.GeneratedId) generateId
                    )

        Storage.DocumentSaved (Ok doc) ->
            let
                updatedDocs =
                    doc :: List.filter (\d -> d.id /= doc.id) common.documents
            in
            ( { model | common = { common | documents = updatedDocs } }
            , Cmd.none
            )

        Storage.DocumentSaved (Err error) ->
            ( model, Cmd.none )

        Storage.DocumentDeleted (Ok id) ->
            let
                updatedDocs =
                    List.filter (\d -> d.id /= id) common.documents
            in
            ( { model | common = { common | documents = updatedDocs } }
            , Cmd.none
            )

        Storage.DocumentDeleted (Err error) ->
            ( model, Cmd.none )

        Storage.UserNameLoaded (Ok maybeName) ->
            ( { model | common = { common | userName = maybeName } }
            , Cmd.none
            )

        Storage.UserNameLoaded (Err error) ->
            ( model, Cmd.none )

        Storage.UserNameSaved _ ->
            ( model, Cmd.none )

        Storage.LastDocumentIdLoaded (Ok maybeId) ->
            let
                newCommon =
                    { common | lastSavedDocumentId = maybeId }
            in
            case maybeId of
                Just id ->
                    ( { model | common = newCommon }
                    , Process.sleep 1000
                        |> Task.perform (always (CommonMsg (Common.LoadDocument id)))
                    )

                Nothing ->
                    ( { model | common = newCommon }
                    , Cmd.none
                    )

        Storage.LastDocumentIdLoaded (Err _) ->
            ( model, Cmd.none )

        Storage.LastDocumentIdSaved _ ->
            ( model, Cmd.none )

        Storage.StorageInitialized (Ok _) ->
            ( { model | storageState = { initialized = True, dbReady = True } }
            , Cmd.batch
                [ Storage.SQLite.storage StorageMsg |> .listDocuments
                , Storage.SQLite.storage StorageMsg |> .loadLastDocumentId
                ]
            )

        Storage.StorageInitialized (Err error) ->
            ( model, Cmd.none )

        Storage.FileOpened content ->
            -- Handle file opened from native dialog
            let
                newCommon =
                    { common | sourceText = content }
            in
            ( { model | common = newCommon }
            , Cmd.none
            )

        Storage.FileSaved _ ->
            -- File saved via native dialog
            ( model, Cmd.none )

        Storage.PdfGenerated _ ->
            -- PDF generation result
            ( model, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    Common.View.view CommonMsg (CommonMsg << Common.CompilerEvent) model.common



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize (\w h -> CommonMsg (Common.GotNewWindowDimensions w h))
        , Keyboard.subscriptions |> Sub.map (CommonMsg << Common.KeyMsg)
        , Time.every constants.autoSaveCheckInterval (CommonMsg << Common.Tick)
        , Sub.map CommonMsg (Common.menuSubscriptions model.common)
        , Storage.SQLite.subscriptions StorageMsg
        ]



-- HELPERS


-- ID GENERATION


generateId : Random.Generator String
generateId =
    Random.int 100000 999999
        |> Random.map (\n -> "doc-" ++ String.fromInt n)



-- PDF ERROR DEDUPLICATION


{-| Deduplicate PDF errors by scriptaLine, combining latexText fields
-}
deduplicatePdfErrors : List Common.PdfError -> List Common.PdfError
deduplicatePdfErrors errors =
    errors
        |> List.Extra.gatherEqualsBy .scriptaLine
        |> List.map combineErrorGroup


{-| Combine a group of errors with the same scriptaLine into one error
-}
combineErrorGroup : ( Common.PdfError, List Common.PdfError ) -> Common.PdfError
combineErrorGroup ( firstError, restErrors ) =
    let
        allErrors =
            firstError :: restErrors

        combinedLatexText =
            allErrors
                |> List.indexedMap (\index error -> "(" ++ String.fromInt (index + 1) ++ ") " ++ error.latexText)
                |> String.join "; "
    in
    { firstError | latexText = combinedLatexText }

