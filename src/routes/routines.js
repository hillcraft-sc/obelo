const express = require('express');
const prisma = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const { getAllUserTags, parseTags } = require('../lib/tags');
const { DAYS, isScheduledDay, recalcStreak } = require('../services/routineStreaks');

const router = express.Router();
router.use(requireAuth);

// ── Constants ────────────────────────────────────────────────────────────────

const TIME_OF_DAY = ['morning', 'afternoon', 'evening', 'anytime'];
const TIME_LABELS = { morning: 'Morning', afternoon: 'Afternoon', evening: 'Evening', anytime: 'Anytime' };
const FREQ_LABELS = { daily: 'Daily', weekdays: 'Weekdays', weekends: 'Weekends', weekly: 'Weekly', custom: 'Custom' };

// ── Helpers ──────────────────────────────────────────────────────────────────

function todayUtcStr() {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth()+1).padStart(2,'0')}-${String(now.getUTCDate()).padStart(2,'0')}`;
}

function localDateStr(req) {
  const tz = req?.user?.timezone || 'UTC';
  return new Date().toLocaleDateString('en-CA', { timeZone: tz });
}

function todayDate(req) {
  return new Date((req ? localDateStr(req) : todayUtcStr()) + 'T00:00:00.000Z');
}

function isDueToday(routine, todayStr) {
  if (!routine.active) return false;
  const tStr = todayStr || todayUtcStr();
  // Don't show as due if start date is in the future
  if (routine.startDate) {
    const startStr = routine.startDate.toISOString().split('T')[0];
    if (startStr > tStr) return false;
  }
  return isScheduledDay(routine, new Date(tStr + 'T00:00:00.000Z'));
}

function buildHeatmapData(completions, routine, todayStr) {
  const completedSet = new Set(
    completions.map(c => c.completedDate.toISOString().split('T')[0])
  );
  const today = todayStr ? new Date(todayStr + 'T00:00:00.000Z') : todayDate();
  const todayDow = today.getUTCDay();
  const currentWeekSunday = new Date(today.getTime() - todayDow * 24 * 60 * 60 * 1000);
  const gridStart = new Date(currentWeekSunday.getTime() - 11 * 7 * 24 * 60 * 60 * 1000);
  // Normalise startDate to UTC midnight so date comparisons are consistent
  const routineStart = routine.startDate
    ? new Date(routine.startDate.toISOString().split('T')[0] + 'T00:00:00.000Z')
    : null;

  const weeks = [];
  for (let w = 0; w < 12; w++) {
    const week = [];
    for (let d = 0; d < 7; d++) {
      const date = new Date(gridStart.getTime() + (w * 7 + d) * 24 * 60 * 60 * 1000);
      const dateStr = date.toISOString().split('T')[0];
      const isFuture = date > today;
      // A day is "not applicable" if it's before the routine's start date OR if
      // the routine's frequency means it was never scheduled on that weekday.
      const beforeStart = routineStart ? date < routineStart : false;
      const notScheduled = !isScheduledDay(routine, date);
      const notApplicable = !isFuture && (beforeStart || notScheduled);
      week.push({
        dateStr,
        isFuture,
        notApplicable,
        completed: !isFuture && !notApplicable && completedSet.has(dateStr),
        label: date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }),
      });
    }
    weeks.push(week);
  }
  return weeks;
}

function buildWeeklyStats(completions, routine, todayStr) {
  const completedSet = new Set(
    completions.map(c => c.completedDate.toISOString().split('T')[0])
  );
  const today = todayStr ? new Date(todayStr + 'T00:00:00.000Z') : todayDate();
  const todayDow = today.getUTCDay();
  const currentWeekSunday = new Date(today.getTime() - todayDow * 24 * 60 * 60 * 1000);
  const gridStart = new Date(currentWeekSunday.getTime() - 11 * 7 * 24 * 60 * 60 * 1000);
  const routineStart = routine.startDate
    ? new Date(routine.startDate.toISOString().split('T')[0] + 'T00:00:00.000Z')
    : null;

  const stats = [];
  for (let w = 0; w < 12; w++) {
    const weekStart = new Date(gridStart.getTime() + w * 7 * 24 * 60 * 60 * 1000);
    let completionCount = 0;
    let scheduledCount = 0;
    for (let d = 0; d < 7; d++) {
      const day = new Date(weekStart.getTime() + d * 24 * 60 * 60 * 1000);
      if (day > today) continue;
      if (routineStart && day < routineStart) continue;
      if (!isScheduledDay(routine, day)) continue;
      scheduledCount++;
      if (completedSet.has(day.toISOString().split('T')[0])) completionCount++;
    }
    const rate = scheduledCount > 0 ? Math.round((completionCount / scheduledCount) * 100) : 0;
    stats.push({
      label: weekStart.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }),
      completionCount,
      dayCount: scheduledCount,
      rate,
    });
  }
  return stats;
}

// ── Routes ───────────────────────────────────────────────────────────────────

// GET /routines
router.get('/', async (req, res, next) => {
  try {
    const view = req.query.view || 'today';
    const tag = req.query.tag || '';
    const tagFilter = tag ? { tags: { has: tag } } : {};
    let routines;
    let completedStreaks = [];

    const countInclude = { _count: { select: { completions: true } } };

    if (view === 'archived') {
      const allArchived = await prisma.routine.findMany({
        where: { userId: req.user.id, active: false, ...tagFilter },
        orderBy: { createdAt: 'desc' },
        include: countInclude,
      });
      // Separate finished time-limited streaks from routines that were simply archived
      completedStreaks = allArchived.filter(
        r => r.durationDays && r._count.completions >= r.durationDays
      );
      routines = allArchived.filter(
        r => !(r.durationDays && r._count.completions >= r.durationDays)
      );
    } else {
      routines = await prisma.routine.findMany({
        where: { userId: req.user.id, active: true, ...tagFilter },
        orderBy: [{ timeOfDay: 'asc' }, { title: 'asc' }],
        include: countInclude,
      });
    }

    const todayStr = localDateStr(req);
    const today = todayDate(req);
    const [todayCompletions, tagRows] = await Promise.all([
      prisma.routineCompletion.findMany({ where: { userId: req.user.id, completedDate: today } }),
      prisma.routine.findMany({ where: { userId: req.user.id }, select: { tags: true } }),
    ]);
    const completedTodayIds = new Set(todayCompletions.map(c => c.routineId));
    const allTags = [...new Set(tagRows.flatMap(r => r.tags))].sort();

    const dueToday = view === 'today' ? routines.filter(r => isDueToday(r, todayStr)) : routines;
    const notDueToday = view === 'today' ? routines.filter(r => !isDueToday(r, todayStr)) : [];

    // Group due-today routines by time of day
    const grouped = Object.fromEntries(TIME_OF_DAY.map(k => [k, []]));
    for (const r of dueToday) {
      const key = TIME_OF_DAY.includes(r.timeOfDay) ? r.timeOfDay : 'anytime';
      grouped[key].push(r);
    }

    res.render('routines/index', {
      title: 'Routines',
      view,
      routines: dueToday,
      notDueToday,
      grouped,
      completedStreaks,
      allTags, activeTag: tag,
      TIME_OF_DAY,
      TIME_LABELS,
      FREQ_LABELS,
      isDueToday: (r) => isDueToday(r, todayStr),
      completedTodayIds,
    });
  } catch (err) { next(err); }
});

// GET /routines/new
router.get('/new', async (req, res) => {
  const tagList = await getAllUserTags(req.user.id);
  res.render('routines/form', {
    title: 'New Routine',
    routine: { frequency: 'daily', timeOfDay: 'anytime', scheduleDays: [], notify: false },
    DAYS,
    errors: [],
    tagList,
  });
});

// POST /routines
router.post('/', async (req, res, next) => {
  try {
    const { title, description, timeOfDay = 'anytime', specificTime,
            frequency = 'daily', scheduleDays, durationDays, startDate, notify, tags: tagsRaw } = req.body;

    if (!title?.trim()) {
      const tagList = await getAllUserTags(req.user.id);
      return res.render('routines/form', {
        title: 'New Routine',
        routine: req.body,
        DAYS,
        errors: ['Title is required.'],
        tagList,
      });
    }

    const days = Array.isArray(scheduleDays) ? scheduleDays : (scheduleDays ? [scheduleDays] : []);

    await prisma.routine.create({
      data: {
        userId: req.user.id,
        title: title.trim(),
        description: description || '',
        timeOfDay,
        specificTime: specificTime || null,
        frequency,
        scheduleDays: days,
        tags: parseTags(tagsRaw),
        durationDays: durationDays ? parseInt(durationDays) : null,
        startDate: startDate ? new Date(startDate + 'T00:00:00.000Z') : null,
        notify: notify === 'on',
      },
    });

    res.redirect('/routines');
  } catch (err) { next(err); }
});

// GET /routines/:id
router.get('/:id', async (req, res, next) => {
  try {
    const routine = await prisma.routine.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id },
    });
    if (!routine) return res.status(404).render('error', { title: 'Not found', error: { message: 'Routine not found.' } });

    const today = todayDate(req);
    const [todayCompletion, allCompletions] = await Promise.all([
      prisma.routineCompletion.findFirst({
        where: { routineId: routine.id, userId: req.user.id, completedDate: today },
      }),
      prisma.routineCompletion.findMany({
        where: { routineId: routine.id },
        orderBy: { completedDate: 'desc' },
      }),
    ]);

    const completionCount = allCompletions.length;
    const todayStr = localDateStr(req);
    res.render('routines/show', {
      title: routine.title,
      routine,
      completedToday: !!todayCompletion,
      isDueToday: isDueToday(routine, todayStr),
      heatmap: buildHeatmapData(allCompletions, routine, todayStr),
      weeklyStats: buildWeeklyStats(allCompletions, routine, todayStr),
      totalCompletions: completionCount,
      completionCount,
      TIME_LABELS,
      FREQ_LABELS,
      DAYS,
    });
  } catch (err) { next(err); }
});

// GET /routines/:id/edit
router.get('/:id/edit', async (req, res, next) => {
  try {
    const routine = await prisma.routine.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id },
    });
    if (!routine) return res.status(404).render('error', { title: 'Not found', error: { message: 'Routine not found.' } });
    const tagList = await getAllUserTags(req.user.id);
    res.render('routines/form', { title: `Edit — ${routine.title}`, routine, DAYS, errors: [], tagList });
  } catch (err) { next(err); }
});

// POST /routines/bulk — bulk actions
router.post('/bulk', async (req, res, next) => {
  try {
    const ids = [req.body.ids || []].flat().map(Number).filter(Boolean);
    const { action, view } = req.body;
    const back = `/routines?view=${view || 'today'}`;
    if (!ids.length) return res.redirect(back);
    const where = { id: { in: ids }, userId: req.user.id };
    if (action === 'archive') {
      await prisma.routine.updateMany({ where, data: { active: false } });
    } else if (action === 'restore') {
      await prisma.routine.updateMany({ where, data: { active: true } });
    } else if (action === 'delete') {
      await prisma.routine.deleteMany({ where });
    }
    res.redirect(back);
  } catch (err) { next(err); }
});

// POST /routines/:id — update
router.post('/:id', async (req, res, next) => {
  try {
    const existing = await prisma.routine.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id },
    });
    if (!existing) return res.status(404).render('error', { title: 'Not found', error: { message: 'Routine not found.' } });

    const { title, description, timeOfDay = 'anytime', specificTime,
            frequency = 'daily', scheduleDays, durationDays, startDate, notify, tags: tagsRaw } = req.body;

    if (!title?.trim()) {
      const tagList = await getAllUserTags(req.user.id);
      return res.render('routines/form', {
        title: `Edit — ${existing.title}`,
        routine: { ...existing, ...req.body, id: existing.id },
        DAYS,
        errors: ['Title is required.'],
        tagList,
      });
    }

    const days = Array.isArray(scheduleDays) ? scheduleDays : (scheduleDays ? [scheduleDays] : []);

    await prisma.routine.update({
      where: { id: existing.id },
      data: {
        title: title.trim(),
        description: description || '',
        timeOfDay,
        specificTime: specificTime || null,
        frequency,
        scheduleDays: days,
        tags: parseTags(tagsRaw),
        durationDays: durationDays ? parseInt(durationDays) : null,
        startDate: startDate ? new Date(startDate + 'T00:00:00.000Z') : null,
        notify: notify === 'on',
      },
    });
    // A schedule change can change which days count as missed
    await recalcStreak({ ...existing, frequency, scheduleDays: days }, localDateStr(req));

    res.redirect(`/routines/${existing.id}`);
  } catch (err) { next(err); }
});

// POST /routines/:id/delete
router.post('/:id/delete', async (req, res, next) => {
  try {
    const r = await prisma.routine.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (r) {
      await prisma.routineCompletion.deleteMany({ where: { routineId: r.id } });
      await prisma.routine.delete({ where: { id: r.id } });
    }
    res.redirect('/routines');
  } catch (err) { next(err); }
});

// POST /routines/:id/archive — toggle active
router.post('/:id/archive', async (req, res, next) => {
  try {
    const r = await prisma.routine.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!r) return res.status(404).end();
    await prisma.routine.update({ where: { id: r.id }, data: { active: !r.active } });
    res.redirect('/routines');
  } catch (err) { next(err); }
});

// POST /routines/:id/complete — HTMX toggle
router.post('/:id/complete', async (req, res, next) => {
  try {
    const routine = await prisma.routine.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!routine) return res.status(404).end();

    const today = todayDate(req);
    const existing = await prisma.routineCompletion.findFirst({
      where: { routineId: routine.id, userId: req.user.id, completedDate: today },
    });

    let completedToday;
    if (existing) {
      await prisma.routineCompletion.delete({ where: { id: existing.id } });
      completedToday = false;
    } else {
      // Only due routines can be completed — a stray tap on a "Not due today" row
      // otherwise logs the wrong routine and silently costs the intended one its streak.
      if (!isDueToday(routine, localDateStr(req))) return res.status(409).end();
      await prisma.routineCompletion.create({
        data: { routineId: routine.id, userId: req.user.id, completedDate: today, completedAt: new Date() },
      });
      completedToday = true;

      // Auto-archive time-limited routines the moment duration is reached.
      // Uses === rather than >= so this only fires once, on the completion
      // that hits the target — otherwise a routine restored after finishing
      // (active: true, durationDays/count unchanged) would re-archive itself
      // on every subsequent completion, since the count stays >= durationDays
      // forever after.
      if (routine.active && routine.durationDays) {
        const count = await prisma.routineCompletion.count({ where: { routineId: routine.id } });
        if (count === routine.durationDays) {
          await prisma.routine.update({ where: { id: routine.id }, data: { active: false } });
        }
      }
    }

    await recalcStreak(routine, localDateStr(req));
    const [refreshed, completionCount] = await Promise.all([
      prisma.routine.findUnique({ where: { id: routine.id } }),
      prisma.routineCompletion.count({ where: { routineId: routine.id } }),
    ]);

    res.render('routines/_row', {
      layout: false,
      routine: refreshed,
      completedToday,
      isDueToday: isDueToday(refreshed, localDateStr(req)),
      completionCount,
      FREQ_LABELS,
    });
  } catch (err) { next(err); }
});

module.exports = { router, isDueToday, todayDate, localDateStr, buildHeatmapData, buildWeeklyStats, TIME_OF_DAY, FREQ_LABELS };
