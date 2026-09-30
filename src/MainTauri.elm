module MainTauri exposing (main)

import AppData
import Browser
import Browser.Dom
import Browser.Events
import Common.Model as Common
import Common.View
import Config
import Constants exposing (constants)
import Dict
import Document exposing (Document)
import Either
import Element exposing (..)
import File.Download
import Frontend.PDF
import Html exposing (Html)
import Json.Decode as Decode
import Json.Encode
import Keyboard
import List.Extra
import Ports
import Process
import Random
import ScriptaExport
import Storage.Interface as Storage
import Storage.Tauri
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
    }


type Msg
    = CommonMsg Common.CommonMsg
    | StorageMsg Storage.StorageMsg


-- INIT


init : Common.Flags -> ( Model, Cmd Msg )
init flags =
    let
        common =
            Common.initCommon flags

        storage =
            Storage.Tauri.storage StorageMsg

        updatedCommon =
            { common 
                | showDocumentList = True
            }
    in
    ( { common = updatedCommon
      }
    , Cmd.batch
        [ storage.init
        , Task.perform (CommonMsg << Common.Tick) Time.now
        , Process.sleep 100
            |> Task.perform (always (CommonMsg Common.LoadUserNameDelayed))
        , Process.sleep 200
            |> Task.perform (always (StorageMsg (Storage.StorageInitialized (Ok ()))))
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


updateCommon : Common.CommonMsg -> Model -> ( Model, Cmd Msg )
updateCommon msg model =
    let
        storage =
            Storage.Tauri.storage StorageMsg

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
            , Cmd.none  -- Theme is saved with each document
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

                        newCommon =
                            { common
                                | currentDocument = Just updatedDoc
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

        Common.AutoSave time ->
            let
                shouldSave =
                    Time.posixToMillis time - Time.posixToMillis common.lastSaved > 30000
                        && common.sourceText /= ""
                        && common.lastChanged /= common.lastSaved
            in
            if shouldSave then
                update (CommonMsg Common.SaveDocument) model
            else
                ( model, Cmd.none )

        Common.Tick time ->
            ( { model | common = { common | currentTime = time } }
            , Cmd.none
            )

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
            let
                exportText =
                    ScriptaExport.latex { title = common.title, date = common.currentTime } common.sourceText
            in
            ( model
            , Ports.tauriCommand <|
                Json.Encode.object
                    [ ( "cmd", Json.Encode.string "saveFile" )
                    , ( "file_name", Json.Encode.string (common.title ++ ".tex") )
                    , ( "content", Json.Encode.string exportText )
                    , ( "mime_type", Json.Encode.string "application/x-latex" )
                    ]
            )

        Common.ExportToRawLaTeX ->
            let
                exportText =
                    ScriptaExport.rawLatex common.sourceText
            in
            ( model
            , Ports.tauriCommand <|
                Json.Encode.object
                    [ ( "cmd", Json.Encode.string "saveFile" )
                    , ( "file_name", Json.Encode.string (common.title ++ ".tex") )
                    , ( "content", Json.Encode.string exportText )
                    , ( "mime_type", Json.Encode.string "application/x-latex" )
                    ]
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
            , Ports.tauriCommand <|
                Json.Encode.object
                    [ ( "cmd", Json.Encode.string "saveFile" )
                    , ( "file_name", Json.Encode.string fileName )
                    , ( "content", Json.Encode.string common.sourceText )
                    , ( "mime_type", Json.Encode.string "text/plain" )
                    ]
            )

        Common.ImportScriptaFile ->
            ( model
            , Ports.tauriCommand <|
                Json.Encode.object
                    [ ( "cmd", Json.Encode.string "openFile" )
                    , ( "extensions", Json.Encode.list Json.Encode.string [ "scripta", "txt" ] )
                    ]
            )

        Common.PrintToPDF ->
            let
                exportText =
                    ScriptaExport.latex { title = common.title, date = common.currentTime } common.sourceText

                fileName =
                    if String.trim common.title == "" then
                        "document.pdf"
                    else
                        common.title ++ ".pdf"

            in
            ( model
            , Ports.tauriCommand <|
                Json.Encode.object
                    [ ( "cmd", Json.Encode.string "generatePdf" )
                    , ( "file_name", Json.Encode.string fileName )
                    , ( "content", Json.Encode.string exportText )
                    ]
            )

        Common.GotPdfLink result ->
            -- This is kept for backwards compatibility but should not be used
            case result of
                Ok pdfLink ->
                    ( { model | common = { common | printingState = Common.PrintReady, pdfLink = pdfLink } }
                    , Cmd.none
                    )

                Err _ ->
                    ( { model | common = { common | printingState = Common.PrintWaiting } }
                    , Cmd.none
                    )

        Common.GotPdfResponse result ->
            case result of
                Ok pdfResponse ->
                    ( { model | common = { common | printingState = Common.PrintReady, pdfResponse = Just pdfResponse } }
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
                [ storage.saveDocument initialDoc
                , storage.saveLastDocumentId initialDoc.id
                ]
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
                    (CommonMsg << Common.InitialDocumentId AppData.defaultDocumentText "Announcement" common.currentTime common.theme)
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
                -- The document carries its theme: set it before rendering
                loadedCommon =
                    { common
                        | theme = doc.theme
                        , options = Common.makeOptions doc.theme common.displaySettings
                    }
                        |> Common.loadSource doc.content

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
            ( model, Cmd.none )

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
                newCommon = { common | lastSavedDocumentId = maybeId }
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

        Storage.PdfGenerated result ->
            -- PDF generation completed (either success or cancelled)
            case result of
                Ok path ->
                    ( model, Cmd.none )
                Err error ->
                    ( model, Cmd.none )

        Storage.FileSaved result ->
            -- File save completed
            case result of
                Ok path ->
                    ( model, Cmd.none )
                Err error ->
                    ( model, Cmd.none )

        Storage.FileOpened content ->
            let
                -- Extract the title from the content
                title = Common.getTitleFromContent content

                -- Generate a new document ID
                newId = "imported-" ++ String.fromInt (Time.posixToMillis model.common.currentTime // 1)

                -- Create a new document
                newDoc = Document.newDocument
                    newId
                    title
                    (Maybe.withDefault "" model.common.userName)
                    content
                    model.common.theme
                    model.common.currentTime

                updatedCommon =
                    let
                        oldCommon = model.common
                    in
                    { oldCommon
                        | currentDocument = Just newDoc
                        , documents = newDoc :: model.common.documents
                        , lastLoadedDocumentId = Just newId
                        , initialText = content
                        , title = title
                        , loadDocumentIntoEditor = True
                    }
                        |> Common.loadSource content

                -- Get the storage command to save the document
                storage = Storage.Tauri.storage StorageMsg
            in
            ( { model | common = updatedCommon }
            , Cmd.batch
                [ storage.saveDocument newDoc
                , Process.sleep 100
                    |> Task.perform (always (CommonMsg Common.ResetLoadFlag))
                ]
            )

        Storage.StorageInitialized (Ok _) ->
            ( model
            , Cmd.batch
                [ Storage.Tauri.storage StorageMsg |> .listDocuments
                , Storage.Tauri.storage StorageMsg |> .loadLastDocumentId
                ]
            )

        Storage.StorageInitialized (Err error) ->
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
        , Time.every (30 * 1000) (CommonMsg << Common.AutoSave)
        , Time.every constants.autoSaveCheckInterval (CommonMsg << Common.Tick)
        , Storage.Tauri.subscriptions StorageMsg
        ]


-- HELPERS


generateId : Random.Generator String
generateId =
    Random.int 100000 999999
        |> Random.map (\n -> "doc-" ++ String.fromInt n)
