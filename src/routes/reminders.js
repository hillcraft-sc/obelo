const express = require('express');
const prisma = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const { fmtHHMM, prefsHour12 } = require('../lib/timeFormat');
const { getAllUserTags, parseTags: parseTagsShared } = require('../lib/tags');
const { zonedToUtc } = require('../lib/timezone');
const { nextRecurrence } = require('../lib/recurrence');

const router = express.Router();
router.use(requireAuth);

// ── Constants ────────────────────────────────────────────────────────────────

const PRIORITY_DOT = { none: 'bg-gray-600', low: 'bg-blue-500', medium: 'bg-amber-500', high: 'bg-red-500' };
const PRIORITY_RING = { none: 'border-gray-600', low: 'border-gray-600', medium: 'border-gray-600', high: 'border-gray-600' };
const PRIORITY_ICON = {
  none:   '<span class="w-3.5 h-3.5 shrink-0 inline-block"></span>',
  low:    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-width="2.5" stroke="currentColor" class="w-3.5 h-3.5 text-gray-400 shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 15.75l7.5-7.5 7.5 7.5"/></svg>',
  medium: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-width="2.5" stroke="currentColor" class="w-3.5 h-3.5 text-gray-400 shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l7.5-7.5 7.5 7.5m-15 6l7.5-7.5 7.5 7.5"/></svg>',
  high:   '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-width="2.5" stroke="currentColor" class="w-3.5 h-3.5 text-gray-400 shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 9l7.5-7.5 7.5 7.5m-15 6l7.5-7.5 7.5 7.5m-15 6l7.5-7.5 7.5 7.5"/></svg>',
};

// ── Helpers ──────────────────────────────────────────────────────────────────

const parseTags = parseTagsShared;

// Returns a human-readable label for any recurRule string.
function recurRuleLabel(rule) {
  const MAP = {
    hourly: 'Hourly', daily: 'Daily', weekdays: 'Weekdays', weekends: 'Weekends',
    weekly: 'Weekly', biweekly: 'Biweekly', monthly: 'Monthly',
    every3months: 'Every 3 Months', every6months: 'Every 6 Months', yearly: 'Yearly',
  };
  if (!rule) return '';
  if (MAP[rule]) return MAP[rule];
  if (rule.startsWith('custom:')) {
    const [, freq, intervalStr, dayType, a, b] = rule.split(':');
    const interval = parseInt(intervalStr) || 1;
    const UNIT = { daily: ['day', 'days'], weekly: ['week', 'weeks'], monthly: ['month', 'months'], yearly: ['year', 'years'] };
    const [sing, plur] = UNIT[freq] || ['?', '?'];
    let label = `Every ${interval} ${interval === 1 ? sing : plur}`;
    if (freq === 'monthly' && dayType === 'each') label += ` on day ${a}`;
    if (freq === 'monthly' && dayType === 'onthe') label += ` on the ${a} ${b}`;
    return label;
  }
  return rule;
}

function buildReminderAt(dueDate, dueTime, offsetMinutes, tz) {
  if (!dueDate || !dueTime) return null;
  const dateStr = (typeof dueDate === 'string' ? dueDate : dueDate.toISOString()).split('T')[0];

  let fireAt;
  if (tz) {
    fireAt = zonedToUtc(dateStr, dueTime, tz);   // the moment the user's clock reads that time
  } else {
    const [h, m] = dueTime.split(':').map(Number);
    fireAt = new Date(dueDate);
    fireAt.setHours(h, m, 0, 0);
  }

  return new Date(fireAt.getTime() - (offsetMinutes || 0) * 60000);
}

// The next occurrence of a recurring reminder: { dueDate, dueTime, reminderAt }, or null.
// With the user's time zone, the notification time is worked out again from the new date, so
// a 9:00 reminder stays at 9:00 on the clock when daylight saving starts or ends. Without a zone it
// keeps the old distance from the due date, which is only right when the clocks don't change.
function nextOccurrence(reminder, tz) {
  const next = nextRecurrence(reminder.dueDate ? new Date(reminder.dueDate) : null, reminder.recurRule, reminder.dueTime);
  if (!next) return null;
  const { dueDate, dueTime, hourly, rule } = next;

  let reminderAt;
  if (hourly && reminder.reminderAt) {
    reminderAt = new Date(reminder.reminderAt.getTime() + 60 * 60 * 1000);
  } else if (tz && reminder.reminderAt && reminder.dueDate && reminder.dueTime) {
    const was = buildReminderAt(utcDateStr(reminder.dueDate), reminder.dueTime, 0, tz);
    const offsetMinutes = Math.round((was - reminder.reminderAt) / 60000);   // how early the heads-up was
    reminderAt = buildReminderAt(utcDateStr(dueDate), dueTime, offsetMinutes, tz);
  } else if (reminder.reminderAt && reminder.dueDate) {
    reminderAt = new Date(dueDate.getTime() + (reminder.reminderAt.getTime() - reminder.dueDate.getTime()));
  } else if (tz && dueTime) {
    reminderAt = buildReminderAt(utcDateStr(dueDate), dueTime, 0, tz);
  } else {
    reminderAt = new Date(dueDate);
    if (dueTime) {
      const [h, m] = dueTime.split(':').map(Number);
      reminderAt.setUTCHours(h, m, 0, 0);
    }
  }
  return { dueDate, dueTime, reminderAt, rule };
}

