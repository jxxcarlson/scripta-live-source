port module ViewScripta exposing (main)

{-| Command-line viewer for Scripta files
Reads a .scripta file and renders it to HTML
-}

import Browser
import Dict
import Element exposing (Element)
import Element.Background as Background
import Element.Font as Font
import Html exposing (Html)
import Render.Theme
import ScriptaV2.API
import ScriptaV2.Language
import ScriptaV2.Msg
import ScriptaV2.Types


-- PORTS


port getFileContent : (String -> msg) -> Sub msg


port logError : String -> Cmd msg



-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { content : Maybe String
    , error : Maybe String
    }


type alias Flags =
    {}


init : Flags -> ( Model, Cmd Msg )
init _ =
    ( { content = Nothing
      , error = Nothing
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = GotFileContent String
    | MarkupMsg ScriptaV2.Msg.MarkupMsg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotFileContent content ->
            ( { model | content = Just content }
            , Cmd.none
            )

        MarkupMsg _ ->
            -- Ignore markup messages (clicks, etc.)
            ( model, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    Element.layout
        [ Element.width Element.fill
        , Element.height Element.fill
        , Background.color (Element.rgb 1 1 1)
        , Font.size 16
        , Element.padding 40
        ]
        (case model.content of
            Nothing ->
                Element.text "Loading..."

            Just content ->
                viewContent content
        )


viewContent : String -> Element Msg
viewContent content =
    let
        params =
            { filter = ScriptaV2.Types.NoFilter
            , lang = detectLanguage content
            , docWidth = 800
            , editCount = 0
            , selectedId = ""
            , selectedSlug = Nothing
            , idsOfOpenNodes = []
            , theme = Render.Theme.Light
            , windowWidth = 900
            , longEquationLimit = 800
            , scale = 1
            , numberToLevel = 1
            , data = Dict.empty
            }

        elements =
            ScriptaV2.API.compileString params content
                |> List.map (Element.map MarkupMsg)
    in
    Element.column
        [ Element.width (Element.px 800)
        , Element.centerX
        , Element.spacing 20
        ]
        elements


detectLanguage : String -> ScriptaV2.Language.Language
detectLanguage content =
    -- Simple heuristic to detect language
    if String.contains "\\begin{" content || String.contains "\\section" content then
        ScriptaV2.Language.MicroLaTeXLang

    else if String.contains "|>" content || String.contains "| section" content then
        ScriptaV2.Language.EnclosureLang

    else
         ScriptaV2.Language.EnclosureLang



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    getFileContent GotFileContent