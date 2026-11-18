const express = require('express');
const prisma = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const { getShareableUsers } = require('../lib/users');

const router = express.Router();
router.use(requireAuth);

// Returns a list the user can access (owns or has been shared with)
async function findAccessible(listId, userId, includeShares = false) {
  if (!Number.isInteger(listId)) return null;
  return prisma.list.findFirst({
    where: {
      id: listId,
      OR: [{ userId }, { shares: { some: { userId } } }],
    },
    include: includeShares
      ? {
          items: { orderBy: { position: 'asc' } },
          shares: { include: { user: { select: { id: true, username: true, displayName: true } } } },
          user:   { select: { username: true, displayName: true } },
        }
      : undefined,
  });
}

// ── Index ──────────────────────────────────────────────────────────────────
router.get('/', async (req, res, next) => {
  try {
    const userId = req.user.id;
    const ITEMS_INCLUDE = { _count: { select: { items: true } }, items: { where: { checked: false } } };

    const [lists, sharedShares] = await Promise.all([
      prisma.list.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, include: ITEMS_INCLUDE }),
      prisma.listShare.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        include: { list: { include: { ...ITEMS_INCLUDE, user: { select: { username: true, displayName: true } } } } },
      }),
    ]);

    const sharedLists = sharedShares.map(s => s.list);
    res.render('lists/index', { title: 'Lists', lists, sharedLists, error: req.query.error || null });
  } catch (err) { next(err); }
});

// ── Create list ────────────────────────────────────────────────────────────
router.post('/', async (req, res, next) => {
  try {
    const title = (req.body.title || '').trim();
    if (!title) return res.redirect('/lists');
    const list = await prisma.list.create({ data: { userId: req.user.id, title } });
    res.redirect(`/lists/${list.id}`);
  } catch (err) { next(err); }
});

// ── Show list ──────────────────────────────────────────────────────────────
router.get('/:id', async (req, res, next) => {
  try {
    const list = await findAccessible(parseInt(req.params.id), req.user.id, true);
    if (!list) return res.redirect('/lists');
    const active  = list.items.filter(i => !i.checked);
    const done    = list.items.filter(i =>  i.checked);
    const isOwner = list.userId === req.user.id;
    const shareableUsers = await getShareableUsers(req.user.id);
    res.render('lists/show', { title: list.title, list, active, done, isOwner, shareableUsers, error: req.query.error || null });
  } catch (err) { next(err); }
});

// ── Rename list (owner only) ───────────────────────────────────────────────
router.post('/:id/rename', async (req, res, next) => {
  try {
    const title = (req.body.title || '').trim();
    if (!title) return res.status(400).json({ error: 'Title is required.' });
    const { count } = await prisma.list.updateMany({ where: { id: parseInt(req.params.id), userId: req.user.id }, data: { title } });
    if (!count) return res.status(404).json({ error: 'List not found.' });
    res.json({ ok: true, title });
  } catch (err) { next(err); }
});

// ── Delete list (owner only) ───────────────────────────────────────────────
router.post('/:id/delete', async (req, res, next) => {
  try {
    await prisma.list.deleteMany({ where: { id: parseInt(req.params.id), userId: req.user.id } });
    res.redirect('/lists');
  } catch (err) { next(err); }
});

// ── Share list (owner only) ────────────────────────────────────────────────
router.post('/:id/share', async (req, res, next) => {
  try {
    const listId = parseInt(req.params.id);
    const list = await prisma.list.findFirst({ where: { id: listId, userId: req.user.id } });
    if (!list) return res.redirect('/lists');

    const username = (req.body.username || '').trim();
    if (!username) return res.redirect(`/lists/${listId}`);

    const target = await prisma.user.findFirst({ where: { username: { equals: username, mode: 'insensitive' } } });
    if (!target)
      return res.redirect(`/lists/${listId}?error=${encodeURIComponent('User "' + username + '" not found')}`);
    if (target.id === req.user.id)
      return res.redirect(`/lists/${listId}?error=Cannot+share+with+yourself`);

    await prisma.listShare.upsert({
      where:  { listId_userId: { listId, userId: target.id } },
      create: { listId, userId: target.id },
      update: {},
    });
    res.redirect(`/lists/${listId}`);
  } catch (err) { next(err); }
});

