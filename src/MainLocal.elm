module MainLocal exposing (main)

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
import Element exposing (..)
import File
import File.Download
import File.Select
import Frontend.PDF
import Html exposing (Html)
import Json.Decode as Decode
import Keyboard
import List.Extra
import Ports
import Process
import Random
import ScriptaExport
import Storage.Interface as Storage
import Storage.Local
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
    , storageState : Storage.Local.State
    }


type Msg
    = CommonMsg Common.CommonMsg
    | StorageMsg Storage.StorageMsg
    | FileSelected File.File
    | FileLoaded String


-- INIT


init : Common.Flags -> ( Model, Cmd Msg )
init flags =
    let
        common =
            Common.initCommon flags

        storage =
            Storage.Local.storage StorageMsg

        updatedCommon =
            { common 
                | showDocumentList = True
            }
    in
    ( { common = updatedCommon
      , storageState = Storage.Local.init
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
                ( modelWithContent, cmdFromUpdate ) = updateCommon (Common.InputText content) model

                -- Extract the title from the content
                title = Common.getTitleFromContent content

                -- Generate a new document ID
                newId = "imported-" ++ String.fromInt (Time.posixToMillis modelWithContent.common.currentTime // 1)

                -- Create a new document
                newDoc = Document.newDocument
                    newId
                    title
                    (Maybe.withDefault "" modelWithContent.common.userName)
                    content
                    modelWithContent.common.theme
                    modelWithContent.common.currentTime

                -- Update the model with the new document
                updatedCommon =
                    let
                        oldCommon = modelWithContent.common
                    in
                    { oldCommon
                        | currentDocument = Just newDoc
                        , documents = newDoc :: modelWithContent.common.documents
                        , lastLoadedDocumentId = Just newId
                        , sourceText = content
                        , initialText = content
                        , loadDocumentIntoEditor = True
                    }

                updatedModel = { modelWithContent | common = updatedCommon }

                -- Get the storage command to save the document
                storage = Storage.Local.storage StorageMsg
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
            Storage.Local.storage StorageMsg

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
                newTheme =
                    if common.theme == Theme.Dark then
                        Theme.Light
                    else
                        Theme.Dark

                newCommon =
                    Common.refreshOptions { common | theme = newTheme }
            in
            ( { model | common = newCommon }
            , Ports.send (Ports.SaveTheme 
                (case newTheme of
                    Theme.Light ->
                        "light"
                    
                    Theme.Dark ->
                        "dark"
                )
            )
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
                [ Ports.send (Ports.SaveDocument newDoc)
                , Ports.send (Ports.SaveLastDocumentId newDoc.id)
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

                        newCommon =
                            { common
                                | currentDocument = Just updatedDoc
                                , lastSaved = common.currentTime
                                , lastSavedDocumentId = Just doc.id
                            }
                    in
                    ( { model | common = newCommon }
                    , Cmd.batch
                        [ Ports.send (Ports.SaveDocument updatedDoc)
                        , Ports.send (Ports.SaveLastDocumentId doc.id)
                        ]
                    )

                Nothing ->
                    update (CommonMsg Common.CreateNewDocument) model

        Common.LoadDocument id ->
            ( { model | common = { common | printingState = Common.PrintWaiting, pdfLink = "" } }
            , Ports.send (Ports.LoadDocument id)
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
            , Ports.send (Ports.DeleteDocument id)
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
            , Ports.send Ports.LoadUserName
            )

        Common.InputUserName name ->
            ( { model | common = { common | userName = Just name } }
            , Ports.send (Ports.SaveUserName name)
            )

        Common.PortMsgReceived result ->
            case result of
                Ok incomingMsg ->
                    handleIncomingPortMsg incomingMsg model

                Err _ ->
                    ( model, Cmd.none )

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
            , File.Select.file ["text/plain", ".scripta", ".txt"] FileSelected
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
            case result of
                Ok pdfLink ->
                    ( { model | common = { common | printingState = Common.PrintReady, pdfLink = pdfLink } }
                    , Cmd.none
                    )

                Err _ ->
                    ( { model | common = { common | printingState = Common.PrintWaiting } }
                    , Cmd.none
                    )

        Common.LoadContentIntoEditorDelayed ->
            ( { model | common = { common | loadDocumentIntoEditor = True } }
            , Process.sleep 100
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
                        , initialText = content
                        , title = title
                        , loadDocumentIntoEditor = True
                    }
            in
            ( { model | common = { newCommon | lastSavedDocumentId = Just initialDoc.id } }
            , Cmd.batch
                [ Ports.send (Ports.SaveDocument initialDoc)
                , Ports.send (Ports.SaveLastDocumentId initialDoc.id)
                ]
            )

        _ ->
            -- Handle other messages with no-op for now
            ( model, Cmd.none )


handleIncomingPortMsg : Ports.IncomingMsg -> Model -> ( Model, Cmd Msg )
handleIncomingPortMsg msg model =
    let
        common =
            model.common
    in
    case msg of
        Ports.DocumentsLoaded docs ->
            if List.isEmpty docs then
                -- No documents in storage, create default document
                ( { model | common = { common | documents = docs } }
                , Random.generate
                    (CommonMsg << Common.InitialDocumentId AppData.defaultDocumentText "Announcement" common.currentTime common.theme)
                    generateId
                )
            else
                ( { model | common = { common | documents = docs } }
                , Cmd.none
                )

        Ports.DocumentLoaded doc ->
            let
                loadedCommon =
                    Common.loadSource doc.content common

                newCommon =
                    { loadedCommon
                        | currentDocument = Just doc
                        , initialText = doc.content
                        , title = doc.title
                        , loadDocumentIntoEditor = True  -- Set to True immediately for initial load
                        , lastLoadedDocumentId = Just doc.id
                        , printingState = Common.PrintWaiting
                        , pdfLink = ""
                    }
            in
            ( { model | common = newCommon }
            , Process.sleep 500
                |> Task.perform (always (CommonMsg Common.ResetLoadFlag))
            )

        Ports.ThemeLoaded themeStr ->
            let
                theme =
                    case themeStr of
                        "dark" ->
                            Theme.Dark
                        
                        _ ->
                            Theme.Light
                newCommon =
                    Common.refreshOptions { common | theme = theme }
            in
            ( { model | common = newCommon }
            , Cmd.none
            )

        Ports.UserNameLoaded name ->
            ( { model | common = { common | userName = Just name } }
            , Cmd.none
            )
        
        Ports.LastDocumentIdLoaded id ->
            let
                newCommon = { common | lastSavedDocumentId = Just id }
            in
            if id /= "" then
                ( { model | common = newCommon }
                -- Delay loading the document to ensure editor is ready
                , Process.sleep 1000
                    |> Task.perform (always (CommonMsg (Common.LoadDocument id)))
                )
            else
                ( { model | common = newCommon }
                , Cmd.none
                )

        Ports.MarkdownFileImported _ ->
            ( model, Cmd.none )


handleStorageMsg : Storage.StorageMsg -> Model -> ( Model, Cmd Msg )
handleStorageMsg msg model =
    -- Since we're using Ports directly, we don't need to handle these
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
        , Ports.receive (CommonMsg << Common.PortMsgReceived)
        ]


-- HELPERS


-- ID GENERATION


generateId : Random.Generator String
generateId =
    Random.int 100000 999999
        |> Random.map (\n -> "doc-" ++ String.fromInt n)