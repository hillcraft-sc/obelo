const express = require('express');
const prisma  = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const { prefsHour12 } = require('../lib/timeFormat');

const router = express.Router();

// GET /search?q=... — returns JSON results grouped by type
router.get('/', requireAuth, async (req, res, next) => {
  try {
    const q = (req.query.q || '').trim();
    if (!q || q.length < 2) return res.json({ results: [] });

    const userId = req.user.id;
    const term   = q.toLowerCase();

    const [notes, tasks, reminders, routines, calEvents, lists, bookmarks] = await Promise.all([
      // Notes — title, content, author, source, and tags (tags are stored lowercase)
      prisma.note.findMany({
        where: {
          userId,
          OR: [
            { title:   { contains: q, mode: 'insensitive' } },
            { content: { contains: q, mode: 'insensitive' } },
            { author:  { contains: q, mode: 'insensitive' } },
            { source:  { contains: q, mode: 'insensitive' } },
            { tags:    { has: term } },
          ],
        },
        orderBy: { updatedAt: 'desc' },
        take: 8,
        select: { id: true, title: true, type: true, tags: true, updatedAt: true },
      }),

      // Tasks — active only, title and notes body
      prisma.task.findMany({
        where: {
          userId,
          status: { notIn: ['done', 'archived'] },
          OR: [
            { title: { contains: q, mode: 'insensitive' } },
            { notes: { contains: q, mode: 'insensitive' } },
          ],
        },
        orderBy: { createdAt: 'desc' },
        take: 6,
        select: { id: true, title: true, status: true, priority: true, dueDate: true },
      }),

      // Reminders — incomplete only, title and notes body
      prisma.reminder.findMany({
        where: {
          userId,
          completed: false,
          OR: [
            { title: { contains: q, mode: 'insensitive' } },
            { notes: { contains: q, mode: 'insensitive' } },
          ],
        },
        orderBy: { dueDate: 'asc' },
        take: 5,
        select: { id: true, title: true, dueDate: true },
      }),

      // Routines — active only, title and description
      prisma.routine.findMany({
        where: {
          userId,
          active: true,
          OR: [
            { title:       { contains: q, mode: 'insensitive' } },
            { description: { contains: q, mode: 'insensitive' } },
          ],
        },
        orderBy: { title: 'asc' },
        take: 4,
        select: { id: true, title: true, frequency: true, timeOfDay: true },
      }),

      // Calendar — title, description, location; fetch extra to sort by proximity to now
      prisma.calendarEvent.findMany({
        where: {
          userId,
          OR: [
            { title:       { contains: q, mode: 'insensitive' } },
            { description: { contains: q, mode: 'insensitive' } },
            { location:    { contains: q, mode: 'insensitive' } },
          ],
        },
        take: 12,
        select: { id: true, title: true, startAt: true, allDay: true, location: true },
      }),

      // Lists — owned or shared, title and item text
      prisma.list.findMany({
        where: {
          AND: [
            { OR: [{ userId }, { shares: { some: { userId } } }] },
            { OR: [
                { title: { contains: q, mode: 'insensitive' } },
                { items: { some: { text: { contains: q, mode: 'insensitive' } } } },
              ]
            },
          ],
        },
        orderBy: { createdAt: 'desc' },
        take: 5,
        select: { id: true, title: true, _count: { select: { items: true } } },
      }),

      // Bookmarks — title, URL, description, and tags
      prisma.bookmark.findMany({
        where: {
          userId,
          OR: [
            { title:       { contains: q, mode: 'insensitive' } },
            { url:         { contains: q, mode: 'insensitive' } },
            { description: { contains: q, mode: 'insensitive' } },
            { tags:        { hasSome: [q, term] } },
          ],
        },
        orderBy: { createdAt: 'desc' },
        take: 6,
        select: { id: true, title: true, url: true, tags: true },
      }),
    ]);

    // Sort calendar events: upcoming first (nearest), then most-recent past
    const now = new Date();
    calEvents.sort((a, b) => {
      const aFuture = a.startAt >= now;
      const bFuture = b.startAt >= now;
      if (aFuture !== bFuture) return aFuture ? -1 : 1;
      if (aFuture) return a.startAt - b.startAt;
      return b.startAt - a.startAt;
    });
    const topCalEvents = calEvents.slice(0, 5);

    // Build grouped result list
    const results = [];

    if (notes.length) {
      results.push({ group: 'Notes', items: notes.map(n => ({
        type:     'note',
        id:       n.id,
        title:    n.title,
        subtitle: n.type !== 'note' ? n.type : (n.tags.length ? n.tags.slice(0, 3).join(', ') : null),
        url:      `/notes/${n.id}`,
      })) });
    }

    if (tasks.length) {
      results.push({ group: 'Tasks', items: tasks.map(t => ({
        type:     'task',
        id:       t.id,
        title:    t.title,
        subtitle: t.dueDate ? `due ${t.dueDate.toISOString().split('T')[0]}` : t.status,
        url:      `/tasks/${t.id}`,
      })) });
    }

    if (reminders.length) {
      results.push({ group: 'Reminders', items: reminders.map(r => ({
        type:     'reminder',
        id:       r.id,
        title:    r.title,
        subtitle: r.dueDate ? r.dueDate.toISOString().split('T')[0] : null,
        url:      `/reminders/${r.id}`,
      })) });
    }

    if (routines.length) {
      results.push({ group: 'Routines', items: routines.map(r => ({
        type:     'routine',
        id:       r.id,
        title:    r.title,
        subtitle: `${r.frequency} · ${r.timeOfDay}`,
        url:      `/routines/${r.id}`,
      })) });
    }

    if (topCalEvents.length) {
      results.push({ group: 'Calendar', items: topCalEvents.map(e => ({
        type:     'calendar',
        id:       e.id,
        title:    e.title,
        subtitle: e.allDay
          ? e.startAt.toISOString().split('T')[0]
          : e.startAt.toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: prefsHour12(req.user.preferences) }),
        url:      `/calendar`,
      })) });
    }

    if (lists.length) {
      results.push({ group: 'Lists', items: lists.map(l => ({
        type:     'list',
        id:       l.id,
        title:    l.title,
        subtitle: `${l._count.items} item${l._count.items === 1 ? '' : 's'}`,
        url:      `/lists/${l.id}`,
      })) });
    }

    if (bookmarks.length) {
      results.push({ group: 'Bookmarks', items: bookmarks.map(b => ({
        type:     'bookmark',
        id:       b.id,
        title:    b.title || b.url,
        subtitle: b.tags.length ? b.tags.slice(0, 3).join(', ') : (() => { try { return new URL(b.url).hostname; } catch { return b.url; } })(),
        url:      `/bookmarks`,
      })) });
    }

    res.json({ results, query: q });
  } catch (err) { next(err); }
});

module.exports = router;
