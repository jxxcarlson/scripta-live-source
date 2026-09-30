module Parser.ListItem exposing (Kind, kind, stripPrefix)

{-| List item syntax: a line whose trimmed text starts with `"- "` is a bulleted
item, and one starting with `". "` is a numbered item.
-}


{-| Block names for a single item of a kind and for a list of them.
-}
type alias Kind =
    { item : String, list : String }


{-| The kind of list item a line is, if any.
-}
kind : String -> Maybe Kind
kind line =
    let
        trimmed =
            String.trim line
    in
    if String.startsWith "- " trimmed then
        Just { item = "item", list = "itemList" }

    else if String.startsWith ". " trimmed then
        Just { item = "numbered", list = "numberedList" }

    else
        Nothing


{-| Trim a line and remove its list prefix, if it has one.
-}
stripPrefix : String -> String
stripPrefix line =
    let
        trimmed =
            String.trim line
    in
    case kind trimmed of
        Just _ ->
            String.dropLeft 2 trimmed

        Nothing ->
            trimmed
