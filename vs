#!/bin/bash
# vs - View Scripta content
# Usage: vs [-f FILE]
#   Default: reads from stdin
#   -f FILE: reads from file

set -e

# Parse arguments
USE_FILE=false
SCRIPTA_FILE=""
SCRIPTA_CONTENT=""

if [ $# -eq 0 ]; then
    # Read from stdin
    SCRIPTA_CONTENT=$(cat)
elif [ "$1" = "-f" ]; then
    # Read from file
    if [ $# -lt 2 ]; then
        echo "Usage: vs [-f FILE]"
        echo "  Default: reads from stdin"
        echo "  -f FILE: reads from file"
        exit 1
    fi
    USE_FILE=true
    SCRIPTA_FILE="$2"

    if [ ! -f "$SCRIPTA_FILE" ]; then
        echo "Error: File '$SCRIPTA_FILE' not found"
        exit 1
    fi

    # Convert to absolute path
    SCRIPTA_FILE="$(cd "$(dirname "$SCRIPTA_FILE")" && pwd)/$(basename "$SCRIPTA_FILE")"
    SCRIPTA_CONTENT=$(cat "$SCRIPTA_FILE")
else
    # Assume it's a file for backward compatibility
    SCRIPTA_FILE="$1"

    if [ ! -f "$SCRIPTA_FILE" ]; then
        echo "Error: File '$SCRIPTA_FILE' not found"
        exit 1
    fi

    USE_FILE=true
    SCRIPTA_FILE="$(cd "$(dirname "$SCRIPTA_FILE")" && pwd)/$(basename "$SCRIPTA_FILE")"
    SCRIPTA_CONTENT=$(cat "$SCRIPTA_FILE")
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Project directory where the Elm source is located
PROJECT_DIR="/Users/carlson/dev/elm-work/scripta/scripta-live"

# Output files
OUTPUT_DIR="$PROJECT_DIR/.vs-tmp"
OUTPUT_HTML="$OUTPUT_DIR/view.html"
OUTPUT_JS="$OUTPUT_DIR/view.js"

# Create temp directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Compile the Elm viewer
echo "Compiling Scripta viewer..."
cd "$PROJECT_DIR"
elm make src/ViewScripta.elm --output="$OUTPUT_JS" --optimize 2>/dev/null

if [ $? -ne 0 ]; then
    echo "Error: Failed to compile Elm viewer"
    exit 1
fi

# Create HTML file with the content
cat > "$OUTPUT_HTML" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scripta Viewer</title>

    <!-- KaTeX for math rendering -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.12.0/dist/katex.min.css" integrity="sha384-AfEj0r4/OFrOo5t7NnNe46zW/tFgW6x/bCJG8FqQCEo3+Aro6EYUG4+cU+KJWu/X" crossorigin="anonymous">
    <script src="https://cdn.jsdelivr.net/npm/katex@0.12.0/dist/katex.min.js" integrity="sha384-g7c+Jr9ZivxKLnZTDUhnkOnsh30B4H0rpLUpJ4jAIKs4fnJI+sEnkvrMWph2EDg4" crossorigin="anonymous"></script>

    <style>
        body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
        }
    </style>
</head>
<body>
    <div id="app"></div>

    <script src="view.js"></script>
    <script>
        // Initialize Elm app
        const app = Elm.ViewScripta.init({
            node: document.getElementById('app'),
            flags: {}
        });

        // Send file content to Elm
        const content = SCRIPTA_CONTENT_PLACEHOLDER;
        setTimeout(() => {
            app.ports.getFileContent.send(content);
        }, 100);

        // Handle KaTeX rendering for custom elements
        function renderKatex() {
            document.querySelectorAll('katex-display, katex-inline').forEach(el => {
                const tex = el.textContent;
                const displayMode = el.tagName.toLowerCase() === 'katex-display';
                try {
                    katex.render(tex, el, {
                        displayMode: displayMode,
                        throwOnError: false
                    });
                } catch (e) {
                    console.error('KaTeX error:', e);
                }
            });
        }

        // Render KaTeX after Elm renders
        setTimeout(renderKatex, 200);

        // Re-render on any DOM changes (for dynamic content)
        const observer = new MutationObserver(renderKatex);
        observer.observe(document.getElementById('app'), {
            childList: true,
            subtree: true
        });
    </script>
</body>
</html>
EOF

# Escape the content for JavaScript and inject it
# Save content to temp file for node to read
TEMP_CONTENT="$OUTPUT_DIR/content.tmp"
echo "$SCRIPTA_CONTENT" > "$TEMP_CONTENT"

# Use node to do the replacement safely
node -e "
const fs = require('fs');
const content = fs.readFileSync('$TEMP_CONTENT', 'utf8');
const html = fs.readFileSync('$OUTPUT_HTML', 'utf8');
const newHtml = html.replace('SCRIPTA_CONTENT_PLACEHOLDER', JSON.stringify(content));
fs.writeFileSync('$OUTPUT_HTML', newHtml);
"

# Clean up temp file
rm "$TEMP_CONTENT"

# Open in browser
echo "Opening in browser..."
if command -v open &> /dev/null; then
    # macOS
    open "$OUTPUT_HTML"
elif command -v xdg-open &> /dev/null; then
    # Linux
    xdg-open "$OUTPUT_HTML"
elif command -v start &> /dev/null; then
    # Windows
    start "$OUTPUT_HTML"
else
    echo "Could not detect how to open browser. Please open this file manually:"
    echo "$OUTPUT_HTML"
fi

echo "Done! Rendered file: $OUTPUT_HTML"
