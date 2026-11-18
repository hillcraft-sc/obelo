const crypto = require('crypto');
const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const bcrypt = require('bcryptjs');
const { marked } = require('marked');
const checklist = require('../services/checklist');
const xss = require('xss');
const { rateLimit } = require('express-rate-limit');
const prisma = require('../lib/prisma');
const { encrypt: encryptNote, decrypt: decryptNote } = require('../lib/noteLock');
const { requireAuth } = require('../middleware/auth');
const { getAllUserTags, parseTags: parseTagsShared } = require('../lib/tags');
const uploads = require('../lib/uploads');
const { folderPaths, buildFolderTree, ownFolderId, deleteFolderKeepContents } = require('../services/folders');
const userTemplates = require('../lib/userTemplates');

const router = express.Router();
router.use(requireAuth);

// The person's note templates for every notes page (lib/userTemplates.js), titled in their timezone
router.use((req, res, next) => {
  res.locals.noteTemplates = userTemplates.forUser(req.user)
    .map((t) => ({ key: t.id, label: t.label, type: t.type, title: t.startTitle, content: t.content }));
  next();
});

const pinLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many attempts — please try again later.',
  skip: () => process.env.NODE_ENV === 'development',
});

// Actions from the notes workspace post ws=1 and return to it. 
const isWs = (req) => req.body?.ws === '1';
const wsUrl = (id) => `/notes/workspace?id=${id}`;

// Markdown options
marked.use({ gfm: true, breaks: true });
// Everything marked produces must survive: <ins> (the underline button), task-list checkboxes
// (<input type="checkbox">, disabled), and the usual block tags, which the default list has.
// Other inputs are dropped.
const _xssOptions = {
  whiteList: { ...xss.getDefaultWhiteList(), ins: [], input: ['type', 'checked', 'disabled'] },
  onTag(tag, html) {
    if (tag === 'input' && !/\btype="checkbox"/.test(html)) return '';
  },
};
// Indented checklists render as checklists, not code (issue #2)
const renderMd = (src) => xss(marked(checklist.normalize(src)), _xssOptions);

// File uploads

// Held in memory so lib/uploads can encrypt before anything touches disk
const ALLOWED_MIMES = new Set(['application/pdf', 'text/plain']);
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024 },
  fileFilter: (req, file, cb) =>
    cb(null, file.mimetype.startsWith('image/') || ALLOWED_MIMES.has(file.mimetype)),
});

// ── Helpers ────────────────────────────────────────────────────────────────

const parseTags = parseTagsShared;

async function findNoteForUser(id, userId) {
  return prisma.note.findFirst({
    where: { id: Number(id), userId },
    include: {
      attachments: { orderBy: { createdAt: 'asc' } },
      thoughts: {
        orderBy: { createdAt: 'asc' },
        include: { user: { select: { id: true, displayName: true } } },
      },
    },
  });
}

const getUserTags = getAllUserTags;

function escHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function pinBtn(noteId, pinned) {
  const cls = pinned
    ? 'bg-amber-950 text-amber-400 border-amber-800'
    : 'bg-gray-800 text-gray-400 hover:text-gray-200 border-gray-700';
  return `<button hx-post="/notes/${noteId}/pin" hx-swap="outerHTML"
    class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors ${cls}">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="${pinned ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="1.5" class="w-4 h-4">
      <path stroke-linecap="round" stroke-linejoin="round" d="M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.47 1.073-2.756 2.57-2.93a48.507 48.507 0 0111.186 0z"/>
    </svg>
    ${pinned ? 'Pinned' : 'Pin'}
  </button>`;
}

function flagBtn(noteId, flagged) {
  const cls = flagged
    ? 'bg-red-950 text-red-400 border-red-800'
    : 'bg-gray-800 text-gray-400 hover:text-gray-200 border-gray-700';
  return `<button hx-post="/notes/${noteId}/flag" hx-swap="outerHTML"
    class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors ${cls}">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="${flagged ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="1.5" class="w-4 h-4">
      <path stroke-linecap="round" stroke-linejoin="round" d="M3 3v1.5M3 21v-6m0 0l2.77-.693a9 9 0 016.208.682l.108.054a9 9 0 006.086.71l3.114-.732a48.524 48.524 0 01-.005-10.499l-3.11.732a9 9 0 01-6.085-.711l-.108-.054a9 9 0 00-6.208-.682L3 4.5M3 15V4.5"/>
    </svg>
    ${flagged ? 'Flagged' : 'Flag for review'}
  </button>`;
}

