const express = require('express');
const prisma = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const { isDueToday, todayDate, localDateStr } = require('./routines');
const { noteSlipCutoff } = require('./notes');
const { byPriority } = require('../lib/priority');

const router = express.Router();

const PRIORITY_DOT = { none: 'bg-gray-600', low: 'bg-blue-500', medium: 'bg-amber-500', high: 'bg-red-500' };
const TIME_OF_DAY = ['morning', 'afternoon', 'evening', 'anytime'];
const TIME_LABELS = { morning: 'Morning', afternoon: 'Afternoon', evening: 'Evening', anytime: 'Anytime' };
const FREQ_LABELS = { daily: 'Daily', weekdays: 'Weekdays', weekends: 'Weekends', weekly: 'Weekly', custom: 'Custom' };

function todayLocalStr(tz) {
  return new Date().toLocaleDateString('en-CA', { timeZone: tz || 'UTC' });
}

// Public landing page for unauthenticated visitors
router.get('/', (req, res, next) => {
  if (req.session.userId) return next();
  res.render('landing', { layout: 'layouts/auth', title: 'Obelo' });
}, requireAuth, async (req, res, next) => {
  try {
    res.render('dashboard/index', {
      title: 'Today',
      ...await loadDashboard(req),
      isNewAccount: await isNewAccount(req.user.id),
      TIME_OF_DAY,
      TIME_LABELS,
      FREQ_LABELS,
      PRIORITY_DOT,
    });
  } catch (err) { next(err); }
});

// True until the account has anything in it. Used for the welcome card on Today.
async function isNewAccount(userId) {
  const counts = await Promise.all([
    prisma.note.count({ where: { userId } }),
    prisma.task.count({ where: { userId } }),
    prisma.reminder.count({ where: { userId } }),
    prisma.routine.count({ where: { userId } }),
    prisma.list.count({ where: { userId } }),
    prisma.bookmark.count({ where: { userId } }),
  ]);
  return counts.every((n) => n === 0);
}

