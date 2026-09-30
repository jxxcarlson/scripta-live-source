// Bundles the v3 Demo editor (scripta-editor.js, copied from
// scripta-compiler-v3/Demo/codemirror-element.js) into a self-contained
// script, so the app does not load CodeMirror from a CDN at runtime.
import {nodeResolve} from "@rollup/plugin-node-resolve"
export default {
  input: "./scripta-editor.js",
  output: {
    file: "../assets/codemirror-element.js",
    format: "iife"
  },
  plugins: [nodeResolve()]
}
