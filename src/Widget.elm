module Widget exposing
    ( inputTextWidget
    , sidebarButton
    , sidebarButton2
    , sidebarIconButton
    )

import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html.Attributes
import Style
import Theme


sidebarButton2 buttonTheme modelTheme msg label =
    Input.button
        [ paddingXY 8 4
        , Background.color
            (if modelTheme == Theme.Light then
                Element.rgb255 255 255 255

             else
                Element.rgb255 48 54 59
            )
        , Font.color
            (if modelTheme == Theme.Light then
                Element.rgb255 50 50 50

             else
                Element.rgb255 150 150 150
            )
        , Element.htmlAttribute
            (Html.Attributes.style "color"
                (case modelTheme of
                    Theme.Light ->
                        "rgb(0, 40, 40)"

                    Theme.Dark ->
                        "rgb(100, 150, 255)"  -- Light blue instead of orange
                )
            )
        , Border.roundEach { topLeft = 0, bottomLeft = 0, topRight = 4, bottomRight = 4 }
        , Border.width
            (if modelTheme == Theme.Light then
                1

             else
                1
            )
        , Border.color
            (if modelTheme == Theme.Light then
                Element.rgba 0.2 0.2 0.2 1.0

             else
                Element.rgba 0.39 0.59 1.0 0.5  -- Light blue border
            )
        , Font.size 12
        , if buttonTheme == modelTheme then
            Font.bold

          else
            Font.extraLight
        , mouseOver
            [ Background.color
                (if modelTheme == Theme.Light then
                    Element.rgb255 240 240 240
                 else
                    Element.rgb255 65 72 78
                )
            , Border.color
                (if modelTheme == Theme.Light then
                    Element.rgba 0.3 0.3 0.3 1.0
                 else
                    Element.rgba 0.39 0.59 1.0 0.7  -- Light blue border on hover
                )
            ]
        , mouseDown
            [ Background.color
                (if modelTheme == Theme.Light then
                    Element.rgb255 220 220 220
                 else
                    Element.rgb255 75 82 88
                )
            , Border.color
                (if modelTheme == Theme.Light then
                    Element.rgba 0.4 0.4 0.4 1.0
                 else
                    Element.rgba 0.39 0.59 1.0 0.9  -- Light blue border on click
                )
            ]
        ]
        { onPress = msg
        , label = Element.text label
        }


sidebarButton theme msg label =
    Input.button (sidebarButtonStyle theme)
        { onPress = msg
        , label = Element.text label
        }


{-| A sidebar button showing an icon; `title` is the hover tooltip.
-}
sidebarIconButton : Theme.Theme -> Maybe msg -> String -> Element msg -> Element msg
sidebarIconButton theme msg title icon =
    Input.button (Element.htmlAttribute (Html.Attributes.title title) :: sidebarButtonStyle theme)
        { onPress = msg
        , label = icon
        }


sidebarButtonStyle : Theme.Theme -> List (Attribute msg)
sidebarButtonStyle theme =
    [ paddingXY 8 4
    , Background.color
        (if theme == Theme.Light then
            Element.rgb255 255 255 255

         else
            Element.rgb255 48 54 59
        )
    , Font.color
        (if theme == Theme.Light then
            Element.rgb255 50 50 50

         else
            Element.rgb255 150 150 150
        )
    , Element.htmlAttribute
        (Html.Attributes.style "color"
            (case theme of
                Theme.Light ->
                    "rgb(0, 40, 40)"

                Theme.Dark ->
                    "rgb(100, 150, 255)"  -- Light blue instead of orange
            )
        )
    , Border.roundEach { topLeft = 0, bottomLeft = 0, topRight = 4, bottomRight = 4 }
    , Border.width
        (if theme == Theme.Light then
            1

         else
            1
        )
    , Border.color
        (if theme == Theme.Light then
            Element.rgba 0.2 0.2 0.2 1.0

         else
            Element.rgba 0.39 0.59 1.0 0.5  -- Light blue border
        )
    , Font.size 12
    , mouseOver
        [ Background.color
            (if theme == Theme.Light then
                Element.rgb255 240 240 240
             else
                Element.rgb255 65 72 78
            )
        , Border.color
            (if theme == Theme.Light then
                Element.rgba 0.3 0.3 0.3 1.0
             else
                Element.rgba 0.39 0.59 1.0 0.7  -- Light blue border on hover
            )
        ]
    , mouseDown
        [ Background.color
            (if theme == Theme.Light then
                Element.rgb255 220 220 220
             else
                Element.rgb255 75 82 88
            )
        , Border.color
            (if theme == Theme.Light then
                Element.rgba 0.4 0.4 0.4 1.0
             else
                Element.rgba 0.39 0.59 1.0 0.9  -- Light blue border on click
            )
        ]
    ]


inputTextWidget theme input msg =
    Input.text
        [ width fill
        , paddingXY 8 4
        , Border.width 1
        , Border.rounded 4
        , Border.color (Element.rgba 0.5 0.5 0.5 0.3)
        , Background.color (Style.backgroundColor theme)
        , Font.color (Style.textColor theme)
        , Font.size 14
        , Font.bold
        ]
        { onChange = msg
        , text = input
        , placeholder = Nothing
        , label = Input.labelHidden "Your name"
        }
