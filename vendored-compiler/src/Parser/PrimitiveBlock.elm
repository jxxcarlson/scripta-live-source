module Parser.PrimitiveBlock exposing (parse)

{-| Parse a list of strings into a list of primitive blocks.
-}

import Dict exposing (Dict)
import Parser.Line as Line exposing (Line)
import Parser.ListItem as ListItem
import Tools.KV
import Tools.Loop exposing (Step(..), loop)
import V3.Types exposing (BlockMeta, Heading(..), PrimitiveBlock)


verbatimNames : List String
verbatimNames =
    [ "math"
    , "chem"
    , "compute"
    , "equation"
    , "aligned"
    , "array"
    , "textarray"
    , "code"
    , "verse"
    , "verbatim"
    , "load"
    , "load-data"
    , "load-files"
    , "include"
    , "hide"
    , "texComment"
    , "docinfo"
    , "mathmacros"
    , "textmacros"
    , "csvtable"
    , "chart"
    , "svg"
    , "quiver"
    , "image"
    , "tikz"
    , "setup"
    , "iframe"
    , "settings"
    , "book"
    , "article"
    ]


{-| Parse a list of strings into a list of PrimitiveBlocks.
-}
parse : List String -> List PrimitiveBlock
parse lines =
    loop (init lines) nextStep



-- STATE


type alias State =
    { blocks : List PrimitiveBlock -- accumulated blocks (reversed)
    , currentBlock : Maybe PrimitiveBlock -- block being built
    , lines : List String -- remaining input lines
    , lineNumber : Int -- current line number
    , position : Int -- character position in source
    , blocksCommitted : Int -- number of committed blocks
    , inHeader : Bool -- are we still in the extended header (continuation lines)?
    }


init : List String -> State
init lines =
    { blocks = []
    , currentBlock = Nothing
    , lines = lines
    , lineNumber = 0
    , position = 0
    , blocksCommitted = 0
    , inHeader = False
    }



-- MAIN LOOP


nextStep : State -> Step State (List PrimitiveBlock)
nextStep state =
    case List.head state.lines of
        Nothing ->
            -- No more lines: commit any open block and return
            Done (List.reverse (commitBlock state).blocks)

        Just rawLine ->
            let
                currentLine =
                    Line.classify state.position state.lineNumber rawLine

                next =
                    advance currentLine state

                isEmpty =
                    currentLine.indent == 0 && String.isEmpty (String.trim currentLine.content)

                isNonEmptyBlank =
                    currentLine.indent > 0 && String.isEmpty (String.trim (String.dropLeft currentLine.indent currentLine.content))
            in
            case ( state.currentBlock /= Nothing, isEmpty, isNonEmptyBlank ) of
                -- State 1: Not in block, empty line -> skip
                ( False, True, _ ) ->
                    Loop next

                -- State 2: Not in block, non-empty blank line -> skip
                ( False, False, True ) ->
                    Loop next

                -- State 3: Not in block, content line -> create new block
                ( False, False, False ) ->
                    Loop (createBlock currentLine next)

                -- State 4: In block, non-empty content -> add line
                ( True, False, _ ) ->
                    Loop (addCurrentLine currentLine next)

                -- State 5: In block, empty line -> commit block
                ( True, True, _ ) ->
                    Loop (commitBlock next)



-- HELPER FUNCTIONS


{-| Advance past the current line. Every step does this; the handlers below
receive the already-advanced state.
-}
advance : Line -> State -> State
advance line state =
    { state
        | lines = List.drop 1 state.lines
        , lineNumber = state.lineNumber + 1
        , position = state.position + String.length line.content + 1
    }


{-| Create a new block from the current line.
-}
createBlock : Line -> State -> State
createBlock line state =
    let
        newBlock =
            blockFromLine line
    in
    { state
        | currentBlock = Just newBlock
        , inHeader = isBlockWithHeader newBlock
    }


