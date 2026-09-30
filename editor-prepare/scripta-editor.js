/**
 * CodeMirror 6 custom element for Scripta Demo
 *
 * This provides a <codemirror-editor> custom element that wraps CodeMirror 6
 * with Scripta syntax highlighting and bidirectional communication with Elm.
 *
 * Communication:
 * - Elm -> JS: Set 'load' attribute to load content, 'text' to update content
 * - JS -> Elm: 'text-change' custom event with {position, source}
 */

// Import CodeMirror 6 modules (resolved via import map in index.html)
import { EditorView, lineNumbers, highlightActiveLineGutter, highlightSpecialChars, drawSelection, dropCursor, rectangularSelection, crosshairCursor, highlightActiveLine, keymap, Decoration } from '@codemirror/view';
import { EditorState, StateField, StateEffect } from '@codemirror/state';
import { history, defaultKeymap, historyKeymap, indentWithTab } from '@codemirror/commands';
import { closeBrackets, autocompletion, closeBracketsKeymap, completionKeymap } from '@codemirror/autocomplete';
import { StreamLanguage, syntaxHighlighting, HighlightStyle, indentOnInput, bracketMatching, foldGutter, foldKeymap } from '@codemirror/language';
import { searchKeymap } from '@codemirror/search';

// ============================================================================
// Sync Highlight (persistent highlight from rendered text clicks)
// ============================================================================

// Effect to set/clear the sync highlight
const setSyncHighlight = StateEffect.define();
const clearSyncHighlight = StateEffect.define();

// Decoration mark for sync highlight
const syncHighlightMark = Decoration.mark({ class: 'cm-sync-highlight' });

// State field to track the sync highlight decoration
const syncHighlightField = StateField.define({
    create() {
        return Decoration.none;
    },
    update(decorations, tr) {
        decorations = decorations.map(tr.changes);
        for (let effect of tr.effects) {
            if (effect.is(setSyncHighlight)) {
                const { from, to } = effect.value;
                decorations = Decoration.set([syncHighlightMark.range(from, to)]);
            } else if (effect.is(clearSyncHighlight)) {
                decorations = Decoration.none;
            }
        }
        return decorations;
    },
    provide: f => EditorView.decorations.from(f)
});
import { tags } from '@lezer/highlight';

// ============================================================================
// Theme Colors (matching scripta-app)
// ============================================================================

const scriptaColors = {
    background: '#1e1e1e',
    foreground: '#d4d4d4',
    coral: '#e06c75',        // brackets [ ]
    violet: '#c678dd',       // element names
    malibu: '#61afef',       // block names, headings
    sage: '#98c379',         // arguments, properties
    paleBlue: '#56b6c2',     // math/code content
    deepOrange: '#d19a66',   // backslash and braces in math
    chalky: '#e5c07b',       // | marker
    cursor: '#f89820',
    selection: 'rgba(180, 100, 255, 0.7)',  // bright violet
};

// ============================================================================
// Dark Theme
// ============================================================================

const darkTheme = EditorView.theme({
    '&': {
        backgroundColor: scriptaColors.background,
        color: scriptaColors.foreground,
    },
    '.cm-content': {
        caretColor: scriptaColors.cursor,
        fontFamily: 'monospace',
        fontSize: '14px',
        lineHeight: '1.5',
    },
    '.cm-cursor': {
        borderLeftColor: scriptaColors.cursor,
        borderLeftWidth: '2px',
    },
    '.cm-selectionBackground, &.cm-focused .cm-selectionBackground': {
        backgroundColor: scriptaColors.selection,
    },
    '.cm-gutters': {
        backgroundColor: '#252526',
        color: '#858585',
        border: 'none',
    },
    '.cm-activeLineGutter': {
        backgroundColor: '#2a2a2a',
    },
    '.cm-activeLine': {
        backgroundColor: 'rgba(255, 255, 255, 0.05)',
    },
    '.cm-sync-highlight': {
        backgroundColor: 'rgba(0, 255, 255, 0.5)',  // cyan
    },
    '.cm-scroller': {
        overflow: 'auto',
    },
}, { dark: true });

// ============================================================================
// Scripta Syntax Highlighting
// ============================================================================

