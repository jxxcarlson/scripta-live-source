module Render.Sizing exposing
    ( bodyFontSizePx
    , codeSize
    , headingSizePx
    , indentPx
    , indentWithDeltaPx
    , itemSpacingPx
    , lineHeight
    , marginLeftPx
    , marginLeftWithIndentPx
    , marginRightPx
    , marginRightWithDeltaPx
    , paragraphSpacingPx
    , scaled
    , toEm
    , toPx
    )

{-| Helper functions for sizing and spacing calculations.
All sizes in px (Float), with a scale multiplier for global adjustments.
-}

import V3.Types exposing (SizingConfig)


{-| Apply scale multiplier to a pixel value.
-}
scaled : SizingConfig -> Float -> Float
scaled config px =
    px * config.scale


{-| Convert a pixel value to a CSS px string, applying scale.
Example: toPx config 18.0 -> "18px" (or "21.6px" if scale is 1.2)
-}
toPx : SizingConfig -> Float -> String
toPx config px =
    String.fromFloat (scaled config px) ++ "px"


{-| Convert to CSS em string. Em values are NOT scaled since they're already relative.
Example: toEm config 1.5 -> "1.5em"
-}
toEm : SizingConfig -> Float -> String
toEm _ em =
    String.fromFloat em ++ "em"


{-| Get paragraph spacing as a CSS px string, applying scale.
-}
paragraphSpacingPx : SizingConfig -> String
paragraphSpacingPx config =
    toPx config config.paragraphSpacing


{-| Get item spacing (for list items) as a CSS px string.
Item spacing is 2/3 of paragraph spacing, with a minimum of 4px.
-}
itemSpacingPx : SizingConfig -> String
itemSpacingPx config =
    let
        itemSpacing =
            max 4.0 (config.paragraphSpacing * 2.0 / 3.0)
    in
    toPx config itemSpacing


{-| Get code font size as a CSS px string.
Code size matches base font size, scaled.
-}
codeSize : SizingConfig -> String
codeSize config =
    toPx config config.baseFontSize


{-| Get left margin as a CSS px string, applying scale.
-}
marginLeftPx : SizingConfig -> String
marginLeftPx config =
    toPx config config.marginLeft


{-| Get left margin as a CSS px string, applying increment delta and then scale.
-}
marginLeftWithDeltaPx : Float -> SizingConfig -> String
marginLeftWithDeltaPx delta config =
    toPx config (config.marginLeft + delta)


{-| Get right margin as a CSS px string, applying scale.
-}
marginRightPx : SizingConfig -> String
marginRightPx config =
    toPx config config.marginRight


{-| Get indentation for a given raw indent (spaces) as a CSS px string.
Converts spaces to levels using indentUnit, then applies indentation and scale.
-}
indentPx : Int -> SizingConfig -> String
indentPx rawIndent config =
    let
        level =
            toFloat rawIndent / toFloat config.indentUnit
    in
    toPx config (config.indentation * level)


{-| Get indentation for a given raw indent (spaces) as a CSS px string.
Converts spaces to levels using indentUnit, then applies indentation, delta, and scale.
-}
indentWithDeltaPx : Int -> Int -> SizingConfig -> String
indentWithDeltaPx delta rawIndent config =
    let
        level =
            toFloat rawIndent / toFloat config.indentUnit
    in
    toPx config (config.indentation * (level + toFloat delta))


marginRightWithDeltaPx : Int -> Int -> SizingConfig -> String
marginRightWithDeltaPx delta rawIndent config =
    let
        level =
            toFloat rawIndent / toFloat config.indentUnit
    in
    toPx config (config.marginRight + (-level + toFloat delta) * config.indentation)


{-| Get left margin plus indentation as a CSS px string.
Combines base marginLeft with indentation based on raw indent (spaces).
-}
marginLeftWithIndentPx : Int -> SizingConfig -> String
marginLeftWithIndentPx rawIndent config =
    let
        level =
            toFloat rawIndent / toFloat config.indentUnit
    in
    toPx config (config.marginLeft + config.indentation * level)


{-| Unitless line-height ratio from config (scales with font size).
-}
lineHeight : SizingConfig -> String
lineHeight config =
    String.fromFloat config.lineHeight


{-| Body text font size as a CSS px string (baseFontSize, scaled).
-}
bodyFontSizePx : SizingConfig -> String
bodyFontSizePx config =
    toPx config config.baseFontSize


{-| Section-heading font size for a 1-based level, as baseFontSize times the
ratio at that level in `headingScale` (falling back to 1.0 past the list).
-}
headingSizePx : Int -> SizingConfig -> String
headingSizePx level config =
    let
        ratio =
            config.headingScale
                |> List.drop (level - 1)
                |> List.head
                |> Maybe.withDefault 1.0
    in
    toPx config (config.baseFontSize * ratio)
