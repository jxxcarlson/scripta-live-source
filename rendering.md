# Scripta Rendering API Documentation

## Overview

This document describes how to use the Scripta compiler API to render `.scripta` files programmatically.

## Main Compiler API Module

**Location:** `vendored-compiler/src/ScriptaV2/API.elm`

The Scripta compiler provides two API interfaces:
- **ScriptaV2.API** - Full API with rendering to elm-ui Elements
- **ScriptaV2.APISimple** - Simplified API (recommended for basic use)

## Key Functions

### Simple API (Recommended)

```elm
-- From ScriptaV2.APISimple (lines 52-54)
compile : CompilerParameters -> String -> List (Element MarkupMsg)
```

### Full API Options

```elm
-- From ScriptaV2.API (lines 31-40)
compile : CompilerParameters -> List String -> List (Element ScriptaV2.Msg.MarkupMsg)
compileString : CompilerParameters -> String -> List (Element ScriptaV2.Msg.MarkupMsg)
compileStringWithTitle : String -> CompilerParameters -> String -> List (Element ScriptaV2.Msg.MarkupMsg)
```

## Input Types

### CompilerParameters

**Location:** `vendored-compiler/src/ScriptaV2/Types.elm:35-51`

```elm
type alias CompilerParameters =
    { windowWidth : Int
    , scale : Float
    , lang : Language
    , docWidth : Int
    , editCount : Int
    , selectedId : String
    , selectedSlug : Maybe String
    , idsOfOpenNodes : List String
    , filter : Filter
    , theme : Render.Theme.Theme
    , longEquationLimit : Float
    , numberToLevel : Int
    , data : Dict String String
    }
```

### Language Type

**Location:** `vendored-compiler/src/ScriptaV2/Language.elm:14-18`

```elm
type Language
    = MicroLaTeXLang
    | EnclosureLang
    | SMarkdownLang
    | MarkdownLang
```

### Filter Type

```elm
type Filter
    = NoFilter
    | SuppressDocumentBlocks
```

### Default Parameters

```elm
defaultCompilerParameters : CompilerParameters
defaultCompilerParameters =
    { lang = ScriptaV2.Language.EnclosureLang
    , docWidth = 800
    , editCount = 0
    , selectedId = ""
    , selectedSlug = Nothing
    , idsOfOpenNodes = []
    , filter = NoFilter
    , theme = Render.Theme.Light
    , windowWidth = 800
    , longEquationLimit = 800
    , scale = 1
    , numberToLevel = 1
    , data = Dict.empty
    }
```

## Output Type

### CompilerOutput

**Location:** `vendored-compiler/src/ScriptaV2/Compiler.elm:260-265`

```elm
type alias CompilerOutput =
    { body : List (Element MarkupMsg)
    , banner : Maybe (Element MarkupMsg)
    , toc : List (Element MarkupMsg)
    , title : Element MarkupMsg
    }
```

**Note:** The output is rendered as **elm-ui Elements**, not HTML strings.

## Usage Examples

### Basic Usage

From `src/Main.elm:919-932`:

```elm
compile : Model -> List (Element MarkupMsg)
compile model =
    ScriptaV2.API.compileStringWithTitle
        ""  -- title (optional)
        { filter = ScriptaV2.Compiler.SuppressDocumentBlocks
        , lang = ScriptaV2.Language.EnclosureLang
        , docWidth = 600
        , editCount = 0
        , selectedId = ""
        , idsOfOpenNodes = []
        , theme = Render.Theme.Light
        , windowWidth = 800
        , longEquationLimit = 800
        , scale = 1
        , numberToLevel = 1
        , data = Dict.empty
        }
        model.sourceText  -- Your .scripta content as a String
```

### Minimal Example

```elm
import ScriptaV2.APISimple
import ScriptaV2.Language exposing (Language)
import ScriptaV2.Types exposing (CompilerParameters)
import Element exposing (Element)

renderScripta : String -> List (Element msg)
renderScripta content =
    let
        params : CompilerParameters
        params =
            { lang = ScriptaV2.Language.EnclosureLang
            , docWidth = 800
            , editCount = 0
            , selectedId = ""
            , selectedSlug = Nothing
            , idsOfOpenNodes = []
            , filter = ScriptaV2.Types.NoFilter
            , theme = Render.Theme.Light
            , windowWidth = 800
            , longEquationLimit = 800
            , scale = 1
            , numberToLevel = 1
            , data = Dict.empty
            }
    in
    ScriptaV2.APISimple.compile params content
```

## Key Parameters Explained

- **lang**: Which markup language to parse (MicroLaTeX, Enclosure, SMarkdown, or Markdown)
- **docWidth**: Document width in pixels (affects layout)
- **editCount**: Increment on each edit for live editing contexts (ensures proper virtual DOM updates)
- **filter**: Use `SuppressDocumentBlocks` to hide document-level metadata blocks
- **theme**: `Render.Theme.Light` or `Render.Theme.Dark`
- **selectedId**: For interactive highlighting of specific elements
- **idsOfOpenNodes**: For collapsible sections state management
- **windowWidth**: Browser window width for responsive calculations
- **longEquationLimit**: Width threshold for breaking long equations
- **scale**: Scaling factor for rendered content
- **numberToLevel**: Numbering depth for sections
- **data**: Key-value dictionary for template substitution

## Related Modules

- **ScriptaV2.DifferentialCompiler** - Incremental compilation for live editing
- **ScriptaV2.Settings** - Display settings configuration
- **ScriptaV2.Msg** - Message types for user interactions
- **Render.Theme** - Theme definitions

## Command-Line Rendering

For command-line rendering, you'll need to:
1. Create an Elm program that reads a file
2. Use the compiler API to process the content
3. Convert elm-ui Elements to HTML
4. Output the HTML or display it in a browser

Note that elm-ui Elements need to be rendered to HTML using `Element.layout` and then converted to a string for command-line output.