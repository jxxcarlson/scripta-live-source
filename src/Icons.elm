module Icons exposing (moon, sun)

{-| Small stroke icons drawn in the current text colour.
-}

import Element exposing (Element)
import Svg exposing (Svg)
import Svg.Attributes as SA


sun : Element msg
sun =
    icon
        [ Svg.circle [ SA.cx "12", SA.cy "12", SA.r "4" ] []
        , Svg.path [ SA.d "M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" ] []
        ]


moon : Element msg
moon =
    icon
        [ Svg.path [ SA.d "M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" ] [] ]


icon : List (Svg msg) -> Element msg
icon children =
    Element.html
        (Svg.svg
            [ SA.width "14"
            , SA.height "14"
            , SA.viewBox "0 0 24 24"
            , SA.fill "none"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2"
            , SA.strokeLinecap "round"
            , SA.strokeLinejoin "round"
            , SA.style "display: block"
            ]
            children
        )