// Everything the Today page shows; shared with the app API (routes/api.js)
async function loadDashboard(req) {
  const userId = req.user.id;
  const tz = req.user.timezone || 'UTC';
  const now = new Date();
  const todayStr = todayLocalStr(tz);
  const todayStart = new Date(todayStr + 'T00:00:00.000Z');
  const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
  const nowHHMM = (() => { const s = now.toLocaleTimeString('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false }); return s === '24:00' ? '00:00' : s; })();
  // Local-day boundaries for calendar events (which store real timestamps, not UTC-midnight dates).
  // Compute the UTC timestamp for local midnight by finding the timezone offset at noon on the local date.
  const _noonUTC = new Date(todayStr + 'T12:00:00Z');
  const _noonLocal = _noonUTC.toLocaleTimeString('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false });
  const [_nh, _nm] = (_noonLocal === '24:00' ? '00:00' : _noonLocal).split(':').map(Number);
  const _offsetMs = (_nh * 60 + _nm - 12 * 60) * 60000;
  const calDayStart = new Date(new Date(todayStr + 'T00:00:00Z').getTime() - _offsetMs);
  const calDayEnd   = new Date(calDayStart.getTime() + 24 * 60 * 60 * 1000);
  const slipCut = new Date(todayStart.getTime() - 7 * 24 * 60 * 60 * 1000);
  const noteSlipCut = noteSlipCutoff();

  const [
    focusTasks,
    calendarEvents,
    openTasks,
    openReminders,
    allActiveRoutines,
    todayRoutineCompletions,
    resurfacePool,
    reviewItems,
    slippingCount,
    slippingNotes,
  ] = await Promise.all([
    prisma.task.findMany({
      where: { userId, status: 'today' },
      orderBy: [{ dueDate: 'asc' }],
    }).then(tasks => tasks.sort(byPriority)),
    prisma.calendarEvent.findMany({
      where: {
        userId,
        // All-day events are stored as bare UTC-midnight dates (no real time-of-day), so they
        // must be matched against the UTC-based today window, not the timezone-shifted one —
        // otherwise they land on the wrong day for anyone in a timezone behind UTC. Timed
        // events carry a real instant and correctly use the local-day window. See eventDate.js.
        OR: [
          { allDay: true,  startAt: { lt: todayEnd },  endAt: { gt: todayStart } },
          { allDay: false, startAt: { lt: calDayEnd }, endAt: { gt: calDayStart } },
        ],
      },
      include: { source: { select: { color: true, name: true } }, localCalendar: { select: { color: true, name: true } } },
      orderBy: [{ allDay: 'desc' }, { startAt: 'asc' }],
    }),
    prisma.task.findMany({
      where: {
        userId,
        status: { notIn: ['done', 'archived', 'today'] },
        dueDate: { lt: todayEnd, not: null },
      },
      orderBy: [{ dueDate: 'asc' }, { dueTime: 'asc' }],
    }),
    prisma.reminder.findMany({
      where: {
        userId,
        completed: false,
        OR: [
          { dueDate: { lt: todayStart } },
          { dueDate: { gte: todayStart, lt: todayEnd } },
        ],
      },
      orderBy: [{ dueDate: 'asc' }, { dueTime: 'asc' }],
    }),
    prisma.routine.findMany({
      where: { userId, active: true },
      orderBy: [{ timeOfDay: 'asc' }, { title: 'asc' }],
    }),
    prisma.routineCompletion.findMany({
      where: { userId, completedDate: todayDate(req) },
    }),
    prisma.note.findMany({
      where: { userId, content: { not: null } },
      select: { id: true, title: true, content: true, type: true, createdAt: true },
      orderBy: { createdAt: 'asc' },
    }),
    prisma.note.findMany({
      where: {
        userId,
        flaggedForReview: true,
        OR: [{ reviewDate: { lte: todayEnd } }, { reviewDate: null }],
      },
      orderBy: [{ reviewDate: 'asc' }, { updatedAt: 'desc' }],
      take: 5,
    }),
    prisma.task.count({
      where: { userId, status: { in: ['inbox', 'today', 'in-progress'] }, updatedAt: { lt: slipCut } },
    }),
    prisma.note.findMany({
      where: { userId, updatedAt: { lt: noteSlipCut }, flaggedForReview: false },
      orderBy: [{ updatedAt: 'asc' }],
      take: 5,
      select: { id: true, title: true, content: true, type: true, updatedAt: true },
    }),
  ]);

  // Filter and group routines
  const dueRoutines = allActiveRoutines.filter(r => isDueToday(r, localDateStr(req)));
  const completedTodayIds = new Set(todayRoutineCompletions.map(c => c.routineId));
  const routineGroups = Object.fromEntries(TIME_OF_DAY.map(k => [k, []]));
  for (const r of dueRoutines) {
    const key = TIME_OF_DAY.includes(r.timeOfDay) ? r.timeOfDay : 'anytime';
    routineGroups[key].push(r);
  }

  // Overdue helpers
  function isOverdue(dueDate, dueTime) {
    if (!dueDate) return false;
    const dueUTC = dueDate.toISOString().split('T')[0];
    if (dueUTC < todayStr) return true;
    if (dueUTC === todayStr && dueTime) {
      return dueTime < nowHHMM;
    }
    return false;
  }

  // Build combined sorted list (overdue first, then by time)
  const combined = [
    ...openTasks.map(t => ({ item: t, type: 'task', overdue: isOverdue(t.dueDate, t.dueTime), isToday: !!(t.dueDate && t.dueDate.toISOString().split('T')[0] === todayStr && !isOverdue(t.dueDate, t.dueTime)) })),
    ...openReminders.map(r => ({ item: r, type: 'reminder', overdue: isOverdue(r.dueDate, r.dueTime), isToday: !!(r.dueDate && r.dueDate.toISOString().split('T')[0] === todayStr && !isOverdue(r.dueDate, r.dueTime)) })),
  ].sort((a, b) => {
    if (a.overdue !== b.overdue) return a.overdue ? -1 : 1;
    const aMs = a.item.dueDate?.getTime() ?? Infinity;
    const bMs = b.item.dueDate?.getTime() ?? Infinity;
    if (aMs !== bMs) return aMs - bMs;
    return (a.item.dueTime || '').localeCompare(b.item.dueTime || '');
  });

  // Resurfacing: one note per day, seeded by date
  const dayIndex = Math.floor(todayStart.getTime() / 86400000);
  const resurfaceNote = resurfacePool.length > 0
    ? resurfacePool[dayIndex % resurfacePool.length]
    : null;

  // Dashboard widget preferences
  const DEFAULT_WIDGETS = ['focus', 'calendar', 'due_items', 'routines', 'resurfaced', 'review'];
  const savedWidgets = req.user.preferences?.dashboardWidgets;
  const dashWidgets = savedWidgets && savedWidgets.length
    ? savedWidgets
    : DEFAULT_WIDGETS.map(key => ({ key, enabled: true }));

  return {
    focusTasks,
    calendarEvents,
    combined,
    dueRoutines,
    routineGroups,
    completedTodayIds,
    reviewItems,
    resurfaceNote,
    slippingCount,
    slippingNotes,
    dashWidgets,
    isOverdue,
    todayStr,
  };
}

module.exports = { router, loadDashboard, TIME_OF_DAY };
