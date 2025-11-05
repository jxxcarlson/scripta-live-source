# vs - Scripta File Viewer

A command-line script for rendering `.scripta` files to HTML and viewing them in your browser.

## Installation

```bash
cd /Users/carlson/dev/elm-work/scripta/scripta-live
./install-vs.sh
```

This will:
1. Copy `vs` to `~/bin/vs`
2. Make it executable
3. Configure the correct project directory path
4. Check if `~/bin` is in your PATH

If `~/bin` is not in your PATH, add this to your `~/.zshrc` or `~/.bashrc`:
```bash
export PATH="$HOME/bin:$PATH"
```

Then reload your shell:
```bash
source ~/.zshrc
```

## Usage

**Read from stdin (default):**
```bash
cat file.scripta | vs
echo "| section\nHello" | vs
```

**Read from file:**
```bash
vs -f FILE.scripta
```

**Backward compatible:**
```bash
vs FILE.scripta
```

The script will:
1. Compile the Elm viewer (on first run and when code changes)
2. Read your `.scripta` file
3. Generate an HTML file with the rendered content
4. Automatically open it in your default browser

## Examples

```bash
# From file
vs -f test.scripta

# From stdin
cat test.scripta | vs

# Backward compatible
vs test.scripta

# Pipe from command
echo "| section\nTest\n\nHello **world**" | vs
```

## Features

- **Automatic language detection**: Detects MicroLaTeX, Enclosure, or SMarkdown syntax
- **Math rendering**: Full KaTeX support for mathematical expressions
- **Syntax highlighting**: Code blocks are properly formatted
- **Responsive layout**: 800px document width, centered on page
- **Theme support**: Currently uses Light theme

## Language Detection

The viewer automatically detects the markup language:

- **MicroLaTeX**: Contains `\begin{` or `\section`
- **Enclosure**: Contains `|>` or `| section`
- **SMarkdown**: Default fallback

## Files

- **`vs`**: The main bash script
- **`src/ViewScripta.elm`**: Elm program that renders Scripta content
- **`.vs-tmp/`**: Temporary directory for compiled output
  - `view.js`: Compiled Elm application
  - `view.html`: Generated HTML file with rendered content

## Requirements

- Elm compiler (0.19.1)
- Node.js (for content escaping)
- Modern web browser

## How It Works

1. The bash script reads your `.scripta` file
2. Compiles the `ViewScripta.elm` program to JavaScript
3. Creates an HTML file with:
   - KaTeX CDN links for math rendering
   - The compiled Elm app
   - Your file content injected as a JavaScript string
4. Opens the HTML file in your browser
5. The Elm app renders the Scripta content using the full compiler API

## Customization

To customize the rendering, edit `src/ViewScripta.elm`:

- **Document width**: Change `docWidth = 800` (line 110)
- **Theme**: Change `theme = Render.Theme.Light` to `Render.Theme.Dark` (line 115)
- **Window width**: Change `windowWidth = 900` (line 116)
- **Scaling**: Change `scale = 1` (line 118)

## Troubleshooting

**Compilation errors:**
```bash
elm make src/ViewScripta.elm --output=/dev/null
```

**Check generated HTML:**
```bash
open .vs-tmp/view.html
```

**View browser console:**
Check for JavaScript errors or KaTeX rendering issues.

## Related Files

- **`rendering.md`**: Complete documentation of the Scripta rendering API
- **`test.scripta`**: Sample test file demonstrating various features