// Every path that completes a reminder must go through here, or recurring reminders stop recurring
async function completeReminder(reminder, tz) {
  await prisma.reminder.update({
    where: { id: reminder.id },
    data: { completed: true, completedAt: new Date() },
  });

  if (reminder.recurring && reminder.recurRule) {
    const next = nextOccurrence(reminder, tz);
    if (next) {
      await prisma.reminder.create({
        data: {
          userId: reminder.userId,
          title: reminder.title,
          notes: reminder.notes,
          dueDate: next.dueDate,
          dueTime: next.dueTime ?? reminder.dueTime,
          reminderAt: next.reminderAt,
          priority: reminder.priority,
          tags: reminder.tags,
          recurring: true,
          recurRule: next.rule || reminder.recurRule,
        },
      });
    }
  }
}

function escHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// dueDate is stored as UTC midnight (new Date('YYYY-MM-DD') = UTC).
// Extract UTC date parts to avoid timezone-shift when comparing.
function utcDateStr(d) {
  const dt = new Date(d);
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
}

// Returns YYYY-MM-DD in the user's local timezone (not UTC).
// dueDates are stored as UTC midnight for the intended local date, so we compare
// using the local date string to avoid false positives near midnight.
function todayLocalStr(tz) {
  return new Date().toLocaleDateString('en-CA', { timeZone: tz || 'UTC' });
}

// Returns the current HH:MM in the user's timezone as a zero-padded string
function nowLocalHHMM(tz) {
  const s = new Date().toLocaleTimeString('en-US', { timeZone: tz || 'UTC', hour: '2-digit', minute: '2-digit', hour12: false });
  return s === '24:00' ? '00:00' : s;
}

function formatDue(reminder, use12h = true) {
  const date = reminder.dueDate
    ? new Date(reminder.dueDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })
    : '';
  const time = fmtHHMM(reminder.dueTime, use12h);
  return [date, time].filter(Boolean).join(' · ');
}

function isTimePast(dueTime, tz) {
  if (!dueTime) return false;
  return dueTime < nowLocalHHMM(tz); // zero-padded HH:MM string comparison is correct
}

function rowDueCls(reminder, tz) {
  if (reminder.completed) return 'text-gray-600';
  if (!reminder.dueDate) return 'text-gray-500';
  const today = todayLocalStr(tz);
  const due = utcDateStr(reminder.dueDate);
  if (due < today) return 'text-red-400 font-medium';
  if (due === today) {
    if (isTimePast(reminder.dueTime, tz)) return 'text-red-400 font-medium';
    return 'text-green-400';
  }
  return 'text-gray-400';
}

// ── Routes ───────────────────────────────────────────────────────────────────