// ── Unshare (owner only) ───────────────────────────────────────────────────
router.post('/:id/unshare/:userId', async (req, res, next) => {
  try {
    const listId = parseInt(req.params.id);
    const list = await prisma.list.findFirst({ where: { id: listId, userId: req.user.id } });
    if (!list) return res.redirect('/lists');
    await prisma.listShare.deleteMany({ where: { listId, userId: parseInt(req.params.userId) } });
    res.redirect(`/lists/${listId}`);
  } catch (err) { next(err); }
});

// ── Add item ───────────────────────────────────────────────────────────────
router.post('/:id/items', async (req, res, next) => {
  try {
    const listId = parseInt(req.params.id);
    const text = (req.body.text || '').trim();
    if (!text) return res.redirect(`/lists/${listId}`);

    const list = await findAccessible(listId, req.user.id);
    if (!list) return res.redirect('/lists');

    const count = await prisma.listItem.count({ where: { listId } });
    const item = await prisma.listItem.create({ data: { listId, text, position: count } });
    if (req.headers['x-requested-with'] === 'fetch')
      return res.json({ id: item.id, text: item.text, checked: false });
    res.redirect(`/lists/${listId}`);
  } catch (err) { next(err); }
});

// ── Reorder active items ───────────────────────────────────────────────────
router.post('/:id/items/reorder', async (req, res, next) => {
  try {
    const listId = parseInt(req.params.id);
    const list = await findAccessible(listId, req.user.id);
    if (!list) return res.status(403).json({ error: 'Forbidden' });

    const ids = req.body.ids;
    if (!Array.isArray(ids) || ids.length === 0) return res.status(400).json({ error: 'ids required' });

    await prisma.$transaction(
      ids.map((id, index) =>
        prisma.listItem.updateMany({ where: { id: parseInt(id), listId }, data: { position: index } })
      )
    );
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ── Toggle item ────────────────────────────────────────────────────────────
router.post('/:id/items/:itemId/toggle', async (req, res, next) => {
  try {
    const listId = parseInt(req.params.id);
    const itemId = parseInt(req.params.itemId);
    if (!Number.isInteger(itemId)) return res.status(404).json({ error: 'Not found' });

    const list = await findAccessible(listId, req.user.id);
    if (!list) return res.status(403).json({ error: 'Forbidden' });

    // The item must belong to this list — access to one list grants nothing on another's items
    const item = await prisma.listItem.findFirst({ where: { id: itemId, listId } });
    if (!item) return res.status(404).json({ error: 'Not found' });

    const updated = await prisma.listItem.update({ where: { id: itemId }, data: { checked: !item.checked } });
    res.json({ id: updated.id, checked: updated.checked });
  } catch (err) { next(err); }
});

// ── Edit item ──────────────────────────────────────────────────────────────
router.post('/:id/items/:itemId/edit', async (req, res, next) => {
  try {
    const listId = parseInt(req.params.id);
    const itemId = parseInt(req.params.itemId);
    if (!Number.isInteger(itemId)) return res.status(404).json({ error: 'Not found' });
    const text   = (req.body.text || '').trim();
    if (!text) return res.status(400).json({ error: 'Text required' });

    const list = await findAccessible(listId, req.user.id);
    if (!list) return res.status(403).json({ error: 'Forbidden' });

    const item = await prisma.listItem.findFirst({ where: { id: itemId, listId } });
    if (!item) return res.status(404).json({ error: 'Not found' });

    const updated = await prisma.listItem.update({ where: { id: item.id }, data: { text } });
    if (req.headers['x-requested-with'] === 'fetch') return res.json({ id: updated.id, text: updated.text });
    res.redirect(`/lists/${listId}`);
  } catch (err) { next(err); }
});

// ── Delete item ────────────────────────────────────────────────────────────
router.post('/:id/items/:itemId/delete', async (req, res, next) => {
  try {
    const listId = parseInt(req.params.id);
    const itemId = parseInt(req.params.itemId);
    if (!Number.isInteger(itemId)) return res.status(404).json({ error: 'Not found' });

    const list = await findAccessible(listId, req.user.id);
    if (!list) return res.status(403).json({ error: 'Forbidden' });

    const { count } = await prisma.listItem.deleteMany({ where: { id: itemId, listId } });
    if (!count) return res.status(404).json({ error: 'Not found' });
    if (req.headers['x-requested-with'] === 'fetch') return res.json({ ok: true });
    res.redirect(`/lists/${listId}`);
  } catch (err) { next(err); }
});

module.exports = router;
