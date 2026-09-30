# Editor build

`scripta-editor.js` is the CodeMirror 6 editor element (`<codemirror-editor>`) from
`scripta-compiler-v3/Demo/codemirror-element.js`, with one local change: `setEditorText`
puts the cursor at the top when a document is loaded.

Build it into `../assets/codemirror-element.js` (a self-contained bundle, no CDN):

```bash
npm install   # first time only
npm start     # rollup -c rollup.scripta.config.mjs
```

See `../docs/new-editor-code.md` for how the app uses the editor.
