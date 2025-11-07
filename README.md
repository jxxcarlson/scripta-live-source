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
- `ScriptaV2.API` - Core compiler API
- `ScriptaV2.DifferentialCompiler` - Incremental compilation for live editing
- `Render.Block` - Rendering compiled output to HTML

The actual compiler lives in the `vendored-compiler/src/ScriptaV2/` directory.

## Updating the Vendored Compiler

The application uses a vendored copy of the Scripta compiler. When the compiler is updated, you may need to fix compatibility issues.

### Update Process

1. **Update the vendored compiler files** (usually done via a script or manual copy from the main compiler repo)

2. **Identify breaking changes** by compiling:
   ```bash
   elm make src/MainSQLite.elm --output=/dev/null
   ```

3. **Common issues to fix:**

   - **Module/type renames**: Update imports and type references
   - **Function signature changes**: Adjust function calls to match new signatures
   - **Removed/renamed variants**: Update pattern matches and constructors

4. **Test compilation:**
   ```bash
   # Test main build
   elm make src/MainSQLite.elm --output=/dev/null

   # Test with elm-watch
   npx elm-watch hot
   ```

5. **Run the app to verify:**
   ```bash
   ./run.sh
   ```

### Recent Update Example

When updating from an older compiler version, we fixed:

- `M.PrimitiveBlock` → `Scripta.PrimitiveBlock`
- `ScriptaV2.Language.EnclosureLang` → `ScriptaV2.Language.ScriptaLang`
- `ScriptaV2.Compiler.SuppressDocumentBlocks` → `ScriptaV2.Types.SuppressDocumentBlocks`
- Function signatures for `compileStringWithTitle` and `editRecordToCompilerOutput` changed from multiple parameters to a single `CompilerParameters` record

### Compatibility Helpers

Created `makeCompilerParams` helper function in `Main.elm` to build the new `CompilerParameters` record from the existing model structure, making the migration easier.

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