// GET /reminders
router.get('/', async (req, res, next) => {
  try {
    const tz = req.user.timezone || 'UTC';
    const view = req.query.view || 'upcoming';
    const tag = req.query.tag || '';
    const tagFilter = tag ? { tags: { has: tag } } : {};
    const todayStr = todayLocalStr(tz);
    const todayStart = new Date(todayStr + 'T00:00:00.000Z');
    const todayEnd = new Date(todayStr + 'T23:59:59.999Z');
    const nowTimeStr = nowLocalHHMM(tz);

    // Overdue = past days OR today with a dueTime that has already passed (in user's timezone)
    const overdueWhere = {
      userId: req.user.id, completed: false, ...tagFilter,
      OR: [
        { dueDate: { lt: todayStart } },
        { dueDate: { gte: todayStart, lte: todayEnd }, dueTime: { lt: nowTimeStr, not: null } },
      ],
    };

    const whereMap = {
      upcoming:  { userId: req.user.id, completed: false, dueDate: { gte: todayStart }, ...tagFilter },
      today:     { userId: req.user.id, completed: false, dueDate: { gte: todayStart, lte: todayEnd }, ...tagFilter },
      overdue:   overdueWhere,
      completed: { userId: req.user.id, completed: true, ...tagFilter },
    };

    const where = whereMap[view] || whereMap.upcoming;
    const order = view === 'completed'
      ? [{ completedAt: 'desc' }]
      : [{ dueDate: 'asc' }, { dueTime: 'asc' }];

    const [reminders, overdueCount, todayCount, tagRows] = await Promise.all([
      prisma.reminder.findMany({ where, orderBy: order }),
      prisma.reminder.count({ where: overdueWhere }),
      prisma.reminder.count({ where: { userId: req.user.id, completed: false, dueDate: { gte: todayStart, lte: todayEnd } } }),
      prisma.reminder.findMany({ where: { userId: req.user.id }, select: { tags: true } }),
    ]);
    const allTags = [...new Set(tagRows.flatMap(r => r.tags))].sort();

    res.render('reminders/index', {
      title: 'Reminders', reminders, view,
      counts: { overdue: overdueCount, today: todayCount },
      allTags, activeTag: tag,
      PRIORITY_DOT, PRIORITY_RING, PRIORITY_ICON,
      rowDueCls: (r) => rowDueCls(r, tz),
      formatDue: (r) => formatDue(r, prefsHour12(req.user.preferences)),
    });
  } catch (err) { next(err); }
});

// GET /reminders/new
router.get('/new', async (req, res) => {
  const today = new Date().toLocaleDateString('en-CA', { timeZone: req.user?.timezone || 'UTC' });
  const tagList = await getAllUserTags(req.user.id);
  res.render('reminders/form', {
    title: 'New Reminder',
    reminder: { dueDate: today, priority: 'none' },
    errors: [],
    tagList,
  });
});

// POST /reminders — create
router.post('/', async (req, res, next) => {
  try {
    const { title, notes, dueDate, dueTime, reminderOffset = '0',
            priority = 'none', recurring, recurRule, tags: tagsRaw } = req.body;

    if (!title?.trim() || !dueDate || !dueTime) {
      const tagList = await getAllUserTags(req.user.id);
      return res.render('reminders/form', {
        title: 'New Reminder',
        reminder: req.body,
        errors: [!title?.trim() ? 'Title is required.' : 'Due date and time are required.'],
        tagList,
      });
    }

    const reminderAt = buildReminderAt(dueDate, dueTime, parseInt(reminderOffset), req.user.timezone || 'UTC');

    await prisma.reminder.create({
      data: {
        userId: req.user.id,
        title: title.trim(),
        notes: notes || '',
        dueDate: new Date(dueDate),
        dueTime,
        reminderAt,
        priority,
        tags: parseTags(tagsRaw),
        recurring: recurring === 'on',
        recurRule: recurring === 'on' ? (recurRule || 'daily') : null,
      },
    });

    res.redirect('/reminders');
  } catch (err) { next(err); }
});

// GET /reminders/:id
router.get('/:id', async (req, res, next) => {
  try {
    const reminder = await prisma.reminder.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id },
    });
    if (!reminder) return res.status(404).render('error', { title: 'Not found', error: { message: 'Reminder not found.' } });

    const tz = req.user.timezone || 'UTC';
    const today = todayLocalStr(tz);
    const due = reminder.dueDate ? utcDateStr(reminder.dueDate) : null;
    const isOverdue = due && !reminder.completed && (
      due < today || (due === today && isTimePast(reminder.dueTime, tz))
    );
    const isToday = due && due === today && !isOverdue;

    res.render('reminders/show', {
      title: reminder.title, reminder, isOverdue, isToday,
      PRIORITY_DOT, PRIORITY_ICON, recurRuleLabel,
    });
  } catch (err) { next(err); }
});

// GET /reminders/:id/edit
router.get('/:id/edit', async (req, res, next) => {
  try {
    const reminder = await prisma.reminder.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id },
    });
    if (!reminder) return res.status(404).render('error', { title: 'Not found', error: { message: 'Reminder not found.' } });
    const tagList = await getAllUserTags(req.user.id);
    res.render('reminders/form', { title: `Edit — ${reminder.title}`, reminder, errors: [], tagList });
  } catch (err) { next(err); }
});

