const express = require('express');
const prisma = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const capture = require('../services/captureService');
const ai = require('../lib/aiProvider');
const { AiError } = require('../lib/aiProvider');
const { getAllUserTags } = require('../lib/tags');

const router = express.Router();

const TYPE_LABELS = { task: 'Task', reminder: 'Reminder', note: 'Note', journal: 'Journal', quote: 'Quote', list: 'List', bookmark: 'Bookmark' };
const TYPE_ICONS  = { task: '✓', reminder: '🔔', note: '📝', journal: '📖', quote: '💬', list: '📋', bookmark: '🔖' };
const TYPE_ROUTES = { task: '/tasks', reminder: '/reminders', note: '/notes', journal: '/notes', quote: '/notes', list: '/lists', bookmark: '/bookmarks' };

// GET /capture — main capture page (pre-fill q from query string)
router.get('/', requireAuth, (req, res) => {
  res.render('capture/index', {
    title: 'Capture',
    prefill: req.query.q || '',
    draft: null,
    error: null,
    TYPE_LABELS, TYPE_ICONS,
  });
});

// POST /capture — process raw input through the configured AI provider
router.post('/', requireAuth, async (req, res, next) => {
  try {
    const { raw, hint } = req.body;
    if (!raw?.trim()) return res.redirect('/capture');

    // Without AI, Capture keeps what was typed as a plain note
    if (!ai.isConfigured()) {
      const note = await prisma.note.create({
        data: {
          userId: req.user.id,
          type: 'note',
          title: raw.trim().split('\n')[0].slice(0, 80) || 'Untitled',
          content: raw.trim(),
          tags: [],
        },
      });
      return res.redirect(`/notes/${note.id}`);
    }

    // `hint` is the type chosen before processing; "auto" or nothing leaves it to the AI
    const suggestion = await capture.processCapture(raw.trim(), req.user, hint);

    const draft = await prisma.captureDraft.create({
      data: {
        userId:       req.user.id,
        rawInput:     raw.trim(),
        aiSuggestion: suggestion,
        status:       'pending',
      },
    });

    res.render('capture/index', {
      title: 'Capture',
      prefill: '',
      draft: { ...draft, suggestion },
      tagList: await getAllUserTags(req.user.id),
      error: null,
      TYPE_LABELS, TYPE_ICONS,
    });
  } catch (err) {
    res.render('capture/index', {
      title: 'Capture',
      prefill: req.body.raw || '',
      chosenType: req.body.hint,
      draft: null,
      error: err.message,
      TYPE_LABELS, TYPE_ICONS,
    });
  }
});

// POST /capture/:id/confirm — save the draft
router.post('/:id/confirm', requireAuth, async (req, res, next) => {
  try {
    const draftId = parseInt(req.params.id);
    const edits   = buildEdits(req.body);
    const { type, saved } = await capture.confirmCapture(draftId, req.user.id, edits);
    const dest = TYPE_ROUTES[type] || '/';
    const noDetailPage = type === 'bookmark';
    res.redirect(noDetailPage ? `${dest}?captured=1` : `${dest}/${saved.id}?captured=1`);
  } catch (err) { next(err); }
});

// POST /capture/:id/reject — discard draft, go back to capture
router.post('/:id/reject', requireAuth, async (req, res, next) => {
  try {
    await prisma.captureDraft.updateMany({
      where: { id: parseInt(req.params.id), userId: req.user.id },
      data:  { status: 'rejected' },
    });
    res.redirect('/capture');
  } catch (err) { next(err); }
});

// ── API endpoint (for iOS Shortcuts) ─────────────────────────────────────────

router.post('/api', async (req, res, next) => {
  try {
    const token = (req.headers.authorization || '').replace('Bearer ', '').trim();
    if (!token) return res.status(401).json({ error: 'Missing API token' });

    const crypto  = require('crypto');
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const apiToken  = await prisma.apiToken.findFirst({
      where: { tokenHash },
      include: { user: true },
    });
    if (!apiToken) return res.status(401).json({ error: 'Invalid token' });

    await prisma.apiToken.update({
      where: { id: apiToken.id },
      data:  { lastUsed: new Date() },
    });

    const { raw } = req.body;
    if (!raw?.trim()) return res.status(400).json({ error: 'raw input required' });

    const suggestion = await capture.processCapture(raw.trim(), apiToken.user);
    const draft = await prisma.captureDraft.create({
      data: {
        userId:       apiToken.user.id,
        rawInput:     raw.trim(),
        aiSuggestion: suggestion,
        status:       'pending',
      },
    });

    res.json({ draftId: draft.id, suggestion });
  } catch (err) {
    if (err instanceof AiError) return res.status(err.status).json({ error: err.message });
    next(err);
  }
});

function buildEdits(body) {
  const edits = {};
  if (body.type)     edits.type     = body.type;
  if (body.title)    edits.title    = body.title;
  if (body.content !== undefined) edits.content = body.content || null;
  if (body.dueDate)  edits.dueDate  = body.dueDate;
  if (body.dueTime)  edits.dueTime  = body.dueTime;
  if (body.priority) edits.priority = body.priority;
  if (body.tags)     edits.tags     = body.tags.split(',').map(t => t.trim().toLowerCase()).filter(Boolean);
  if (body.source)   edits.source   = body.source;
  if (body.author)   edits.author   = body.author;
  if (body.url !== undefined) edits.url = body.url || null;
  if (body.items !== undefined) {
    edits.items = body.items
      ? body.items.split('\n').map(i => i.trim()).filter(Boolean)
      : [];
  }
  return edits;
}

module.exports = router;