function thoughtItem(thought) {
  const initial = escHtml(thought.user.displayName.charAt(0).toUpperCase());
  const name = escHtml(thought.user.displayName);
  const content = escHtml(thought.content);
  const date = new Date(thought.createdAt).toLocaleDateString('en-US', {
    month: 'short', day: 'numeric',
  });
  return `<div class="thought-item flex gap-3 py-3 border-b border-gray-800 last:border-0 group">
    <div class="w-7 h-7 rounded-full bg-indigo-900 flex items-center justify-center shrink-0 text-xs font-semibold text-indigo-300">${initial}</div>
    <div class="flex-1 min-w-0">
      <div class="flex items-baseline gap-2 mb-1">
        <span class="text-sm font-medium text-gray-300">${name}</span>
        <span class="text-xs text-gray-600">${date}</span>
      </div>
      <p class="text-sm text-gray-400 leading-relaxed whitespace-pre-wrap">${content}</p>
    </div>
    <button hx-delete="/notes/${thought.noteId}/thoughts/${thought.id}"
            hx-swap="outerHTML" hx-target="closest .thought-item"
            class="opacity-0 group-hover:opacity-100 text-gray-600 hover:text-red-400 transition-all shrink-0 self-start pt-0.5">
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/>
      </svg>
    </button>
  </div>`;
}