// POST /reminders/bulk — bulk actions
router.post('/bulk', async (req, res, next) => {
  try {
    const ids = [req.body.ids || []].flat().map(Number).filter(Boolean);
    const { action, view } = req.body;
    const back = `/reminders?view=${view || 'upcoming'}`;
    if (!ids.length) return res.redirect(back);
    const where = { id: { in: ids }, userId: req.user.id };
    if (action === 'complete') {
      const reminders = await prisma.reminder.findMany({ where: { ...where, completed: false } });
      for (const r of reminders) await completeReminder(r, req.user.timezone || 'UTC');
    } else if (action === 'delete') {
      await prisma.reminder.deleteMany({ where });
    }
    res.redirect(back);
  } catch (err) { next(err); }
});

// POST /reminders/:id — update
router.post('/:id', async (req, res, next) => {
  try {
    const existing = await prisma.reminder.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id },
    });
    if (!existing) return res.status(404).render('error', { title: 'Not found', error: { message: 'Reminder not found.' } });

    const { title, notes, dueDate, dueTime, reminderOffset = '0',
            priority = 'none', recurring, recurRule, tags: tagsRaw } = req.body;

    if (!title?.trim() || !dueDate || !dueTime) {
      const tagList = await getAllUserTags(req.user.id);
      return res.render('reminders/form', {
        title: `Edit — ${existing.title}`,
        reminder: { ...existing, ...req.body, id: existing.id },
        errors: ['Title, date, and time are required.'],
        tagList,
      });
    }

    const reminderAt = buildReminderAt(dueDate, dueTime, parseInt(reminderOffset), req.user.timezone || 'UTC');

    await prisma.reminder.update({
      where: { id: existing.id },
      data: {
        title: title.trim(),
        notes: notes || '',
        dueDate: new Date(dueDate),
        dueTime,
        reminderAt,
        priority,
        tags: parseTags(tagsRaw),
        recurring: recurring === 'on',
        recurRule: recurring === 'on' ? (recurRule || 'daily') : null,
      },
    });

    res.redirect(`/reminders/${existing.id}`);
  } catch (err) { next(err); }
});

// POST /reminders/:id/delete
router.post('/:id/delete', async (req, res, next) => {
  try {
    const r = await prisma.reminder.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (r) await prisma.reminder.delete({ where: { id: r.id } });
    if (req.headers['hx-request']) return res.send('');
    res.redirect('/reminders');
  } catch (err) { next(err); }
});

// POST /reminders/:id/complete — HTMX
router.post('/:id/complete', async (req, res, next) => {
  try {
    const r = await prisma.reminder.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!r) return res.status(404).end();
    await completeReminder(r, req.user.timezone || 'UTC');
    res.send('');
  } catch (err) { next(err); }
});

// POST /reminders/:id/restore — HTMX
router.post('/:id/restore', async (req, res, next) => {
  try {
    const r = await prisma.reminder.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!r) return res.status(404).end();
    await prisma.reminder.update({ where: { id: r.id }, data: { completed: false, completedAt: null } });
    res.send('');
  } catch (err) { next(err); }
});

// POST /reminders/:id/snooze — HTMX
router.post('/:id/snooze', async (req, res, next) => {
  try {
    const r = await prisma.reminder.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!r) return res.status(404).end();

    const { duration } = req.body;
    const tz = req.user.timezone || 'UTC';
    // Snooze from now — or from the reminder's own time if that's still in the future
    const now = new Date();
    const base = r.reminderAt && r.reminderAt > now ? new Date(r.reminderAt) : now;
    let newReminderAt, newDueDate, newDueTime;

    if (duration === '15min') {
      newReminderAt = new Date(base.getTime() + 15 * 60 * 1000);
      newDueDate = r.dueDate;
      newDueTime = r.dueTime;
    } else if (duration === '1hour') {
      newReminderAt = new Date(base.getTime() + 60 * 60 * 1000);
      newDueDate = r.dueDate;
      newDueTime = r.dueTime;
    } else if (duration === 'tomorrow') {
      // Tomorrow in the user's timezone, not the day after the (possibly long past) due date
      const tomorrow = new Date(todayLocalStr(tz) + 'T00:00:00.000Z');
      tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
      newDueDate = tomorrow;
      newDueTime = r.dueTime || '09:00';
      newReminderAt = buildReminderAt(tomorrow.toISOString().split('T')[0], newDueTime, 0, tz);
    } else {
      return res.status(400).end();
    }

    await prisma.reminder.update({
      where: { id: r.id },
      data: { reminderAt: newReminderAt, dueDate: newDueDate, dueTime: newDueTime },
    });

    // Remove from current view — will appear when it's due again
    res.send('');
  } catch (err) { next(err); }
});

module.exports = { router, completeReminder, nextOccurrence, buildReminderAt, recurRuleLabel, todayLocalStr, nowLocalHHMM };
