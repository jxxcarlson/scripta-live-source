#!/bin/bash
# Install vs script to ~/bin

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/bin"

echo "Building Scripta viewer..."
cd "$SCRIPT_DIR"

# Compile the Elm app
elm make src/ViewScripta.elm --output=.vs-tmp/view.js --optimize

if [ $? -ne 0 ]; then
    echo "✗ Failed to compile Elm viewer"
    exit 1
fi

echo "✓ Elm viewer compiled successfully"

# Create ~/bin if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Copy the vs script
echo "Installing vs to $INSTALL_DIR/vs..."

# Remove existing file/symlink if it exists
if [ -e "$INSTALL_DIR/vs" ]; then
    rm "$INSTALL_DIR/vs"
fi

cp "$SCRIPT_DIR/vs" "$INSTALL_DIR/vs"
chmod +x "$INSTALL_DIR/vs"

# Update the PROJECT_DIR path in the installed script
sed -i.bak "s|PROJECT_DIR=\".*\"|PROJECT_DIR=\"$SCRIPT_DIR\"|g" "$INSTALL_DIR/vs"
rm "$INSTALL_DIR/vs.bak"

echo "✓ vs installed successfully to $INSTALL_DIR/vs"

# Check if ~/bin is in PATH
if [[ ":$PATH:" == *":$HOME/bin:"* ]]; then
    echo "✓ $HOME/bin is already in your PATH"
else
    echo ""
    echo "⚠️  $HOME/bin is not in your PATH"
    echo "   Add this line to your ~/.zshrc or ~/.bashrc:"
    echo ""
    echo "   export PATH=\"\$HOME/bin:\$PATH\""
    echo ""
    echo "   Then run: source ~/.zshrc"
fi

echo ""
echo "Usage:"
echo "  vs -f FILE.scripta    # Read from file"
echo "  cat file | vs         # Read from stdin"
echo "  vs file.scripta       # Backward compatible"