const scriptaLanguageDef = {
    name: 'scripta',

    startState: function() {
        return {
            inBlockHeader: false,
            blockHeaderParsed: false,
            bracketDepth: 0,
            inMath: false,
            inCode: false,
            inMathBlock: false,
            pendingMathBlock: false,
            inCodeBlock: false,
            pendingCodeBlock: false,
        };
    },

    copyState: function(state) {
        return { ...state };
    },

    token: function(stream, state) {
        // Start of line - reset block header state and activate pending blocks
        if (stream.sol()) {
            state.inBlockHeader = false;
            state.blockHeaderParsed = false;
            if (state.pendingMathBlock) {
                state.inMathBlock = true;
                state.pendingMathBlock = false;
            }
            if (state.pendingCodeBlock) {
                state.inCodeBlock = true;
                state.pendingCodeBlock = false;
            }
        }

        // Handle math block body (equation, aligned)
        if (state.inMathBlock) {
            if (stream.sol() && (stream.match(/^\s*$/) || stream.peek() === '|')) {
                state.inMathBlock = false;
                if (stream.peek() === '|') {
                    return null;
                }
                stream.skipToEnd();
                return null;
            }
            if (stream.peek() === '\\' || stream.peek() === '{' || stream.peek() === '}') {
                stream.next();
                return 'regexp';
            }
            if (stream.match(/^[^\\{}]+/)) {
                return 'string';
            }
            stream.next();
            return 'string';
        }

        // Handle code block body
        if (state.inCodeBlock) {
            if (stream.sol() && (stream.match(/^\s*$/) || stream.peek() === '|')) {
                state.inCodeBlock = false;
                if (stream.peek() === '|') {
                    return null;
                }
                stream.skipToEnd();
                return null;
            }
            stream.skipToEnd();
            return 'string';
        }

        // Handle inline code `...`
        if (state.inCode) {
            if (stream.eat('`')) {
                state.inCode = false;
                return 'string';
            }
            stream.next();
            return 'string';
        }

        // Handle inline math $...$
        if (state.inMath) {
            if (stream.eat('$')) {
                state.inMath = false;
                return 'string';
            }
            if (stream.peek() === '\\' || stream.peek() === '{' || stream.peek() === '}') {
                stream.next();
                return 'regexp';
            }
            stream.next();
            return 'string';
        }

        // Handle $$ math blocks
        if (stream.sol() && stream.match(/^\$\$/)) {
            state.pendingMathBlock = true;
            return 'keyword';
        }

        // Handle # headings
        if (stream.sol() && stream.match(/^#+\s/)) {
            stream.skipToEnd();
            return 'heading';
        }

        // Handle - bullet lists
        if (stream.sol() && stream.match(/^-\s/)) {
            return 'list';
        }

        // Handle . numbered lists
        if (stream.sol() && stream.match(/^\.\s/)) {
            return 'list';
        }

        // Handle | block headers
        if (stream.sol() && stream.match(/^\|\s*/)) {
            state.inBlockHeader = true;
            state.blockHeaderParsed = false;
            return 'keyword';
        }

        // In block header, parse block name
        if (state.inBlockHeader && !state.blockHeaderParsed) {
            if (stream.match(/^[a-zA-Z_][a-zA-Z0-9_]*/)) {
                state.blockHeaderParsed = true;
                const blockName = stream.current();
                // Check for math/code blocks
                if (['equation', 'aligned', 'math'].includes(blockName)) {
                    state.pendingMathBlock = true;
                }
                if (['code', 'verbatim'].includes(blockName)) {
                    state.pendingCodeBlock = true;
                }
                return 'typeName';
            }
        }

        // In block header, parse arguments and properties
        if (state.inBlockHeader && state.blockHeaderParsed) {
            stream.eatSpace();
            // Property: key:value
            if (stream.match(/^[a-zA-Z_][a-zA-Z0-9_]*:/)) {
                return 'propertyName';
            }
            // Property value or argument
            if (stream.match(/^[^\s\[\]]+/)) {
                return 'attributeName';
            }
        }

        // Handle inline elements [name ...]
        if (stream.eat('[')) {
            state.bracketDepth++;
            return 'bracket';
        }

        if (stream.eat(']')) {
            state.bracketDepth = Math.max(0, state.bracketDepth - 1);
            return 'bracket';
        }

        // Inside brackets, color element name
        if (state.bracketDepth > 0) {
            // First word after [ is the element name
            if (stream.match(/^[a-zA-Z_][a-zA-Z0-9_]*/)) {
                return 'tagName';
            }
            // Rest is content
            if (stream.match(/^[^\[\]]+/)) {
                return null;
            }
        }

        // Handle inline math
        if (stream.eat('$')) {
            state.inMath = true;
            return 'string';
        }

        // Handle inline code
        if (stream.eat('`')) {
            state.inCode = true;
            return 'string';
        }

        // Default: consume and return null
        stream.next();
        return null;
    },
};

const scriptaLanguage = StreamLanguage.define(scriptaLanguageDef);

// Highlight style mapping
const scriptaHighlightStyle = HighlightStyle.define([
    { tag: tags.keyword, color: scriptaColors.chalky },           // | marker
    { tag: tags.typeName, color: scriptaColors.malibu },          // block names
    { tag: tags.tagName, color: scriptaColors.violet },           // element names
    { tag: tags.bracket, color: scriptaColors.coral },            // [ ]
    { tag: tags.attributeName, color: scriptaColors.sage },       // arguments
    { tag: tags.propertyName, color: scriptaColors.sage },        // properties
    { tag: tags.string, color: scriptaColors.paleBlue },          // math/code content
    { tag: tags.regexp, color: scriptaColors.deepOrange },        // \, {, } in math
    { tag: tags.heading, color: scriptaColors.malibu },           // # headings
    { tag: tags.list, color: scriptaColors.coral },               // - . list markers
]);

// ============================================================================
// Helper Functions
// ============================================================================

function sendText(editor) {
    const event = new CustomEvent('text-change', {
        detail: {
            position: editor.state.selection.main.head,
            source: editor.state.doc.toString()
        },
        bubbles: true,
        composed: true
    });
    editor.dom.dispatchEvent(event);
}

function setEditorText(editor, str) {
    try {
        const currentValue = editor.state.doc.toString();

        // Skip update if content is the same (prevents cursor jumping)
        if (currentValue === str) {
            return;
        }

        const endPosition = currentValue.length;

        // Set flag to prevent sending text-change event for this update
        editor.isProgrammaticUpdate = true;

        // Programmatic loads replace the whole document: put the cursor at
        // the top and scroll there. Without this, a load that lands before
        // the editor's first measure leaves it scrolled part-way down.
        editor.dispatch({
            changes: {
                from: 0,
                to: endPosition,
                insert: str
            },
            selection: { anchor: 0 },
            scrollIntoView: true
        });

        // Force CodeMirror to update its view
        editor.requestMeasure();
        editor.dispatch({});
    } catch (error) {
        console.error('Error in setEditorText:', error);
    }
}

// ============================================================================
// Custom Element
// ============================================================================

class CodemirrorEditor extends HTMLElement {
    static get observedAttributes() {
        return ['load', 'text', 'theme'];
    }

    constructor() {
        super();
        this.editor = null;
        this.pendingAttributes = {};
    }

    connectedCallback() {
        console.log('CodeMirror element connected');

        // Set up container styles
        this.style.display = 'block';
        this.style.height = '100%';
        this.style.width = '100%';
        this.style.overflow = 'hidden';

        // Defer editor creation to next tick
        setTimeout(() => {
            try {
                console.log('Creating CodeMirror editor...');

                const panelTheme = EditorView.theme({
                    '&': { height: '100%' },
                    '.cm-scroller': { overflow: 'auto' },
                });

                this.editor = new EditorView({
                    state: EditorState.create({
                        extensions: [
                            // Custom setup (basicSetup minus highlightSelectionMatches)
                            lineNumbers(),
                            highlightActiveLineGutter(),
                            highlightSpecialChars(),
                            history(),
                            foldGutter(),
                            drawSelection(),
                            dropCursor(),
                            EditorState.allowMultipleSelections.of(true),
                            indentOnInput(),
                            bracketMatching(),
                            closeBrackets(),
                            autocompletion(),
                            rectangularSelection(),
                            crosshairCursor(),
                            highlightActiveLine(),
                            // highlightSelectionMatches() - intentionally omitted
                            keymap.of([
                                // ESC clears sync highlight
                                { key: 'Escape', run: (view) => {
                                    view.dispatch({ effects: clearSyncHighlight.of(null) });
                                    // Also clear any highlight in rendered output
                                    document.querySelectorAll('.rendered-sync-highlight').forEach(el => {
                                        el.classList.remove('rendered-sync-highlight');
                                    });
                                    return true;
                                }},
                                // Ctrl+S triggers left-to-right sync (source to rendered)
                                { key: 'Ctrl-s', run: (view) => {
                                    const sel = view.state.selection.main;
                                    if (sel.empty) return false; // No selection

                                    const fromLine = view.state.doc.lineAt(sel.from);
                                    const toLine = view.state.doc.lineAt(sel.to);

                                    // Calculate character offset within the starting line's block
                                    // For multi-line paragraphs, we need to count from the block start
                                    const lineNum = fromLine.number;
                                    const charInLine = sel.from - fromLine.from;

                                    // Dispatch custom event for the app to handle
                                    const event = new CustomEvent('sync-to-rendered', {
                                        detail: {
                                            lineNumber: lineNum,
                                            charOffset: charInLine,
                                            selectionLength: sel.to - sel.from
                                        },
                                        bubbles: true,
                                        composed: true
                                    });
                                    view.dom.dispatchEvent(event);
                                    return true; // Prevent default Ctrl+S behavior
                                }},
                                ...closeBracketsKeymap,
                                ...defaultKeymap,
                                ...searchKeymap,
                                ...historyKeymap,
                                ...foldKeymap,
                                ...completionKeymap,
                                indentWithTab,
                            ]),
                            // Sync highlight field for persistent highlighting
                            syncHighlightField,
                            // Custom extensions
                            darkTheme,
                            panelTheme,
                            EditorView.lineWrapping,
                            scriptaLanguage,
                            syntaxHighlighting(scriptaHighlightStyle),
                            // Send text changes to Elm
                            EditorView.updateListener.of((v) => {
                                if (v.docChanged) {
                                    if (this.editor && this.editor.isProgrammaticUpdate) {
                                        this.editor.isProgrammaticUpdate = false;
                                    } else {
                                        sendText(this.editor);
                                    }
                                }
                            }),
                        ],
                        doc: '',
                    }),
                    parent: this,
                });

                console.log('CodeMirror editor created successfully');

                // Expose sync highlight effect for external use
                this.setSyncHighlight = (range) => setSyncHighlight.of(range);
                this.clearSyncHighlight = () => clearSyncHighlight.of(null);
                // Scroll to center a position in the view
                this.scrollToCenter = (pos) => EditorView.scrollIntoView(pos, { y: 'center' });

                // Dispatch ready event
                this.dispatchEvent(new CustomEvent('editor-ready', {
                    bubbles: true,
                    composed: true,
                    detail: this.editor
                }));

                // Apply any pending attributes
                for (const attr in this.pendingAttributes) {
                    if (this.pendingAttributes[attr] !== undefined) {
                        console.log('Applying pending attribute:', attr);
                        this.handleAttributeChange(attr, null, this.pendingAttributes[attr]);
                    }
                }
                this.pendingAttributes = {};

                // Set up ResizeObserver
                if (window.ResizeObserver) {
                    this.resizeObserver = new ResizeObserver(() => {
                        if (this.editor) {
                            this.editor.requestMeasure();
                        }
                    });
                    this.resizeObserver.observe(this);
                }
            } catch (error) {
                console.error('Error creating CodeMirror editor:', error);
            }
        }, 0);
    }

    disconnectedCallback() {
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
            this.resizeObserver = null;
        }
    }

    attributeChangedCallback(name, oldVal, newVal) {
        console.log('Attribute changed:', name, 'editor exists:', !!this.editor);
        if (!this.editor) {
            // Store for later application
            this.pendingAttributes[name] = newVal;
            return;
        }
        this.handleAttributeChange(name, oldVal, newVal);
    }

    handleAttributeChange(name, oldVal, newVal) {
        switch (name) {
            case 'load':
            case 'text':
                if (typeof newVal === 'string') {
                    console.log('Setting editor text, length:', newVal.length);
                    setEditorText(this.editor, newVal);
                }
                break;
        }
    }
}

// Register the custom element
customElements.define('codemirror-editor', CodemirrorEditor);
console.log('CodeMirror custom element registered');


