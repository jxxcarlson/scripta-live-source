# Editor code

In the v3 compiler port, the editor and most of its JavaScript came from the Demo app in `scripta-compiler-v3/Demo`. The Elm code that talks to the editor is the app's own, adapted to the new editor.

Line numbers are as of this writing.

## From the Demo app

### The editor itself

- `editor-prepare/scripta-editor.js` is a copy of `Demo/codemirror-element.js`. It defines the `<codemirror-editor>` element (`scripta-editor.js:568`).
- It is bundled into `assets/codemirror-element.js` by `editor-prepare/rollup.scripta.config.mjs`. The bundle is self-contained, with no CDN. To rebuild: `cd editor-prepare && npm start`.
- One local change: `setEditorText` (`scripta-editor.js:341`, comment at `:355`) puts the cursor at the top when a document is loaded.
- Unchanged from the Demo:
  - the Ctrl+S handler, which emits `sync-to-rendered` (`:454`);
  - the sync-highlight hook `setSyncHighlight` (`:501`).
- The editor emits `text-change` with `{position, source}`.

### Sync JavaScript

`assets/editor-sync.js` is adapted from the script in `Demo/index.html`: port subscriptions, preview-selection → editor, Ctrl+S → preview, and Esc. Additions made here:

| Addition | Where |
|---|---|
| Wire up the Elm ports | `setupEditorSync` (`:74`) |
| Convert v3's 0-based element ids to editor (1-based) lines | `lineOfId` (`:40`) |
| Find clicked or selected text in the source near the estimated position | `findNear` / `locateText` (`:129`, `:156`) |
| Find the enclosing block (images, display math, list items) | `blockElement` (`:180`) |
| Click → editor: a word, inline math, or display math | `mouseup` handler (`:216`) |
| Ctrl+S → preview: highlight images and display math, not the block before them | `sync-to-rendered` handler (`:277`) |
| Esc clears highlights and restores the scroll position | `keydown` handler (`:113`) |

### HTML hooks

Each host page loads `codemirror-element.js` and `editor-sync.js` and calls `setupEditorSync(app)` after `Elm.<Main>.init`:

| Page | Lines |
|---|---|
| `assets/index-sqlite.html` | 54, 57, 202 |
| `assets/index-local.html` | 24, 27, 54 |
| `assets/index-tauri.html` | 25, 28, 75 |

## The app's Elm code that touches the editor

- **`Common.View`**
  - `editorView` (`:630`) renders `<codemirror-editor>` (`:645`), with `load`/`text` attributes (`:652`).
  - `onTextChange` (`:668`) decodes `text-change` into `InputText2`.
- **`Ports`** (`:72–73`): `selectInEditor` (highlight a range in the editor) and `scrollToElement` (scroll and highlight in the preview).
- **`Common.Model`**
  - `compilerEventCmd` (`:334`) handles clicks from the preview (TOC, footnotes, citations → `scrollToElement`).
  - `focusEditorOnLine` (`:444`) handles clicks on PDF error buttons (→ `selectInEditor`).
- **`ScriptaExport`**: `sourceBlockAt` (`:75`) maps a PDF error line (0-based) to the block to highlight in the editor.
- **`MainSQLite` / `MainLocal` / `MainTauri`**:

| Branch | MainSQLite | MainLocal | MainTauri |
|---|---|---|---|
| `InputText2` (text changes) | 347 | 172 | 117 |
| `CompilerEvent` | 354 | 179 | 124 |
| `FocusOnEditorLine` | 732 | 348 | 285 |

## What it replaced (v2, see commit `5b105b9`)

- **The old editor**: `editor-prepare/editor.js`, bundled by `editor-prepare/rollup.config.mjs` and `editor-prepare/make.sh`, with `initializer.txt` appended.
  - Attributes: `load`, `text`, `editordata`, `refineselection` and `selection`.
  - Events: `text-change`, `cursor-change` and `selected-text`.
  - The HTML pages started it by calling `initCodeMirror()`.
- **Elm state and handlers**:
  - fields `editorData`, `doSync`, `maybeSelectionOffset`, `selectedId` and `foundIds`, and related fields;
  - the `SelectedText`, `StartSync` and `SelectId` handlers;
  - all in `Common.Model`, `Common.View` and the Main files.

These old editor files have been deleted: `editor.js`, `rollup.config.mjs`, `make.sh`, `initializer.txt`, `scripts.yaml` (the old build steps), and `editor-rlsync-test.html` (a test page for the old editor). `npm start` in `editor-prepare/` now builds the new editor.

`src/Sync.elm` and `src/Editor.elm` remain, because the unported `src/Main.elm` and `src/Model.elm` still use them.
