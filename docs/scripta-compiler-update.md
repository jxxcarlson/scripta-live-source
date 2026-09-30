# Scripta compiler update: v2 → v3

On 2026-09-30 Scripta Live moved from a vendored copy of `scripta-compiler-v2` to a vendored copy of `scripta-compiler-v3`, commit `f22b9ae`. The web (SQLite), web (localStorage) and Tauri builds were ported. The plan and working notes are in `docs/plans/2026-09-30-port-to-v3.md`.

## Compiler

- `vendored-compiler/src` is now v3's `src` (without `TestData.elm`). The copied commit is recorded in `vendored-compiler/VERSION.md`.
- The v2 API is gone: `ScriptaV2.*`, the differential compiler, `EditRecord`, `MarkupMsg`, and the MicroLaTeX, MiniLaTeX, SMarkdown and XMarkdown parsers. v3 compiles Scripta only. The app only ever used Scripta, so no feature was lost.
- The app uses v3's public `Scripta` module:
  - `parse` for a new document, and `reparse` (incremental) for each edit;
  - `render`, which returns `Html Scripta.Event` (title, body, TOC, banner);
  - `Scripta.Options` for theme, widths, TOC and filter.
- v3 declares Elm 0.19.2 but compiles under 0.19.1, and the app stays on 0.19.1. If the `elm` on your PATH is 0.19.2, build with `~/.elm/elm-tooling/elm/0.19.1/elm`.

## App changes

### Model and view (`src/Common/Model.elm`, `src/Common/View.elm`)

- `CommonModel` holds three compiler fields: `options : Scripta.Options`, `document : Scripta.Document`, and `compilerOutput : Scripta.Output Scripta.Event`.
  - These replace `params`, `currentLanguage`, `editRecord` and the v2 `compilerOutput`.
  - `displaySettings` is reduced to `{ windowWidth : Int }`.
- New helpers keep the document and output current:
  - `loadSource`: full parse, used on load or document switch.
  - `updateSource`: incremental reparse.
  - `applyEdit`: `updateSource` plus title and change tracking.
  - `refreshOptions`: used after a theme change or resize.
- Two more shared helpers: `contentWidth` computes the rendered-column width, and `compilerEventCmd` handles clicks.
- Rendering happens in `update`, only when the source or options change, not on every view.
- The view wraps the v3 `Html` in `Element.html` with `width fill`. Without it, elm-ui sized the body to its widest child and pushed centred images and equations off-screen.
- The TOC comes from `output.toc` and no longer expands or collapses. The app's duplicate "Contents" heading was removed.
- The old editor-sync state and messages were removed: `editorData`, `selectedId`, `foundIds`, `SelectedText`, `StartSync`, `SelectId` and others. A single `CompilerEvent Scripta.Event` message replaces `Render MarkupMsg`.

### Entry points (`src/MainSQLite.elm`, `src/MainLocal.elm`, `src/MainTauri.elm`)

- All three use the shared helpers above.
- `MainLocal` now computes the rendered width the same way as the other two. It used `width // 3` on resize.
- Theme changes that come from storage or a loaded document now refresh the compiler options.

### Exports and imports

- **LaTeX and raw LaTeX export, and PDF:** new module `src/ScriptaExport.elm`.
  - v3 drops `title` and `document` blocks at parse time for display, so it re-parses the source without that filter before exporting.
  - Image urls for the PDF server are collected from the v3 AST (`Frontend/PDF.elm`).
- **LaTeX import:** uses the standalone `LaTeXToScripta.convert`, moved to `vendored-converter/latex/` and added as a source directory. Its output differs from v2's `translate`.
- **Markdown import:** unchanged; it still uses the `jxxcarlson/markdown-to-scripta` package.

### Theme and colours

- `Render.NewColor` moved into the app as `src/NewColor.elm`, because v3 has no colour module.
- `Theme.mapTheme` now returns `Scripta.Theme`.

### Other Elm changes

- `Widget.elm` no longer depends on `Model`. The widgets that send `Model.Msg`, which only `Main.elm` uses, moved to `src/MainWidget.elm`.
- Dead and test-only modules were deleted: `Debug*.elm`, `Test*.elm`, `QuickTest`, `MinimalHrefTest`, `Export`, `Download`, `Util` and `EditorSync`.

## Editor and sync (JavaScript)

- **Editor:** the app uses the v3 Demo's CodeMirror element.
  - Its source is `editor-prepare/scripta-editor.js`, copied from `scripta-compiler-v3/Demo/codemirror-element.js`. It is bundled locally with `npx rollup -c rollup.scripta.config.mjs` into `assets/codemirror-element.js`, so no CDN is needed and the Tauri build works offline.
  - One local change: a document load puts the cursor at the top. Without it, the editor could open scrolled part-way down.
- **Sync:** `assets/editor-sync.js` is adapted from the Demo's `index.html`. All three HTML hosts load it and call `setupEditorSync(app)`.
  - Clicking a word in the rendered output highlights that word in the editor. Clicking math highlights its source: `$…$` for inline math, the whole block for display math.
  - Selecting text in the rendered output highlights the source in the editor, including selections that cross markup such as `Hello [b world]`.
  - `data-begin` is not always measured from the start of the source line: list items, headings and elements like `[i …]` measure from after their prefix. So the computed position is only an estimate, and the rendered text is then looked up in the source near it. Block elements (display math, images, list items) carry absolute `data-begin`/`data-end` offsets.
  - Ctrl+S on an editor selection highlights the matching rendered element.
  - ESC clears highlights and restores the scroll position.
  - TOC, footnote and citation clicks scroll the rendered text, using the new `scrollToElement` port.
  - PDF-error clicks go to the editor line, using the new `selectInEditor` port.
  - v3 element ids (`e-<line>.<n>`) use 0-based lines, which are converted to CodeMirror's 1-based lines.
  - v3 emits no event for a plain click on rendered text, so click sync is handled entirely in JS. Clicks on links (footnotes, citations, references) are left to Elm.
- **Math:** `assets/katex.js` now re-renders `math-text` when its `content` or `display` changes, because v3 reuses math nodes across edits.
- **Caching:** `server.py` sends `Cache-Control: no-cache`, and the HTML hosts version the changed scripts (`?v=v3`). Without this, browsers kept the old editor bundle and showed an empty editor.

## Not ported

- `src/Main.elm` (the older Tauri/LocalStorage build) and `src/ViewScripta.elm` (the `vs` viewer) do not compile against v3.
- `run.sh` and `npx elm-watch hot` use the `elm` on your PATH. They fail if that is 0.19.2.

## Verification

- The SQLite and localStorage builds were tested in headless Chrome:
  - rendering, math and the TOC;
  - edit and incremental reparse;
  - math re-render after an edit;
  - theme toggle;
  - Ctrl+S sync, and rendered-selection → editor sync.
- The Tauri build was compile-checked only.
- LaTeX export, image-url extraction and LaTeX import were run in an Elm worker.
