// Editor <-> rendered-text sync, adapted from scripta-compiler-v3/Demo/index.html.
//
// Call setupEditorSync(app) after Elm.<Main>.init(...). It wires:
//   - Elm ports scrollToElement (TOC, footnote, citation clicks) and
//     selectInEditor (PDF error lines) when the program uses them
//   - selecting text in the rendered output -> highlight it in the editor
//   - Ctrl+S on an editor selection -> highlight the matching rendered element
//   - ESC -> clear highlights and restore the rendered-text scroll position
//
// Rendered elements carry ids "e-<line>.<token>" and data-begin/data-end
// (character offsets within their block), emitted by the v3 compiler.
// The line in the id is 0-based; CodeMirror lines are 1-based.

(function () {
  const RENDERED_ID = 'rendered-text-container';
  const HIGHLIGHT = 'rendered-sync-highlight';

  const style = document.createElement('style');
  style.textContent =
    '.' + HIGHLIGHT + ' { background-color: rgba(0, 255, 255, 0.5) !important; outline: 2px solid cyan; }';
  document.head.appendChild(style);

  function renderedOutput() {
    return document.getElementById(RENDERED_ID);
  }

  function editorElement() {
    const el = document.querySelector('codemirror-editor');
    return el && el.editor ? el : null;
  }

  function clearRenderedHighlights() {
    document.querySelectorAll('.' + HIGHLIGHT).forEach(function (el) {
      el.classList.remove(HIGHLIGHT);
    });
  }

  // Editor (1-based) line of a rendered element; ids use 0-based lines.
  function lineOfId(id) {
    if (!id || !id.startsWith('e-')) return null;
    const line = parseInt(id.substring(2).split('.')[0], 10);
    return isNaN(line) ? null : line + 1;
  }

  // Highlight [from, to) in the editor and scroll it to the centre.
  function highlightInEditor(editorEl, from, to) {
    if (editorEl.setSyncHighlight) {
      editorEl.editor.dispatch({
        effects: [editorEl.setSyncHighlight({ from: from, to: to }), editorEl.scrollToCenter(from)]
      });
    }
    editorEl.editor.focus();
  }

  // Absolute document position of a character offset counted from the start
  // of line lineNum, continuing across following lines (multi-line paragraphs).
  function absolutePosition(doc, lineNum, charOffset) {
    let pos = doc.line(lineNum).from;
    let remaining = charOffset;
    let currentLine = lineNum;
    while (remaining > 0 && currentLine <= doc.lines) {
      const lineLength = doc.line(currentLine).length;
      if (remaining <= lineLength) return pos + remaining;
      remaining -= lineLength + 1; // +1 for the newline
      currentLine++;
      if (currentLine <= doc.lines) pos = doc.line(currentLine).from;
    }
    return pos + Math.max(0, remaining);
  }

  let savedScrollState = null;

  window.setupEditorSync = function (app) {
    if (app.ports.scrollToElement) {
      app.ports.scrollToElement.subscribe(function (elementId) {
        const output = renderedOutput();
        if (output) savedScrollState = { scrollTop: output.scrollTop, elementId: elementId };
        setTimeout(function () {
          const element = document.getElementById(elementId);
          if (element) {
            clearRenderedHighlights();
            element.scrollIntoView({ behavior: 'smooth', block: 'center' });
            element.classList.add(HIGHLIGHT);
          }
        }, 50);
      });
    }

    if (app.ports.selectInEditor) {
      // selection = { lineNumber, begin, end, numberOfLines }
      app.ports.selectInEditor.subscribe(function (selection) {
        const editorEl = editorElement();
        if (!editorEl) return;
        const doc = editorEl.editor.state.doc;
        if (selection.lineNumber < 1 || selection.lineNumber > doc.lines) return;
        const lineStart = doc.line(selection.lineNumber).from;
        let from, to;
        if (selection.numberOfLines > 0) {
          from = lineStart;
          const endLine = Math.min(selection.lineNumber + selection.numberOfLines - 1, doc.lines);
          to = doc.line(endLine).to;
        } else {
          from = lineStart + selection.begin;
          to = lineStart + selection.end + 1;
        }
        highlightInEditor(editorEl, from, to);
      });
    }
  };

  // ESC: clear highlights and return to the previous rendered-text position.
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    clearRenderedHighlights();
    if (savedScrollState) {
      const output = renderedOutput();
      if (output) output.scrollTo({ top: savedScrollState.scrollTop, behavior: 'smooth' });
      savedScrollState = null;
    }
  });

  // Selecting text in the rendered output highlights the source in the editor.
  document.addEventListener('mouseup', function (e) {
    const output = renderedOutput();
    if (!output || !output.contains(e.target)) return;

    const selection = window.getSelection();
    if (!selection || selection.isCollapsed || selection.rangeCount === 0) return;
    const range = selection.getRangeAt(0);

    function positionElement(node) {
      let el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
      while (el && el !== output) {
        if (el.hasAttribute && el.hasAttribute('data-begin') && lineOfId(el.id) !== null) return el;
        el = el.parentElement;
      }
      return null;
    }

    const startEl = positionElement(range.startContainer);
    const endEl = positionElement(range.endContainer);
    if (!startEl || !endEl) return;

    const startBegin = parseInt(startEl.getAttribute('data-begin'), 10);
    const endBegin = parseInt(endEl.getAttribute('data-begin'), 10);
    if (isNaN(startBegin) || isNaN(endBegin)) return;

    const editorEl = editorElement();
    if (!editorEl) return;
    const doc = editorEl.editor.state.doc;
    const startLine = lineOfId(startEl.id);
    const endLine = lineOfId(endEl.id);
    if (startLine > doc.lines || endLine > doc.lines) return;

    const from = absolutePosition(doc, startLine, startBegin + range.startOffset);
    const to = absolutePosition(doc, endLine, endBegin + range.endOffset);
    highlightInEditor(editorEl, from, to);
  });

  // Ctrl+S in the editor (emitted by codemirror-element.js): highlight the
  // rendered element whose source line is closest at or before the selection.
  document.addEventListener('sync-to-rendered', function (e) {
    const lineNumber = e.detail.lineNumber;
    clearRenderedHighlights();
    const output = renderedOutput();
    if (!output) return;

    let bestMatch = null;
    let bestDistance = Infinity;
    output.querySelectorAll('[data-begin]').forEach(function (el) {
      const line = lineOfId(el.id);
      if (line === null || line > lineNumber) return;
      if (lineNumber - line < bestDistance) {
        bestDistance = lineNumber - line;
        bestMatch = el;
      }
    });

    if (bestMatch) {
      savedScrollState = { scrollTop: output.scrollTop, elementId: bestMatch.id };
      bestMatch.classList.add(HIGHLIGHT);
      bestMatch.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  });
})();
