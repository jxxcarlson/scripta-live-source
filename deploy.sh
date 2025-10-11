#!/bin/bash

# Deploy scripta-live to GitHub Pages

set -e  # Exit on any error

SCRIPTA_LIVE_DIR="/Users/carlson/dev/elm-work/scripta/jxxcarlson.github.io/scripta-live"

echo "Copying files to deployment directory..."
cp assets/main.js "$SCRIPTA_LIVE_DIR/"
cp assets/index.html "$SCRIPTA_LIVE_DIR/index-old.html"
cp assets/index-sqlite.html "$SCRIPTA_LIVE_DIR/"
cp assets/katex.js "$SCRIPTA_LIVE_DIR/"
cp assets/codemirror-element.js "$SCRIPTA_LIVE_DIR/"
cp assets/RLSync.js "$SCRIPTA_LIVE_DIR/"
cp assets/main-sqlite.js "$SCRIPTA_LIVE_DIR/"
cp assets/sql-wasm.wasm "$SCRIPTA_LIVE_DIR/"
cp assets/sql-wasm.js "$SCRIPTA_LIVE_DIR/"

echo "Changing to deployment directory..."
cd "$SCRIPTA_LIVE_DIR"

echo "Copying index-sqlite.html to index.html..."
cp index-sqlite.html index.html

echo "Committing changes..."
git add .
git commit -m "update scripta-live"

echo "Pushing to remote..."
git push

echo "Returning to original directory..."
cd -

echo "Deployment complete!"
