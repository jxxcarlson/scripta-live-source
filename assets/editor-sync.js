// Editor <-> rendered-text sync, adapted from scripta-compiler-v3/Demo/index.html.
//
// Call setupEditorSync(app) after Elm.<Main>.init(...). It wires:
//   - Elm ports scrollToElement (TOC, footnote, citation clicks) and
//     selectInEditor (PDF error lines) when the program uses them
//   - clicking a word (or math) in the rendered output, or selecting rendered
//     text -> highlight the source in the editor
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

  // data-begin is not always measured from the start of the source line
  // (list items, headings and elements like [i ...] measure from after
  // their prefix), so the computed position is only an estimate. Find the
  // rendered text in the source near the estimate: [from, to) or null.
  const SEARCH_WINDOW = 400;

  function findNear(src, estimate, text, minIndex) {
    const trimmed = text.trim();
    if (!trimmed) return null;
    // Whitespace in rendered text may be a newline or several spaces in the source
    const pattern = trimmed
      .split(/\s+/)
      .map(function (w) { return w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); })
      .join('\\s+');
    const lo = Math.max(minIndex || 0, estimate - SEARCH_WINDOW);
    const hi = Math.min(src.length, estimate + SEARCH_WINDOW + trimmed.length);
    const re = new RegExp(pattern, 'g');
    const region = src.slice(lo, hi);
    let best = null;
    let m;
    while ((m = re.exec(region)) !== null) {
      const from = lo + m.index;
      if (best === null || Math.abs(from - estimate) < Math.abs(best.from - estimate)) {
        best = { from: from, to: from + m[0].length };
      }
      if (m[0].length === 0) re.lastIndex++;
    }
    return best;
  }

  // Source range of rendered text, using the estimate to pick the right
  // occurrence. A selection that crosses markup (e.g. "Hello [b world]")
  // does not occur verbatim, so match its first and last words separately.
  function locateText(src, estimate, text) {
    const exact = findNear(src, estimate, text);
    if (exact) return exact;
    const words = text.trim().split(/\s+/);
    if (words.length < 2) return null;
    const head = findNear(src, estimate, words.slice(0, 2).join(' ')) || findNear(src, estimate, words[0]);
    if (!head) return null;
    const tailText = words.slice(-2).join(' ');
    const tail = findNear(src, head.from + text.length, tailText, head.from) ||
      findNear(src, head.from + text.length, words[words.length - 1], head.from);
    return tail && tail.to > head.from ? { from: head.from, to: tail.to } : head;
  }

  function positionElement(node, output) {
    let el = node && node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
    while (el && el !== output) {
      if (el.hasAttribute && el.hasAttribute('data-begin') && lineOfId(el.id) !== null) return el;
      el = el.parentElement;
    }
    return null;
  }

  // Enclosing block element (display math, images, list items, ...). Its
  // data-begin/data-end are absolute offsets into the source, end inclusive.
  function blockElement(node, output) {
    let el = node && node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
    while (el && el !== output) {
      if (el.hasAttribute && el.hasAttribute('data-lines') && el.hasAttribute('data-begin')) return el;
      el = el.parentElement;
    }
    return null;
  }

  // Estimated source position of offset within node, or null.
  function estimatePosition(doc, node, offset, output) {
    const el = positionElement(node, output);
    if (el) {
      const line = lineOfId(el.id);
      if (line <= doc.lines) {
        return absolutePosition(doc, line, parseInt(el.getAttribute('data-begin'), 10) + offset);
      }
    }
    const block = blockElement(node, output);
    return block ? parseInt(block.getAttribute('data-begin'), 10) : null;
  }

  // The word around offset in a text node: { text, offset } or null.
  function wordAt(node, offset) {
    if (!node || node.nodeType !== Node.TEXT_NODE) return null;
    const s = node.textContent;
    let a = Math.min(offset, s.length);
    let b = a;
    while (a > 0 && /\S/.test(s[a - 1])) a--;
    while (b < s.length && /\S/.test(s[b])) b++;
    const word = s.slice(a, b).replace(/^[^\w\\$]+|[^\w}$]+$/g, '');
    if (!word) return null;
    return { text: word, offset: a + s.slice(a, b).indexOf(word) };
  }

  // Click or selection in the rendered output highlights the source in the editor.
  document.addEventListener('mouseup', function (e) {
    const output = renderedOutput();
    if (!output || !output.contains(e.target)) return;
    const editorEl = editorElement();
    if (!editorEl) return;
    const doc = editorEl.editor.state.doc;
    const src = doc.toString();

    const selection = window.getSelection();
    const hasSelection = selection && !selection.isCollapsed && selection.rangeCount > 0;

    if (hasSelection) {
      const range = selection.getRangeAt(0);
      const estimate = estimatePosition(doc, range.startContainer, range.startOffset, output);
      if (estimate === null) return;
      const found = locateText(src, estimate, selection.toString());
      if (found) highlightInEditor(editorEl, found.from, found.to);
      return;
    }

    // Plain click. Links (footnotes, citations, references) are handled by Elm.
    if (e.target.closest && e.target.closest('a')) return;

    // The word under the pointer, or the whole element (e.g. math)
    let node = null;
    let offset = 0;
    if (document.caretRangeFromPoint) {
      const caret = document.caretRangeFromPoint(e.clientX, e.clientY);
      if (caret) { node = caret.startContainer; offset = caret.startOffset; }
    }
    const target = node && output.contains(node) ? node : e.target;
    const word = wordAt(node, offset);
    if (word) {
      const estimate = estimatePosition(doc, node, word.offset, output);
      const found = estimate === null ? null : findNear(src, estimate, word.text);
      if (found) { highlightInEditor(editorEl, found.from, found.to); return; }
    }
    // No word under the pointer (math, images): highlight the source of the
    // innermost positioned element, an expression (e.g. inline math) or a
    // block (e.g. display math)
    const el = positionElement(target, output);
    const block = blockElement(target, output);
    if (el && (!block || block.contains(el))) {
      const line = lineOfId(el.id);
      const begin = parseInt(el.getAttribute('data-begin'), 10);
      const end = parseInt(el.getAttribute('data-end'), 10);
      if (line <= doc.lines && !isNaN(begin) && !isNaN(end)) {
        highlightInEditor(editorEl, absolutePosition(doc, line, begin), absolutePosition(doc, line, end + 1));
      }
    } else if (block) {
      highlightInEditor(editorEl, parseInt(block.getAttribute('data-begin'), 10), parseInt(block.getAttribute('data-end'), 10));
    }
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
