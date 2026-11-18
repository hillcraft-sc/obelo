// Shared note editor: Write/Preview, the Markdown toolbar, Text/Draw with the drawing canvas.
// Used by the classic note form (notes/form.ejs) and the notes workspace (notes/workspace.ejs).
// The markup comes from notes/_editor.ejs, so the element ids below must stay the same.

// Preview renders with marked unless a page provides its own (the workspace uses the server's
// sanitised renderer).
async function renderPreviewHtml(md) {
  if (window.renderNotePreview) return window.renderNotePreview(md);
  // Indented checklists render as checklists, not code, as on the server (issue #2)
  const src = window.ObeloChecklist ? window.ObeloChecklist.normalize(md) : md;
  return marked.parse(src || '*Nothing to preview.*');
}

// Ticking a checklist item in the Preview edits the note's text, so the page's autosave or Save
// keeps it (issue #2)
function _wireChecklist(container) {
  if (!window.ObeloChecklist) return;
  container.querySelectorAll('li > input[type="checkbox"]').forEach((box, index) => {
    box.disabled = false;
    box.style.pointerEvents = 'auto';
    box.style.cursor = 'pointer';
    box.addEventListener('change', () => {
      const textarea = document.getElementById('content');
      const updated = window.ObeloChecklist.toggle(textarea.value, index, box.checked);
      if (updated === null) { box.checked = !box.checked; return; }
      textarea.value = updated;
      _notifyChange();
    });
  });
}

