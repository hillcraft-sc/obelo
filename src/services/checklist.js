// Checklists ("- [ ] item") in note Markdown. Used by the note renderer and by ticking items on the
// note page (issue #2). The browser loads this same file as /js/checklist.js (window.ObeloChecklist)
// for the editor's Preview, so both sides count checklist items the same way.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.ObeloChecklist = factory();
}(typeof self !== 'undefined' ? self : this, function () {

const FENCE = /^\s*(```|~~~)/;
// A task item: optional quote markers, a bullet or number, then [ ] or [x] followed by a space.
// Same shape marked turns into a checkbox (a "[ ]" with no space after it stays text).
const TASK = /^((?:[ \t]*>)*[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+)\[([ xX])\](?=[ \t]|$)/;
const LIST_ITEM = /^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+/;

// Leading whitespace width, a tab counting as 4 (as Markdown does)
function indentWidth(line) {
  let w = 0;
  for (const ch of line) {
    if (ch === ' ') w += 1;
    else if (ch === '\t') w += 4 - (w % 4);
    else break;
  }
  return w;
}

// Removes `width` columns of leading whitespace
function dedent(line, width) {
  let w = 0, i = 0;
  while (i < line.length && w < width && (line[i] === ' ' || line[i] === '\t')) {
    w += line[i] === '\t' ? 4 - (w % 4) : 1;
    i += 1;
  }
  return line.slice(i);
}

// A checklist indented with spaces or a tab, but not nested under a list item, is a code block to
// Markdown, so it showed as code. Moves such a checklist to the left edge, keeping its own nesting.
// Indented checklists under a list item, and real code blocks, are left alone.
function normalize(src) {
  const lines = String(src || '').replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  let inFence = false;
  let prevList = false;      // the last non-blank line was a list item
  let prevIndented = false;  // the last non-blank line was indented
  let run = null;            // indent being removed from the current checklist
  for (const line of lines) {
    if (FENCE.test(line)) { inFence = !inFence; run = null; out.push(line); prevList = false; continue; }
    if (inFence) { out.push(line); continue; }
    const blank = line.trim() === '';
    if (run !== null) {
      if (blank) { out.push(line); continue; }
      if (indentWidth(line) >= run) { out.push(dedent(line, run)); prevList = LIST_ITEM.test(line); continue; }
      run = null;
    }
    if (blank) { out.push(line); continue; }
    const width = indentWidth(line);
    if (width > 0 && TASK.test(line) && !prevList && !prevIndented) {
      run = width;
      out.push(dedent(line, width));
      prevList = true;
      prevIndented = false;
      continue;
    }
    out.push(line);
    prevList = LIST_ITEM.test(line);
    prevIndented = width >= 4;
  }
  return out.join('\n');
}

// Letters and digits only, lower case, for comparing an item's source with its rendered text
const plain = (s) => String(s || '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '').slice(0, 24);

// Line numbers of the checklist items Markdown shows as checkboxes, in page order: not inside a
// fence, and not in an indented code block (normalize keeps one line per line, so they line up)
function taskLines(src) {
  const lines = normalize(src).split('\n');
  const found = [];
  let inFence = false, inList = false;
  lines.forEach((line, i) => {
    if (FENCE.test(line)) { inFence = !inFence; inList = false; return; }
    if (inFence || line.trim() === '') return;
    const width = indentWidth(line);
    if (width >= 4 && !inList) return; // indented code
    if (LIST_ITEM.test(line)) inList = true;
    else if (width === 0) inList = false;
    if (TASK.test(line)) found.push(i);
  });
  return found;
}

// Ticks (checked true) or unticks the index-th checklist item, counted in page order. `text` is the
// item's text as the page shows it; when given, it must match, so a note changed elsewhere since
// the page loaded is not ticked in the wrong place. Returns the new Markdown, or null.
function toggle(src, index, checked, text) {
  const lines = String(src || '').replace(/\r\n?/g, '\n').split('\n');
  const i = taskLines(src)[index];
  if (i === undefined) return null;
  const m = lines[i].match(TASK);
  if (!m) return null;
  if (text != null) {
    const a = plain(lines[i].slice(m[0].length)), b = plain(text);
    if (!(a.startsWith(b) || b.startsWith(a))) return null;
  }
  lines[i] = m[1] + (checked ? '[x]' : '[ ]') + lines[i].slice(m[0].length);
  return lines.join('\n');
}

return { normalize, toggle };
}));