{-| Create a PrimitiveBlock from a Line.
-}
blockFromLine : Line -> PrimitiveBlock
blockFromLine line =
    let
        headingData =
            getHeadingData line.content

        bodyLineNumber =
            case headingData.heading of
                Paragraph ->
                    line.lineNumber

                _ ->
                    line.lineNumber + 1

        -- True for blocks whose first source line is a discardable header
        -- (| name, || name, $$, ```). Detected via firstLine == "": those
        -- heading parsers store an empty firstLine because the raw heading
        -- line is not kept as block content. Paragraph blocks with an empty
        -- first line are excluded explicitly.
        hasHeaderLine =
            headingData.firstLine == "" && headingData.heading /= Paragraph

        contentBegin_ =
            if hasHeaderLine then
                line.position + String.length line.content + 1

            else
                line.position

        contentEnd_ =
            if hasHeaderLine then
                contentBegin_

            else
                line.position + String.length line.content

        meta : BlockMeta
        meta =
            { id = ""
            , position = line.position
            , lineNumber = line.lineNumber
            , bodyLineNumber = bodyLineNumber
            , numberOfLines = 1
            , begin = line.position
            , end = lineEnd line
            , contentBegin = contentBegin_
            , contentEnd = contentEnd_
            , messages = []
            , sourceText = line.content
            , error = Nothing
            }
    in
    { heading = headingData.heading
    , indent = line.indent
    , args = headingData.args
    , properties = headingData.properties
    , firstLine = headingData.firstLine
    , body = []
    , meta = meta
    , style = {}
    }


{-| Add the current line to the block being built.

Includes list coalescing: when consecutive item or numbered lines are found,
the block heading changes to itemList or numberedList respectively.

Also handles continuation lines for extended header syntax.

-}
addCurrentLine : Line -> State -> State
addCurrentLine line state =
    let
        -- Check if this is a continuation line for extended header syntax
        currentIsVerbatim =
            case Maybe.map .heading state.currentBlock of
                Just (Verbatim _) ->
                    True

                _ ->
                    False

        isContinuation =
            state.inHeader && isContinuationLine currentIsVerbatim line.content
    in
    if isContinuation then
        -- Merge continuation line's args/properties into the current block
        { state | currentBlock = Maybe.map (mergeContinuationLine line) state.currentBlock }

    else
        -- Normal line processing (end of header, now in body)
        { state
            | currentBlock = Maybe.map (addBodyLine line) state.currentBlock
            , inHeader = False
        }


{-| Add a body line to a block, coalescing list items: consecutive `item`
lines become an `itemList`, and consecutive `numbered` lines a `numberedList`.
-}
addBodyLine : Line -> PrimitiveBlock -> PrimitiveBlock
addBodyLine line block =
    case ( block.heading, ListItem.kind line.content ) of
        ( Ordinary name, Just kind ) ->
            if name == kind.item then
                addRawLineToBlock line { block | heading = Ordinary kind.list }

            else if name == kind.list then
                addRawLineToBlock line block

            else
                addLineToBlock line block

        ( Ordinary "itemList", Nothing ) ->
            -- continuation of the last item; Pipeline.groupListItems merges it
            addRawLineToBlock line block

        ( Ordinary "numberedList", Nothing ) ->
            addRawLineToBlock line block

        _ ->
            addLineToBlock line block


{-| Add a line to a block's body exactly as written. List blocks keep their
lines raw: nested items are identified by their indent.
-}
addRawLineToBlock : Line -> PrimitiveBlock -> PrimitiveBlock
addRawLineToBlock line block =
    let
        meta =
            block.meta
    in
    { block
        | body = line.content :: block.body
        , meta = { meta | numberOfLines = meta.numberOfLines + 1, end = lineEnd line }
    }


{-| Add a line to a block's body.
-}
addLineToBlock : Line -> PrimitiveBlock -> PrimitiveBlock
addLineToBlock line block =
    let
        -- Determine the content to add based on block type
        contentToAdd =
            if block.indent > 0 && line.indent >= block.indent then
                -- For indented blocks, drop the indent prefix
                String.dropLeft block.indent line.content

            else
                line.content

        meta =
            block.meta
    in
    { block
        | body = contentToAdd :: block.body -- prepend (will reverse later)
        , meta = { meta | numberOfLines = meta.numberOfLines + 1, end = lineEnd line }
    }


{-| Commit the current block and reset for the next one.
-}
commitBlock : State -> State
commitBlock state =
    let
        committedBlocks =
            case state.currentBlock of
                Nothing ->
                    state.blocks

                Just block ->
                    let
                        finalBlock =
                            finalize block
                                |> setBlockId state.blocksCommitted
                    in
                    finalBlock :: state.blocks
    in
    { state
        | blocks = committedBlocks
        , currentBlock = Nothing
        , blocksCommitted = state.blocksCommitted + 1
        , inHeader = False
    }


{-| Finalize a block by reversing the body and reconstructing sourceText.

For Paragraph blocks, firstLine is content (not a header), so it's prepended to body.
For Ordinary/Verbatim blocks, firstLine was the header line and body has the content.

-}
finalize : PrimitiveBlock -> PrimitiveBlock
finalize block =
    let
        reversedBody =
            List.reverse block.body

        -- For paragraphs, firstLine is content, not a header
        firstLineIsContent =
            (block.heading == Paragraph || block.heading == Ordinary "section")
                && not (String.isEmpty block.firstLine)

        finalBody =
            if firstLineIsContent then
                block.firstLine :: reversedBody

            else
                reversedBody

        meta =
            block.meta

        -- Use `meta.sourceText` (the raw heading line captured at block
        -- construction, plus any header continuation lines) rather than
        -- `block.firstLine`, which for `|`, `||`, `$$`, and ``` blocks has
        -- been stripped of the heading.
        sourceText =
            if List.isEmpty reversedBody then
                meta.sourceText

            else
                meta.sourceText ++ "\n" ++ String.join "\n" reversedBody
    in
    { block
        | body = finalBody
        , meta =
            { meta
                | sourceText = sourceText
                , contentEnd = meta.end
            }
    }


{-| Offset just past the last character of a line, as written in the source.
A block's `end` is the `lineEnd` of its last line. It is tracked line by line,
not computed from `sourceText`, because body lines of an indented block are
stored with the indentation removed.
-}
lineEnd : Line -> Int
lineEnd line =
    line.position + String.length line.content


{-| Set the block ID.
-}
setBlockId : Int -> PrimitiveBlock -> PrimitiveBlock
setBlockId index block =
    let
        meta =
            block.meta

        id =
            String.fromInt meta.lineNumber ++ "-" ++ String.fromInt index
    in
    { block | meta = { meta | id = id } }



-- HEADING DATA


type alias HeadingData =
    { heading : Heading
    , args : List String
    , properties : Dict String String
    , firstLine : String
    }


{-| Extract heading data from a line.
-}
getHeadingData : String -> HeadingData
getHeadingData line =
    let
        trimmed =
            String.trim line
    in
    if String.startsWith "|| " trimmed then
        -- Verbatim block: || blockname -- LEGACY, eventually phase out?
        getVerbatimHeading trimmed

    else if String.startsWith "| " trimmed then
        -- Ordinary block: | blockname
        getHeading trimmed

    else if String.startsWith "```" trimmed then
        -- Code fence
        { heading = Verbatim "code"
        , args = []
        , properties = Dict.empty
        , firstLine = ""
        }

    else if String.startsWith "$$" trimmed then
        -- Math block
        { heading = Verbatim "math"
        , args = []
        , properties = Dict.empty
        , firstLine = ""
        }

    else if String.startsWith "# " trimmed then
        markdownHeading 1 trimmed

    else if String.startsWith "## " trimmed then
        markdownHeading 2 trimmed

    else if String.startsWith "### " trimmed then
        markdownHeading 3 trimmed

    else
        case ListItem.kind trimmed of
            Just kind ->
                -- List item (preserve full line including prefix)
                { heading = Ordinary kind.item
                , args = []
                , properties = Dict.empty
                , firstLine = trimmed
                }

            Nothing ->
                { heading = Paragraph
                , args = []
                , properties = Dict.empty
                , firstLine = line
                }


{-| Markdown-style section heading (`#`, `##`, `###`) of the given level.
-}
markdownHeading : Int -> String -> HeadingData
markdownHeading level trimmed =
    let
        levelString =
            String.fromInt level
    in
    { heading = Ordinary "section"
    , args = [ levelString ]
    , properties = Dict.singleton "level" levelString
    , firstLine = String.dropLeft (level + 1) trimmed
    }


{-| Parse verbatim heading: || blockname arg1 arg2 ...
-}
getVerbatimHeading : String -> HeadingData
getVerbatimHeading line =
    let
        afterPrefix =
            String.dropLeft 3 line

        parts =
            String.words afterPrefix

        name =
            List.head parts |> Maybe.withDefault "code"

        ( args, properties ) =
            Tools.KV.argsAndPropertiesFromList (List.drop 1 parts)
    in
    { heading = Verbatim name
    , args = args
    , properties = properties
    , firstLine = ""
    }


{-| Parse ordinary heading: | blockname arg1 arg2 ...
-}
getHeading : String -> HeadingData
getHeading line =
    let
        afterPrefix : String
        afterPrefix =
            String.dropLeft 2 line

        parts =
            String.words afterPrefix

        name =
            List.head parts |> Maybe.withDefault "block"

        ( args, properties_ ) =
            Tools.KV.argsAndPropertiesFromList (List.drop 1 parts)

        properties =
            if name /= "section" then
                properties_

            else
                let
                    level =
                        List.head args
                            |> Maybe.andThen (\str -> String.toInt str |> Maybe.map (\_ -> str))
                            |> Maybe.withDefault "1"
                in
                Dict.insert "level" level properties_
    in
    { heading =
        if isVerbatimName name then
            Verbatim name

        else
            Ordinary name
    , args = args
    , properties = properties
    , firstLine = ""
    }


isVerbatimName : String -> Bool
isVerbatimName str =
    List.member str verbatimNames



-- CONTINUATION LINE HANDLING


{-| List of known ordinary block names (not verbatim).
Used to distinguish continuation lines from new blocks.
-}
ordinaryNames : List String
ordinaryNames =
    [ "section"
    , "theorem"
    , "definition"
    , "lemma"
    , "corollary"
    , "proposition"
    , "proof"
    , "remark"
    , "example"
    , "exercise"
    , "note"
    , "problem"
    , "solution"
    , "question"
    , "answer"
    , "abstract"
    , "title"
    , "subtitle"
    , "author"
    , "date"
    , "contents"
    , "index"
    , "bibliography"
    , "quotation"
    , "table"
    , "item"
    , "numbered"
    , "heading"
    , "subheading"
    , "document"
    , "endnotes"
    , "set-key"
    ]


{-| Check if a block has a header (Ordinary or Verbatim, not Paragraph).
-}
isBlockWithHeader : PrimitiveBlock -> Bool
isBlockWithHeader block =
    case block.heading of
        Paragraph ->
            False

        _ ->
            True


{-| Check if a line is a continuation line (extends the header with more args/properties).
A continuation line:

1.  Starts with "| " (pipe + space)
2.  The first word after "| " is NOT a known block name (unless it contains a colon)

-}
isContinuationLine : Bool -> String -> Bool
isContinuationLine isVerbatim line =
    let
        trimmed =
            String.trim line
    in
    if String.startsWith "| " trimmed then
        let
            afterPrefix =
                String.dropLeft 2 trimmed

            firstWord =
                String.words afterPrefix |> List.head |> Maybe.withDefault ""
        in
        if isVerbatim then
            -- For verbatim blocks, only property lines (containing ":") are continuations
            String.contains ":" firstWord

        else
            -- For ordinary blocks, properties OR unknown names are continuations
            String.contains ":" firstWord
                || not (isKnownBlockName firstWord)

    else
        False


{-| Check if a name is a known block name (verbatim or ordinary).
-}
isKnownBlockName : String -> Bool
isKnownBlockName name =
    List.member name verbatimNames || List.member name ordinaryNames


{-| Merge a continuation line's args and properties into a block.
The line is part of the block's header: it is added to `sourceText`, and the
content starts after it.
-}
mergeContinuationLine : Line -> PrimitiveBlock -> PrimitiveBlock
mergeContinuationLine line block =
    let
        trimmed =
            String.trim line.content

        afterPrefix =
            String.dropLeft 2 trimmed

        parts =
            String.words afterPrefix

        ( newArgs, newProps ) =
            Tools.KV.argsAndPropertiesFromList parts

        ( mergedArgs, mergedProps ) =
            Tools.KV.mergeArgsAndProperties ( block.args, block.properties ) ( newArgs, newProps )

        meta =
            block.meta
    in
    { block
        | args = mergedArgs
        , properties = mergedProps
        , meta =
            { meta
                | numberOfLines = meta.numberOfLines + 1
                , bodyLineNumber = meta.bodyLineNumber + 1
                , sourceText = meta.sourceText ++ "\n" ++ line.content
                , contentBegin = meta.contentBegin + String.length line.content + 1
                , end = lineEnd line
            }
    }
