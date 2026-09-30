module MainWidget exposing
    ( nameElement
    , toggleTheme
    )

{-| Widgets that send `Model.Msg`, used only by the Main.elm entry point.
-}

import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html.Attributes
import Model exposing (Msg(..))
import Style
import Theme
import Widget exposing (inputTextWidget, sidebarButton, sidebarButton2)


toggleTheme model =
    Element.row
        [ Border.width 1
        , Border.color (Element.rgb 0.7 0.7 0.7)
        , Border.rounded 4
        , height (px 30)

        --, paddingXY 12 6
        ]
        [ if model.theme == Theme.Dark then
            sidebarButton2 model.theme Theme.Dark (Just ToggleTheme) "Dark"

          else
            sidebarButton model.theme (Just ToggleTheme) "Dark"
        , if model.theme == Theme.Light then
            sidebarButton2 model.theme Theme.Light (Just ToggleTheme) "Light"

          else
            sidebarButton model.theme (Just ToggleTheme) "Light"
        ]


nameElement model =
    case model.userName of
        Just name ->
            if String.trim name /= "" then
                -- Show just the username when it's filled
                inputTextWidget model.theme name InputUserName

            else
                -- Show label and input when empty
                Element.column [ spacing 8 ]
                    [ Element.el []
                        (Element.text "Your Name")
                    , inputTextWidget model.theme name InputUserName
                    ]

        Nothing ->
            -- Show label and input when Nothing
            Element.column [ spacing 8 ]
                [ Element.el [ Font.bold, paddingEach { top = 0, bottom = 8, left = 0, right = 0 } ]
                    (Element.text "Your Name")
                , inputTextWidget model.theme "" InputUserName
                ]



-- Tools section at the bottom


tools model =
    Element.column
        [ width fill
        , alignBottom
        , Element.paddingXY 16 16
        , Element.spacing 12
        , Border.widthEach { left = 0, right = 0, top = 1, bottom = 0 }
        , Border.color (Element.rgb 0.5 0.5 0.5)
        ]
        [ nameElement model
        , Element.el [ Font.bold, paddingEach { top = 0, bottom = 8, left = 0, right = 0 } ]
            (Element.text "Tools:")
        , foo model
        ]


foo model =
    Input.button
        [ Background.color (Style.buttonBackgroundColor model.theme)
        , Font.color (Style.electricBlueColor model.theme)
        , paddingXY 12 8
        , Border.rounded 4
        , Border.width 1
        , Border.color (Element.rgba 0.5 0.5 0.5 0.3)
        , mouseOver
            [ Background.color (Element.rgba 0.5 0.5 0.5 0.2)
            , Border.color (Element.rgba 0.5 0.5 0.5 0.5)
            ]
        , mouseDown
            [ Background.color (Element.rgba 0.5 0.5 0.5 0.3)
            , Border.color (Element.rgba 0.5 0.5 0.5 0.7)
            ]
        , Element.htmlAttribute
            (Html.Attributes.style "color"
                (case model.theme of
                    Theme.Light ->
                        "rgb(0, 123, 255)"

                    Theme.Dark ->
                        "rgb(0, 191, 255)"
                )
            )
        , width fill
        ]
        { onPress = Just DownloadScript
        , label = text "Download script"
        }
