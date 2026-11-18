const express = require('express');
const prisma = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const { getAllUserTags, parseTags } = require('../lib/tags');
const { getShareableUsers } = require('../lib/users');
const { shareBookmarkToUser } = require('../lib/bookmarkShare');

const router = express.Router();
router.use(requireAuth);

// ── Index ──────────────────────────────────────────────────────────────────
router.get('/', async (req, res, next) => {
  try {
    const tag = req.query.tag || null;
    const where = { userId: req.user.id };
    if (tag) where.tags = { has: tag };

    const bookmarks = await prisma.bookmark.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });

    // Collect all unique tags across all user bookmarks for the filter bar
    const allBookmarks = tag
      ? await prisma.bookmark.findMany({ where: { userId: req.user.id }, select: { tags: true } })
      : bookmarks;
    const allTags = [...new Set(allBookmarks.flatMap(b => b.tags))].sort();

    // Full cross-module tag vocabulary for the add/edit tag pickers (matches notes/tasks/reminders/routines)
    const tagList = await getAllUserTags(req.user.id);
    const shareableUsers = await getShareableUsers(req.user.id);

    res.render('bookmarks/index', { title: 'Bookmarks', bookmarks, allTags, tagList, shareableUsers, activeTag: tag, error: req.query.error || null });
  } catch (err) { next(err); }
});

// ── Create ─────────────────────────────────────────────────────────────────
router.post('/', async (req, res, next) => {
  try {
    let url = (req.body.url || '').trim();
    const title = (req.body.title || '').trim() || null;
    const description = (req.body.description || '').trim() || null;
    const tags = parseTags(req.body.tags);

    if (!url) return res.redirect('/bookmarks?error=URL+is+required');
    if (!/^https?:\/\//i.test(url)) url = 'https://' + url;

    await prisma.bookmark.create({ data: { userId: req.user.id, url, title, description, tags } });
    res.redirect('/bookmarks');
  } catch (err) { next(err); }
});

// ── Share to user ──────────────────────────────────────────────────────────
router.post('/:id/share-to-user', async (req, res, next) => {
  try {
    const r = await shareBookmarkToUser(req.user.id, Number(req.params.id), req.body.username);
    res.status(r.status).json(r.body);
  } catch (err) { next(err); }
});

// ── Delete ─────────────────────────────────────────────────────────────────
router.post('/:id/delete', async (req, res, next) => {
  try {
    await prisma.bookmark.deleteMany({ where: { id: Number(req.params.id), userId: req.user.id } });
    res.redirect('/bookmarks');
  } catch (err) { next(err); }
});

// ── Edit ───────────────────────────────────────────────────────────────────
router.post('/:id/edit', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    let url = (req.body.url || '').trim();
    const title = (req.body.title || '').trim() || null;
    const description = (req.body.description || '').trim() || null;
    const tags = parseTags(req.body.tags);

    if (!url) return res.redirect('/bookmarks?error=URL+is+required');
    if (!/^https?:\/\//i.test(url)) url = 'https://' + url;

    await prisma.bookmark.updateMany({ where: { id, userId: req.user.id }, data: { url, title, description, tags } });
    res.redirect('/bookmarks');
  } catch (err) { next(err); }
});

// ── Bulk delete ────────────────────────────────────────────────────────────
router.post('/bulk', async (req, res, next) => {
  try {
    const ids = [req.body.ids || []].flat().map(Number).filter(Boolean);
    if (ids.length) {
      await prisma.bookmark.deleteMany({ where: { id: { in: ids }, userId: req.user.id } });
    }
    res.redirect('/bookmarks');
  } catch (err) { next(err); }
});

module.exports = router;