// Stores an uploaded file (encrypted at rest when configured) and records it on the note.
// Shared with the app API.
async function saveAttachment(noteId, file) {
  const ext = uploads.safeExt(file.originalname);
  const filename = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}${ext}`;
  await uploads.writeFile(uploads.notePath(noteId, filename), file.buffer);
  return prisma.noteAttachment.create({ data: { noteId, filePath: filename, mimeType: file.mimetype } });
}

async function removeAttachment(noteId, attachmentId) {
  const attachment = await prisma.noteAttachment.findFirst({ where: { id: attachmentId, noteId } });
  if (!attachment) return false;
  await uploads.remove(uploads.notePath(noteId, attachment.filePath));
  await prisma.noteAttachment.delete({ where: { id: attachment.id } });
  return true;
}

const SLIPPING_DAYS = 30;

function noteSlipCutoff() {
  const now = new Date();
  return new Date(now.getTime() - SLIPPING_DAYS * 24 * 60 * 60 * 1000);
}

// ── Routes ─────────────────────────────────────────────────────────────────

// GET /notes — the workspace is the only notes screen. Old filter links carry over.
router.get('/', (req, res) => {
  const { type, tag, search } = req.query;
  const params = new URLSearchParams();
  if (WS_FILTERS.includes(type)) params.set('filter', type);
  if (typeof tag === 'string' && tag) params.set('tag', tag);
  if (typeof search === 'string' && search) params.set('search', search);
  const q = params.toString();
  res.redirect('/notes/workspace' + (q ? `?${q}` : ''));
});

// GET /notes/new — old link to the blank form; the workspace's New note button replaces it
router.get('/new', (req, res) => res.redirect('/notes/workspace'));

// GET /notes/tags.json — tag autocomplete
router.get('/tags.json', async (req, res, next) => {
  try {
    const tags = await getUserTags(req.user.id);
    res.json(tags);
  } catch (err) {
    next(err);
  }
});

// POST /notes/bulk — bulk actions
router.post('/bulk', async (req, res, next) => {
  try {
    const { action, ids: rawIds } = req.body;
    const ids = (Array.isArray(rawIds) ? rawIds : [rawIds]).map(Number).filter(Boolean);
    if (ids.length && action) {
      if (action === 'delete') {
        const owned = await prisma.note.findMany({ where: { id: { in: ids }, userId: req.user.id }, select: { id: true } });
        for (const n of owned) await uploads.remove(uploads.noteDir(n.id));
        await prisma.note.deleteMany({ where: { id: { in: owned.map(n => n.id) } } });
      } else if (action === 'pin') {
        await prisma.note.updateMany({ where: { id: { in: ids }, userId: req.user.id }, data: { pinned: true } });
      } else if (action === 'unpin') {
        await prisma.note.updateMany({ where: { id: { in: ids }, userId: req.user.id }, data: { pinned: false } });
      } else if (action === 'flag') {
        await prisma.note.updateMany({ where: { id: { in: ids }, userId: req.user.id }, data: { flaggedForReview: true } });
      } else if (action === 'unflag') {
        await prisma.note.updateMany({ where: { id: { in: ids }, userId: req.user.id }, data: { flaggedForReview: false } });
      } else if (action === 'add-tags' || action === 'remove-tags') {
        const tagInput = (req.body.tags || '').split(',').map(t => t.trim().toLowerCase()).filter(Boolean);
        if (tagInput.length) {
          const notes = await prisma.note.findMany({ where: { id: { in: ids }, userId: req.user.id }, select: { id: true, tags: true } });
          for (const note of notes) {
            const updated = action === 'add-tags'
              ? [...new Set([...note.tags, ...tagInput])]
              : note.tags.filter(t => !tagInput.includes(t));
            await prisma.note.update({ where: { id: note.id }, data: { tags: updated } });
          }
        }
      }
    }
    res.redirect('/notes/workspace');
  } catch (err) { next(err); }
});

// ── Notes workspace ──────────────────────────────────────────────────────────
// A flat list beside the open note. An unlocked note opens straight into editing; a locked note
// asks for the PIN first. Autosave uses the existing POST /notes/:id route.

const WS_TYPES = ['note', 'journal', 'quote'];
const WS_FILTERS = ['flagged', 'slipping', ...WS_TYPES];

async function loadWorkspace(req, { search, tag, id, filter }) {
  if (!WS_FILTERS.includes(filter)) filter = '';
  const slipCut = noteSlipCutoff();
  const where = {
    userId: req.user.id,
    ...(tag ? { tags: { has: tag } } : {}),
    ...(filter === 'flagged' ? { flaggedForReview: true } : {}),
    ...(filter === 'slipping' ? { updatedAt: { lt: slipCut } } : {}),
    ...(WS_TYPES.includes(filter) ? { type: filter } : {}),
    ...(search
      ? {
          OR: [
            { title: { contains: search, mode: 'insensitive' } },
            { content: { contains: search, mode: 'insensitive' } },
          ],
        }
      : {}),
  };
  const [list, tagList, folders, flaggedCount, slippingCount] = await Promise.all([
    prisma.note.findMany({
      where,
      orderBy: filter === 'slipping' ? [{ updatedAt: 'asc' }] : [{ pinned: 'desc' }, { updatedAt: 'desc' }],
      select: { id: true, title: true, tags: true, pinned: true, private: true, locked: true, hasDrawing: true, updatedAt: true, folderId: true },
    }),
    getUserTags(req.user.id),
    prisma.folder.findMany({ where: { userId: req.user.id }, orderBy: { name: 'asc' } }),
    prisma.note.count({ where: { userId: req.user.id, flaggedForReview: true } }),
    prisma.note.count({ where: { userId: req.user.id, updatedAt: { lt: slipCut } } }),
  ]);
  // No note is opened unless one is asked for, so the workspace starts on the empty state
  const noteId = Number(id) || null;
  const note = noteId ? await findNoteForUser(noteId, req.user.id) : null;
  // Full folder paths ("Work / Projects") for the folder picker
  folderPaths(folders);
  // The tree is shown when nothing is filtered. A search or tag shows a flat list of matches.
  const filtered = Boolean(search || tag || filter);
  const tree = filtered ? [] : buildFolderTree(folders, list);
  // Pinned notes get their own section at the top of the tree; they also stay in their folder
  const pinned = filtered ? [] : list.filter((n) => n.pinned);
  return { list, tagList, note, folders, tree, filtered, pinned, filter, flaggedCount, slippingCount };
}

// GET /notes/workspace?id=N&search=&tag=
router.get('/workspace', async (req, res, next) => {
  try {
    const { search = '', tag = '', id, filter: rawFilter = '' } = req.query;
    const { list, tagList, note, folders, tree, filtered, pinned, filter, flaggedCount, slippingCount } = await loadWorkspace(req, { search, tag, id, filter: rawFilter });

    let state = 'empty';
    let content = '';
    if (note) {
      if (note.hasDrawing) {
        // Handwritten notes open in the same editor, in Draw mode
        state = 'edit';
      } else if (note.locked) {
        if (req.session.unlockedNotes?.[note.id]) {
          try {
            content = decryptNote(note.lockedContent, req.user.id, note.lockSalt);
            state = 'edit';
          } catch {
            state = 'locked';
          }
        } else {
          state = 'locked';
        }
      } else {
        content = note.content || '';
        state = 'edit';
      }
    }

    const prefs = await prisma.user.findUnique({ where: { id: req.user.id }, select: { preferences: true } });
    const canLock = !!prefs?.preferences?.noteLockPin;

    res.render('notes/workspace', {
      title: 'Notes workspace',
      list, tagList, note, state, content, canLock, folders, tree, filtered, pinned,
      search, tag, filter, flaggedCount, slippingCount,
      lockError: req.query.lockerr ? 'Incorrect PIN.' : null,
      templateMsg: req.query.templateMsg ? String(req.query.templateMsg).slice(0, 200) : null,
    });
  } catch (err) { next(err); }
});

// POST /notes/workspace/new — create an empty note and open it in the workspace
router.post('/workspace/new', async (req, res, next) => {
  try {
    const folderId = await ownFolderId(req.body.folderId, req.user.id);
    if (folderId === undefined) return res.status(400).end();
    // A template (or none) sets the starting type, title and content. One deleted since the page loaded gives a blank note.
    const tpl = req.body.template ? userTemplates.findFor(req.user, String(req.body.template)) : null;
    const note = await prisma.note.create({
      data: {
        userId: req.user.id,
        type: tpl ? tpl.type : 'note',
        title: tpl ? tpl.startTitle : 'Untitled',
        content: tpl ? tpl.content : '',
        tags: [], folderId,
      },
    });
    res.redirect(`/notes/workspace?id=${note.id}`);
  } catch (err) { next(err); }
});

// POST /notes/workspace/:id/save-as-template — keep the open note's type, title and text as a template
router.post('/workspace/:id/save-as-template', async (req, res, next) => {
  try {
    const note = await findNoteForUser(req.params.id, req.user.id);
    if (!note) return res.status(404).end();
    const back = (msg) => res.redirect(`/notes/workspace?id=${note.id}${msg ? '&templateMsg=' + encodeURIComponent(msg) : ''}`);
    if (note.locked) return back("Locked notes can't be saved as templates.");
    if (note.hasDrawing) return back("Handwritten notes can't be saved as templates.");
    const result = await userTemplates.mutate(req.user.id, (prefs) => userTemplates.withCreated(prefs, {
      label: req.body.name, type: note.type, title: note.title || '', content: note.content || '',
    }));
    back(result.error || `Saved the template "${result.template.label}". Find it under + Note.`);
  } catch (err) { next(err); }
});

// POST /notes/workspace/folders — create a folder, optionally inside another
router.post('/workspace/folders', async (req, res, next) => {
  try {
    const name = String(req.body.name || '').trim().slice(0, 80);
    if (!name) return res.redirect(workspaceBack(req));
    const parentId = await ownFolderId(req.body.parentId, req.user.id);
    if (parentId === undefined) return res.status(400).end();
    await prisma.folder.create({ data: { userId: req.user.id, name, parentId } });
    res.redirect(workspaceBack(req));
  } catch (err) { next(err); }
});

// POST /notes/workspace/folders/:id/rename
router.post('/workspace/folders/:id/rename', async (req, res, next) => {
  try {
    const name = String(req.body.name || '').trim().slice(0, 80);
    const folder = await prisma.folder.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!folder) return res.status(404).end();
    if (name) await prisma.folder.update({ where: { id: folder.id }, data: { name } });
    res.redirect(workspaceBack(req));
  } catch (err) { next(err); }
});

// POST /notes/workspace/folders/:id/delete — notes and subfolders move up one level; nothing is deleted
router.post('/workspace/folders/:id/delete', async (req, res, next) => {
  try {
    const folder = await prisma.folder.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!folder) return res.status(404).end();
    await deleteFolderKeepContents(folder, req.user.id);
    res.redirect(workspaceBack(req));
  } catch (err) { next(err); }
});

// POST /notes/workspace/notes/:id/move — folderId '' or missing moves the note to the top level
router.post('/workspace/notes/:id/move', async (req, res, next) => {
  try {
    const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!note) return res.status(404).json({ ok: false });
    const folderId = await ownFolderId(req.body.folderId, req.user.id);
    if (folderId === undefined) return res.status(400).json({ ok: false, error: 'Unknown folder' });
    await prisma.note.update({ where: { id: note.id }, data: { folderId } });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// Where a folder action returns: the workspace, keeping the open note if one was sent
function workspaceBack(req) {
  const id = Number(req.body.returnId);
  return Number.isInteger(id) && id > 0 ? wsUrl(id) : '/notes/workspace';
}

// POST /notes/workspace/preview — live preview, sanitised by the same renderer as the note view
router.post('/workspace/preview', (req, res) => {
  res.type('html').send(renderMd(String(req.body.content || '')));
});

// POST /notes/workspace/:id/relock — sent when the page is left, so the note locks again
router.post('/workspace/:id/relock', (req, res) => {
  const id = Number(req.params.id);
  if (req.session.unlockedNotes) delete req.session.unlockedNotes[id];
  res.sendStatus(204);
});

// POST /notes/workspace/:id/unlock — PIN check, then back to the workspace
router.post('/workspace/:id/unlock', pinLimiter, async (req, res, next) => {
  try {
    const [note, userPrefs] = await Promise.all([
      findNoteForUser(req.params.id, req.user.id),
      prisma.user.findUnique({ where: { id: req.user.id }, select: { preferences: true } }),
    ]);
    if (!note) return res.status(404).render('error', { title: 'Not found', error: { message: 'Note not found.' } });
    const back = `/notes/workspace?id=${note.id}`;
    if (!note.locked) return res.redirect(back);

    const pinHash = userPrefs.preferences?.noteLockPin;
    const valid = pinHash && await bcrypt.compare(req.body.pin || '', pinHash);
    if (!valid) return res.redirect(`${back}&lockerr=1`);
    try {
      decryptNote(note.lockedContent, req.user.id, note.lockSalt);
    } catch {
      return res.redirect(`${back}&lockerr=1`);
    }
    req.session.unlockedNotes = req.session.unlockedNotes || {};
    req.session.unlockedNotes[note.id] = true;
    res.redirect(back);
  } catch (err) { next(err); }
});

// GET /notes/:id and /notes/:id/edit — old links open the note in the workspace.
// Same answer for another user's note as for a missing one: the workspace shows its empty state.
const openInWorkspace = (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id < 1) return res.status(404).render('error', { title: 'Not found', error: { message: 'Note not found.' } });
  res.redirect(wsUrl(id));
};
router.get('/:id', openInWorkspace);
router.get('/:id/edit', openInWorkspace);

// POST /notes/:id — update
router.post('/:id', async (req, res, next) => {
  try {
    const existing = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!existing) return res.status(404).render('error', { title: 'Not found', error: { message: 'Note not found.' } });
    if (existing.locked && !req.session.unlockedNotes?.[existing.id]) return res.redirect(wsUrl(existing.id));

    const { type = 'note', title, content, source, author, tags: tagsRaw,
            pinned, private: priv, flaggedForReview, reviewDate,
            noteMode, drawingData: drawingDataRaw } = req.body;
    const hasDrawing = noteMode === 'draw' && !!drawingDataRaw?.trim();
    const drawingData = hasDrawing ? drawingDataRaw.trim() : null;
    const noteContent = hasDrawing ? null : (content || '');

    const isAutosave = req.headers['x-autosave'] === '1';

    if (!title?.trim()) {
      if (isAutosave) return res.status(422).json({ ok: false, error: 'Title is required.' });
      return res.redirect(wsUrl(existing.id));
    }

    if (existing.locked) {
      // Note remains locked — re-encrypt the edited content under the same salt
      const newLockedContent = encryptNote(noteContent || '', req.user.id, existing.lockSalt);
      await prisma.note.update({
        where: { id: existing.id },
        data: {
          type, title: title.trim(),
          lockedContent: newLockedContent, content: null,
          source: source?.trim() || null, author: author?.trim() || null,
          tags: parseTags(tagsRaw),
          pinned: pinned === 'on', private: priv === 'on',
          flaggedForReview: flaggedForReview === 'on',
          reviewDate: flaggedForReview === 'on' && reviewDate ? new Date(reviewDate) : null,
        },
      });
      if (isAutosave) return res.json({ ok: true });
      return res.redirect(wsUrl(existing.id));
    }

    await prisma.note.update({
      where: { id: existing.id },
      data: {
        type,
        title: title.trim(),
        content: noteContent,
        source: source?.trim() || null,
        author: author?.trim() || null,
        tags: parseTags(tagsRaw),
        pinned: pinned === 'on',
        private: priv === 'on',
        flaggedForReview: flaggedForReview === 'on',
        reviewDate: flaggedForReview === 'on' && reviewDate ? new Date(reviewDate) : null,
        hasDrawing,
        drawingData,
      },
    });

    if (isAutosave) return res.json({ ok: true });
    res.redirect(wsUrl(existing.id));
  } catch (err) {
    next(err);
  }
});

// POST /notes/:id/delete
router.post('/:id/delete', async (req, res, next) => {
  try {
    const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!note) return res.redirect('/notes/workspace');

    await uploads.remove(uploads.noteDir(note.id));

    await prisma.note.delete({ where: { id: note.id } });
    res.redirect('/notes/workspace');
  } catch (err) {
    next(err);
  }
});

// POST /notes/:id/lock — encrypt content with server-derived key, no password needed
router.post('/:id/lock', async (req, res, next) => {
  try {
    const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!note) return res.status(404).render('error', { title: 'Not found', error: { message: 'Note not found.' } });
    if (note.locked) return res.redirect(wsUrl(note.id));

    const salt = crypto.randomBytes(16).toString('hex');
    const lockedContent = encryptNote(note.content || '', req.user.id, salt);

    await prisma.note.update({
      where: { id: note.id },
      data: { locked: true, lockedContent, lockSalt: salt, content: null },
    });

    if (req.session.unlockedNotes) delete req.session.unlockedNotes[note.id];
    res.redirect(wsUrl(note.id));
  } catch (err) { next(err); }
});

// POST /notes/:id/remove-lock — verify PIN, decrypt, and permanently restore plain content
router.post('/:id/remove-lock', pinLimiter, async (req, res, next) => {
  try {
    const [note, userPrefs] = await Promise.all([
      prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } }),
      prisma.user.findUnique({ where: { id: req.user.id }, select: { preferences: true } }),
    ]);
    if (!note) return res.status(404).render('error', { title: 'Not found', error: { message: 'Note not found.' } });
    if (!note.locked) return res.redirect(wsUrl(note.id));

    const pinHash = userPrefs.preferences?.noteLockPin;
    const { pin } = req.body;
    const valid = pinHash && await bcrypt.compare(pin || '', pinHash);
    if (!valid) return res.redirect(`${wsUrl(note.id)}&lockerr=1`);

    let decryptedContent = '';
    try {
      decryptedContent = decryptNote(note.lockedContent, req.user.id, note.lockSalt);
    } catch {
      return res.redirect(wsUrl(note.id));
    }

    await prisma.note.update({
      where: { id: note.id },
      data: { locked: false, lockedContent: null, lockSalt: null, content: decryptedContent },
    });

    if (req.session.unlockedNotes) delete req.session.unlockedNotes[note.id];
    res.redirect(wsUrl(note.id));
  } catch (err) { next(err); }
});

// POST /notes/:id/pin — HTMX toggle
// POST /notes/:id/checklist — tick or untick one checklist item from the note page (issue #2).
// Body: index (the item's place among the page's checkboxes), checked, text (the item as shown).
router.post('/:id/checklist', async (req, res, next) => {
  try {
    const note = await findNoteForUser(req.params.id, req.user.id);
    if (!note) return res.status(404).json({ error: 'Note not found.' });
    if (note.hasDrawing) return res.status(409).json({ error: 'Handwritten notes have no checklist.' });
    if (note.locked && !req.session.unlockedNotes?.[note.id]) return res.status(423).json({ error: 'Unlock this note first.' });
    const content = note.locked ? decryptNote(note.lockedContent, req.user.id, note.lockSalt) : (note.content || '');
    const index = Number.parseInt(req.body.index, 10);
    const checked = req.body.checked === true || req.body.checked === 'true';
    const text = typeof req.body.text === 'string' ? req.body.text : null;
    const updated = Number.isInteger(index) && index >= 0 ? checklist.toggle(content, index, checked, text) : null;
    if (updated === null) return res.status(409).json({ error: 'This checklist changed. Reload the note.' });
    await prisma.note.update({
      where: { id: note.id },
      data: note.locked ? { lockedContent: encryptNote(updated, req.user.id, note.lockSalt) } : { content: updated },
    });
    res.json({ ok: true, checked });
  } catch (err) { next(err); }
});

router.post('/:id/pin', async (req, res, next) => {
  try {
    const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!note) return res.status(404).end();
    const updated = await prisma.note.update({ where: { id: note.id }, data: { pinned: !note.pinned } });
    res.send(pinBtn(note.id, updated.pinned));
  } catch (err) {
    next(err);
  }
});

// POST /notes/:id/flag — HTMX toggle
router.post('/:id/flag', async (req, res, next) => {
  try {
    const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!note) return res.status(404).end();
    const updated = await prisma.note.update({ where: { id: note.id }, data: { flaggedForReview: !note.flaggedForReview } });
    if (req.query.from === 'dashboard') return res.send('');
    if (isWs(req)) return res.redirect(wsUrl(note.id));
    res.send(flagBtn(note.id, updated.flaggedForReview));
  } catch (err) {
    next(err);
  }
});

// POST /notes/:id/thoughts — HTMX add thought
router.post('/:id/thoughts', async (req, res, next) => {
  try {
    const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!note) return res.status(404).end();

    const { content } = req.body;
    if (!content?.trim()) return res.status(400).end();

    const thought = await prisma.noteThought.create({
      data: { noteId: note.id, userId: req.user.id, content: content.trim() },
      include: { user: { select: { id: true, displayName: true } } },
    });

    if (isWs(req)) return res.redirect(wsUrl(note.id));
    res.send(thoughtItem(thought));
  } catch (err) {
    next(err);
  }
});

// POST /notes/:id/thoughts/:tid/delete — workspace form version of the delete below
router.post('/:id/thoughts/:tid/delete', async (req, res, next) => {
  try {
    const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!note) return res.redirect('/notes/workspace');
    await prisma.noteThought.deleteMany({ where: { id: Number(req.params.tid), noteId: note.id, userId: req.user.id } });
    res.redirect(wsUrl(note.id));
  } catch (err) { next(err); }
});

// DELETE /notes/:id/thoughts/:tid — HTMX remove thought
router.delete('/:id/thoughts/:tid', async (req, res, next) => {
  try {
    const thought = await prisma.noteThought.findFirst({
      where: { id: Number(req.params.tid), userId: req.user.id },
    });
    if (thought) await prisma.noteThought.delete({ where: { id: thought.id } });
    res.send('');
  } catch (err) {
    next(err);
  }
});

// POST /notes/:id/attachments — photo upload
router.post('/:id/attachments', (req, res, next) => {
  upload.single('photo')(req, res, async (uploadErr) => {
    if (uploadErr) return next(uploadErr);
    try {
      const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
      if (!note) return res.redirect('/notes/workspace');
      if (req.file) await saveAttachment(note.id, req.file);
      res.redirect(wsUrl(note.id));
    } catch (err) {
      next(err);
    }
  });
});

// GET /notes/:id/attachments/:filename — serve file (auth-gated)
router.get('/:id/attachments/:filename', async (req, res, next) => {
  try {
    const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!note) return res.status(404).end();

    const filename = path.basename(req.params.filename);
    const attachment = await prisma.noteAttachment.findFirst({
      where: { noteId: note.id, filePath: filename },
    });
    if (!attachment) return res.status(404).end();

    const data = await uploads.readFile(uploads.notePath(note.id, filename));
    if (!data) return res.status(404).end();
    uploads.setServeHeaders(res);
    res.type(attachment.mimeType).send(data);
  } catch (err) {
    next(err);
  }
});

// POST /notes/:id/attachments/:aid/delete
router.post('/:id/attachments/:aid/delete', async (req, res, next) => {
  try {
    const note = await prisma.note.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!note) return res.redirect('/notes/workspace');

    await removeAttachment(note.id, Number(req.params.aid));
    res.redirect(wsUrl(note.id));
  } catch (err) {
    next(err);
  }
});

module.exports = { router, noteSlipCutoff, upload, saveAttachment, removeAttachment };