// Tell the page its note changed. Both pages autosave on 'input' events from the note form.
function _notifyChange() {
  const form = document.getElementById('content')?.closest('form');
  if (form) form.dispatchEvent(new Event('input', { bubbles: true }));
}

  // Write / Preview toggle
  const writePanel = document.getElementById('write-panel');
  const previewPanel = document.getElementById('preview-panel');
  const previewContent = document.getElementById('preview-content');
  const btnWrite = document.getElementById('btn-write');
  const btnPreview = document.getElementById('btn-preview');

  async function setMode(mode) {
    if (mode === 'preview') {
      const md = document.getElementById('content').value;
      // Only the newest render may fill the panel: an older request can finish later
      const seq = ++_previewSeq;
      const html = await renderPreviewHtml(md);
      if (seq === _previewSeq) { previewContent.innerHTML = html; _wireChecklist(previewContent); }
      writePanel.classList.add('hidden');
      previewPanel.classList.remove('hidden');
      btnPreview.classList.add('bg-gray-700', 'text-gray-200');
      btnPreview.classList.remove('text-gray-500');
      btnWrite.classList.remove('bg-gray-700', 'text-gray-200');
      btnWrite.classList.add('text-gray-500');
    } else {
      writePanel.classList.remove('hidden');
      previewPanel.classList.add('hidden');
      btnWrite.classList.add('bg-gray-700', 'text-gray-200');
      btnWrite.classList.remove('text-gray-500');
      btnPreview.classList.remove('bg-gray-700', 'text-gray-200');
      btnPreview.classList.add('text-gray-500');
    }
  }

  // ── Markdown toolbar ──────────────────────────────────────────────────────
  function fmt(type) {
    const ta = document.getElementById('content');
    const start = ta.selectionStart;
    const end   = ta.selectionEnd;
    const sel   = ta.value.substring(start, end);
    const before = ta.value.substring(0, start);
    const after  = ta.value.substring(end);

    // Helper: wrap selection or insert placeholder
    function wrap(open, close, placeholder) {
      close = close ?? open;
      if (sel) {
        set(before + open + sel + close + after, start, start + open.length + sel.length + close.length);
      } else {
        set(before + open + placeholder + close + after, start + open.length, start + open.length + placeholder.length);
      }
    }

    // Helper: prefix each line in selection
    function prefixLines(prefix) {
      if (sel) {
        const lines = sel.split('\n').map(l => prefix + l).join('\n');
        set(before + lines + after, start, start + lines.length);
      } else {
        const ins = prefix + 'text';
        set(before + ins + after, start + prefix.length, start + ins.length);
      }
    }

    function set(value, selStart, selEnd) {
      const scroll = ta.scrollTop;
      ta.value = value;
      ta.focus();
      ta.setSelectionRange(selStart, selEnd);
      ta.scrollTop = scroll;
    }

    switch (type) {
      case 'bold':      return wrap('**', '**', 'bold text');
      case 'italic':    return wrap('*', '*', 'italic text');
      case 'underline': return wrap('<ins>', '</ins>', 'underlined text');
      case 'strike':    return wrap('~~', '~~', 'strikethrough');
      case 'code':      return wrap('`', '`', 'code');
      case 'h1':        closeHeadingMenu(); return prefixLines('# ');
      case 'h2':        closeHeadingMenu(); return prefixLines('## ');
      case 'h3':        closeHeadingMenu(); return prefixLines('### ');
      case 'ul':        return prefixLines('- ');
      case 'ol':        return prefixLines('1. ');
      case 'checklist': {
        if (sel) {
          const lines = sel.split('\n');
          if (lines.some(l => /^- \[[ x]\] /.test(l))) {
            const toggled = lines.map(l => {
              if (l.startsWith('- [ ] ')) return '- [x] ' + l.slice(6);
              if (l.startsWith('- [x] ')) return '- [ ] ' + l.slice(6);
              return l;
            }).join('\n');
            return set(before + toggled + after, start, start + toggled.length);
          }
        }
        return prefixLines('- [ ] ');
      }
      case 'quote':     return prefixLines('> ');
      case 'hr': {
        const nl = before.endsWith('\n') || before === '' ? '' : '\n';
        const ins = nl + '\n---\n\n';
        set(before + ins + after, start + ins.length, start + ins.length);
        return;
      }
      case 'codeblock': {
        const placeholder = 'code here';
        const ins = '\n```\n' + (sel || placeholder) + '\n```\n';
        set(before + ins + after, start + 5, start + 5 + (sel || placeholder).length);
        return;
      }
      case 'link': {
        const label = sel || 'link text';
        const ins = '[' + label + '](url)';
        const urlStart = start + label.length + 3;
        set(before + ins + after, urlStart, urlStart + 3);
        return;
      }
      case 'table': {
        const nl = (before.endsWith('\n') || before === '') ? '' : '\n';
        const tpl = nl + '\n| Header 1 | Header 2 | Header 3 |\n|----------|----------|----------|\n| Cell     | Cell     | Cell     |\n\n';
        const selStart = start + nl.length + 3; // position of "Header 1"
        set(before + tpl + after, selStart, selStart + 8);
        return;
      }
    }
  }

  // Heading dropdown
  function toggleHeadingMenu() {
    document.getElementById('heading-menu').classList.toggle('hidden');
  }
  function closeHeadingMenu() {
    document.getElementById('heading-menu').classList.add('hidden');
  }
  document.addEventListener('click', e => {
    if (!document.getElementById('heading-menu-wrap').contains(e.target)) closeHeadingMenu();
  });

  // Keyboard shortcuts
  document.getElementById('content')?.addEventListener('keydown', e => {
    if ((e.ctrlKey || e.metaKey) && !e.shiftKey) {
      if (e.key === 'b') { e.preventDefault(); fmt('bold'); }
      if (e.key === 'i') { e.preventDefault(); fmt('italic'); }
      if (e.key === 'k') { e.preventDefault(); fmt('link'); }
    }
  });

  // ── Drawing canvas ────────────────────────────────────────────────────────
  let _canvas, _ctx;
  let _canvasReady = false;
  let _drawing = false;
  let _curStroke = null;
  let _strokes = [];
  let _canvasW = 0;
  let _canvasH = 1200;
  let _penColor = '#f1f5f9';
  let _penWidth = 3;
  let _eraserOn = false;
  let _contentMode = 'text';
  let _rafId = null;

  function setContentMode(mode) {
    _contentMode = mode;
    const isText = mode === 'text';
    const activeC = 'px-2.5 py-1 rounded text-xs font-medium transition-colors bg-gray-700 text-gray-200';
    const idleC   = 'px-2.5 py-1 rounded text-xs font-medium transition-colors text-gray-500 hover:text-gray-300';
    document.getElementById('btn-mode-text').className = isText ? activeC : idleC;
    document.getElementById('btn-mode-draw').className = isText ? idleC   : activeC;
    const wpt = document.getElementById('write-preview-toggle');
    if (wpt) wpt.classList.toggle('hidden', !isText);
    document.getElementById('write-panel').classList.toggle('hidden', !isText);
    document.getElementById('preview-panel').classList.add('hidden');
    document.getElementById('draw-panel').classList.toggle('hidden', isText);
    const hint = document.getElementById('content-hint');
    if (hint) hint.textContent = isText
      ? 'Markdown supported — use toolbar or type syntax directly'
      : 'Use Apple Pencil or finger to draw — handwritten notes are not searchable.';
    document.getElementById('noteModeInput').value = mode;
    if (isText) document.getElementById('drawingDataInput').value = '';
    if (!isText && !_canvasReady) setTimeout(_initCanvas, 60);
  }

  function _initCanvas() {
    _canvas = document.getElementById('draw-canvas');
    if (!_canvas) return;
    _ctx = _canvas.getContext('2d');
    const wrapper = document.getElementById('canvas-wrapper');
    const dpr = window.devicePixelRatio || 1;
    const cssW = wrapper.clientWidth;
    _canvasW = cssW;
    _canvasH = 1200;
    _canvas.style.width  = cssW + 'px';
    _canvas.style.height = _canvasH + 'px';
    _canvas.width  = Math.round(cssW * dpr);
    _canvas.height = Math.round(_canvasH * dpr);
    _ctx.scale(dpr, dpr);
    _canvasReady = true;
    // Load existing strokes when editing a drawing note
    const saved = document.getElementById('drawingDataInput').value;
    if (saved) {
      try {
        const data = JSON.parse(saved);
        if (Array.isArray(data.strokes)) {
          _strokes = data.strokes;
          // Restore canvas height if note was previously expanded
          if (data.h && data.h > _canvasH) {
            _canvasH = data.h;
            _canvas.height = Math.round(_canvasH * dpr);
            _canvas.style.height = _canvasH + 'px';
            _ctx.scale(dpr, dpr);
          }
          _redrawAll(data.w ? cssW / data.w : 1);
        }
      } catch (_) { /* ignore corrupt data */ }
    }
    _canvas.addEventListener('pointerdown', _onDown);
    _canvas.addEventListener('pointermove', _onMove);
    _canvas.addEventListener('pointerup',   _onUp);
    _canvas.addEventListener('pointercancel', _onUp);
    _canvas.addEventListener('contextmenu', e => e.preventDefault());
    // Prevent iOS long-press callout and text selection during drawing
    _canvas.addEventListener('touchstart',  e => e.preventDefault(), { passive: false });
    _canvas.addEventListener('touchmove',   e => e.preventDefault(), { passive: false });
    _canvas.addEventListener('touchend',    e => e.preventDefault(), { passive: false });
  }

  function _pt(e) {
    const r = _canvas.getBoundingClientRect();
    return {
      x: e.clientX - r.left,
      y: e.clientY - r.top,
      p: Math.max(0.1, Math.min(1.0, e.pressure || 0.5)),
    };
  }

  function _onDown(e) {
    e.preventDefault();
    _canvas.setPointerCapture(e.pointerId);
    _drawing = true;
    const pt = _pt(e);
    _curStroke = { color: _penColor, width: _eraserOn ? 20 : _penWidth, eraser: _eraserOn, points: [pt] };
    if (!_rafId) _rafId = requestAnimationFrame(_rafRender);
  }

  function _onMove(e) {
    if (!_drawing || !_curStroke) return;
    e.preventDefault();
    const pt = _pt(e);
    const last = _curStroke.points[_curStroke.points.length - 1];
    const dx = pt.x - last.x, dy = pt.y - last.y;
    if (dx * dx + dy * dy < 4) return; // skip points < 2px apart
    _curStroke.points.push(pt);
    if (!_rafId) _rafId = requestAnimationFrame(_rafRender);
  }

  function _rafRender() {
    _rafId = null;
    // Auto-expand canvas when drawing within 300px of the bottom
    if (_curStroke && _curStroke.points.length > 0) {
      const lastY = _curStroke.points[_curStroke.points.length - 1].y;
      if (lastY > _canvasH - 300) _expandCanvas(800);
    }
    _redrawAll();
    if (_curStroke) _drawStroke(_curStroke, 1);
  }

  function _expandCanvas(addH) {
    const dpr = window.devicePixelRatio || 1;
    _canvasH += addH;
    _canvas.height = Math.round(_canvasH * dpr);
    _canvas.style.height = _canvasH + 'px';
    _ctx.scale(dpr, dpr); // re-apply transform after resize clears it
  }

  function _onUp() {
    if (!_drawing || !_curStroke) return;
    _drawing = false;
    if (_rafId) { cancelAnimationFrame(_rafId); _rafId = null; }
    if (_strokes.length < 500) _strokes.push(_curStroke);
    _curStroke = null;
    _redrawAll();
    _saveData();
    _notifyChange();
  }

  function _drawStroke(stroke, sc = 1) {
    const pts = stroke.points;
    if (!pts || pts.length === 0) return;
    _ctx.save();
    _ctx.globalCompositeOperation = stroke.eraser ? 'destination-out' : 'source-over';
    _ctx.lineCap = 'round';
    _ctx.lineJoin = 'round';
    if (pts.length === 1) {
      _ctx.fillStyle = stroke.eraser ? 'rgba(0,0,0,1)' : window.obeloInk(stroke.color);
      _ctx.beginPath();
      _ctx.arc(pts[0].x * sc, pts[0].y * sc, stroke.width * (pts[0].p || 0.5), 0, Math.PI * 2);
      _ctx.fill();
    } else {
      _ctx.strokeStyle = stroke.eraser ? 'rgba(0,0,0,1)' : window.obeloInk(stroke.color);
      const avgP = pts.reduce((s, p) => s + p.p, 0) / pts.length;
      _ctx.lineWidth = stroke.width * avgP * 2;
      // Quadratic bezier through midpoints — eliminates jagged corners on curves
      _ctx.beginPath();
      _ctx.moveTo(pts[0].x * sc, pts[0].y * sc);
      if (pts.length === 2) {
        _ctx.lineTo(pts[1].x * sc, pts[1].y * sc);
      } else {
        for (let i = 1; i < pts.length - 1; i++) {
          const mx = (pts[i].x + pts[i + 1].x) / 2 * sc;
          const my = (pts[i].y + pts[i + 1].y) / 2 * sc;
          _ctx.quadraticCurveTo(pts[i].x * sc, pts[i].y * sc, mx, my);
        }
        _ctx.lineTo(pts[pts.length - 1].x * sc, pts[pts.length - 1].y * sc);
      }
      _ctx.stroke();
    }
    _ctx.restore();
  }

  function _redrawAll(sc = 1) {
    if (!_ctx || !_canvas) return;
    _ctx.clearRect(0, 0, _canvasW, _canvasH);
    _strokes.forEach(s => _drawStroke(s, sc));
  }

  function undo() {
    if (_strokes.length === 0) return;
    _strokes.pop();
    _redrawAll();
    _saveData();
    _notifyChange();
  }

  function clearCanvas() {
    _strokes = [];
    if (_curStroke) _curStroke = null;
    _redrawAll();
    _saveData();
    _notifyChange();
  }

  function _saveData() {
    const di = document.getElementById('drawingDataInput');
    if (!di) return;
    if (_strokes.length === 0) { di.value = ''; return; }
    di.value = JSON.stringify({
      v: 1, w: _canvasW, h: _canvasH,
      strokes: _strokes.map(s => ({
        color: s.color,
        width: s.width,
        eraser: s.eraser || false,
        points: s.points.map(p => ({ x: Math.round(p.x), y: Math.round(p.y), p: Math.round(p.p * 100) / 100 })),
      })),
    });
  }

  function selectColor(color) {
    _penColor = color;
    _eraserOn = false;
    document.querySelectorAll('.color-btn').forEach(btn => {
      btn.style.outline = btn.dataset.color === color ? '2px solid #6366f1' : 'none';
      btn.style.outlineOffset = '1px';
    });
    _updEraserBtn();
  }

  function selectSize(size) {
    _penWidth = parseFloat(size);
    document.querySelectorAll('.size-btn').forEach(btn => {
      const on = btn.dataset.size == size;
      btn.className = (on ? 'bg-gray-700 text-gray-200 font-medium ' : 'text-gray-400 hover:bg-gray-700 ')
        + 'size-btn px-2 py-1 rounded text-xs transition-colors';
    });
  }

  function toggleEraser() {
    _eraserOn = !_eraserOn;
    _updEraserBtn();
  }

  function _updEraserBtn() {
    const btn = document.getElementById('eraserBtn');
    if (!btn) return;
    btn.className = (_eraserOn ? 'bg-gray-700 text-gray-200 ' : 'text-gray-400 hover:bg-gray-700 ')
      + 'px-2 py-1 rounded text-xs transition-colors flex items-center gap-1';
  }

  // Cmd/Ctrl+Z for undo while in draw mode
  document.addEventListener('keydown', e => {
    if (_contentMode === 'draw' && (e.metaKey || e.ctrlKey) && e.key === 'z') {
      e.preventDefault();
      undo();
    }
  });

  // Before submit: ensure mode and data are correct
  document.getElementById('content')?.closest('form')?.addEventListener('submit', () => {
    document.getElementById('noteModeInput').value = _contentMode;
    if (_contentMode === 'draw' && _canvasReady) _saveData();
    if (_contentMode === 'text') document.getElementById('drawingDataInput').value = '';
  });

// Preview follows typing while the preview is open (debounced)
let _previewTimer = null;
let _previewSeq = 0;
document.getElementById('content')?.addEventListener('input', () => {
  if (!previewPanel || previewPanel.classList.contains('hidden')) return;
  clearTimeout(_previewTimer);
  _previewTimer = setTimeout(() => setMode('preview'), 250);
});

// Author and Source show only for quotes. Used by the classic form and the workspace.
function updateQuoteFields() {
  const type = document.querySelector('input[name="type"]:checked')?.value;
  const el = document.getElementById('quote-fields');
  if (el) el.style.display = type === 'quote' ? 'block' : 'none';
}
document.querySelectorAll('input[name="type"]').forEach((el) => el.addEventListener('change', updateQuoteFields));
updateQuoteFields();

// "Flag for review" shows the review date. Used by the classic form and the workspace.
const flagCheck = document.getElementById('flagCheck');
const reviewDateField = document.getElementById('review-date-field');
function updateReviewDate() {
  if (flagCheck && reviewDateField) reviewDateField.style.display = flagCheck.checked ? 'block' : 'none';
}
flagCheck?.addEventListener('change', updateReviewDate);
updateReviewDate();
