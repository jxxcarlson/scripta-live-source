# Scripta Live

A web-based live editor and compiler for multiple markup languages, providing real-time rendering in a split-pane interface.

## What is Scripta Live?

Scripta Live is a demonstration application for Scripta Compiler V2 that compiles and renders three different markup languages:

- **MicroLaTeX** - LaTeX-like syntax for mathematical and scientific documents
- **SMarkdown** - Scripta Markdown with enhanced features
- **Enclosure Language** - Pipe-based block syntax (also known as Scripta)

The application provides a live editor where you can type in any of these languages and see the rendered output in real-time, with full support for:
- Mathematical expressions (KaTeX rendering)
- Code syntax highlighting
- Document structure and formatting
- Cross-references and citations

## Quick Start

### Running the Application

The simplest way to run Scripta Live:

```bash
./run.sh
```

Then open your browser to **http://localhost:8012**

This script will:
1. Start an HTTP server on port 8012 (serving the app)
2. Start elm-watch on port 8009 (for hot reloading)
3. Compile the Elm code if needed

To stop the application, press `Ctrl+C` in the terminal.

### Alternative: Manual Start

If you prefer to start components separately:

```bash
# Start elm-watch for development with hot reloading
npx elm-watch hot

# In another terminal, serve the app (from assets directory)
cd assets && python3 -m http.server 8012
```

Then access at http://localhost:8012/index-sqlite.html

## Development

### Prerequisites

- Elm 0.19.1
- Node.js (for elm-watch)
- Python 3 (for the HTTP server)

### Development Commands

```bash
# Start development server with hot reloading (recommended)
./run.sh

# Alternative: use make.sh
./make.sh

# Run code review
npm run review

# Generate call graph
npm run cgraph

# Production build
elm make src/MainSQLite.elm --output=./assets/main-sqlite.js
```

### Project Structure

```
scripta-live/
├── src/
│   ├── MainSQLite.elm       # Main application entry point
│   ├── Main.elm              # Alternative entry point
│   ├── Model.elm             # Application model
│   ├── Data/                 # Sample texts for each language
│   └── ...
├── vendored-compiler/        # Local copy of Scripta compiler
│   └── src/ScriptaV2/        # Compiler modules
├── assets/
│   ├── index-sqlite.html     # Main HTML file
│   └── main-sqlite.js        # Compiled Elm output
├── run.sh                    # Run script (starts server + elm-watch)
└── server.py                 # Custom HTTP server
```

### Architecture

The application follows standard Elm Architecture (TEA):

- **Model** - Application state including source text, compiled output, settings
- **Update** - Message handling and state transitions
- **View** - UI rendering using elm-ui

Key components:
- `Scripta` (vendored compiler) - public API: `parse` / `reparse` build a `Document`, `render` turns it into `Html` emitting `Scripta.Event`s
- `Common.Model` - shared model; `loadSource`, `updateSource` and `refreshOptions` keep the parsed document and rendered output current
- `ScriptaExport` - LaTeX export and image urls for PDF, using the compiler's internal modules
- `assets/codemirror-element.js` - the editor, built from `editor-prepare/scripta-editor.js`
- `assets/editor-sync.js` - editor ↔ rendered-text sync (click a word or equation, or select text, in the rendered output → editor; Ctrl+S in the editor → rendered text; ESC clears)

The compiler lives in `vendored-compiler/src/`, a copy of `scripta-compiler-v3` (see `vendored-compiler/VERSION.md` for the commit). LaTeX import uses `vendored-converter/latex/`.

## Updating the Vendored Compiler

1. Replace `vendored-compiler/src` with the chosen commit of `../scripta-compiler-v3` and record it in `vendored-compiler/VERSION.md`:
   ```bash
   rm -rf vendored-compiler/src
   git -C ../scripta-compiler-v3 archive <commit> src | tar -x -C vendored-compiler
   rm vendored-compiler/src/TestData.elm
   ```

2. Compile the three entry points. The app uses Elm 0.19.1; if the `elm` on your PATH is 0.19.2, use the 0.19.1 binary from elm-tooling:
   ```bash
   ELM=~/.elm/elm-tooling/elm/0.19.1/elm
   $ELM make src/MainSQLite.elm --output=assets/main-sqlite.js
   $ELM make src/MainLocal.elm --output=assets/main-local.js
   $ELM make src/MainTauri.elm --output=assets/main-tauri.js
   ```

3. If the compiler's editor changed, update `editor-prepare/scripta-editor.js` from `scripta-compiler-v3/Demo/codemirror-element.js` (keep the local change in `setEditorText` that scrolls to the top on load) and rebuild:
   ```bash
   cd editor-prepare && npx rollup -c rollup.scripta.config.mjs
   ```

`src/Main.elm` (the older Tauri/LocalStorage build) and `src/ViewScripta.elm` (the `vs` viewer) have not been ported to v3 and do not compile.

## Additional Tools

### vs - Command-line Viewer

Scripta Live also includes a command-line tool for viewing `.scripta` files:

```bash
# Install
./install-vs.sh

# Use
vs -f file.scripta
cat file.scripta | vs
```

See [README-vs.md](README-vs.md) for complete documentation.

## Contributing

When making changes:

1. Ensure code compiles without errors
2. Test hot reloading with `./run.sh`
3. Run code review: `npm run review`
4. Test all three language modes (MicroLaTeX, SMarkdown, Scripta)

## Resources

- **CLAUDE.md** - Development guide for AI assistants
- **README-vs.md** - Command-line viewer documentation
- Main Scripta Compiler repository (parent directory)

## License

(Add license information here)
