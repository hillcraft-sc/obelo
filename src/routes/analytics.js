const express = require('express');
const router = express.Router();
const prisma = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const { standsOut, refineWithAi } = require('../services/analyticsInsights');

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const DAY_ABBR = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const PRIORITY_LABELS = { high: 'High', medium: 'Medium', low: 'Low', none: 'None' };

function isScheduledDay(routine, date) {
  const dow = date.getUTCDay();
  switch (routine.frequency) {
    case 'daily':    return true;
    case 'weekdays': return dow >= 1 && dow <= 5;
    case 'weekends': return dow === 0 || dow === 6;
    case 'weekly':
    case 'custom':   return (routine.scheduleDays || []).includes(DAY_ABBR[dow]);
    default:         return true;
  }
}

// Returns the YYYY-MM-DD string for the calendar day before the given YYYY-MM-DD string.
function subtractOneDay(dateStr) {
  const d = new Date(dateStr + 'T12:00:00.000Z');
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().split('T')[0];
}

// Returns local minutes-since-midnight for a UTC timestamp in the given timezone.
function getLocalMinutes(date, tz) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz, hour: 'numeric', minute: 'numeric', hour12: false,
  }).formatToParts(date);
  const hour   = parseInt(parts.find(p => p.type === 'hour').value, 10) % 24;
  const minute = parseInt(parts.find(p => p.type === 'minute').value, 10);
  return hour * 60 + minute;
}

// Buckets: early | on_time | late_same_day | late_1_3 | late_4_7 | late_8plus | no_due
//
// When dueTime ("HH:MM") is present:
//   - early        : completed before the due time (same or prior day)
//   - on_time      : completed within 30 min after the due time (grace window)
//   - late_same_day: completed >30 min past due time but still the same calendar day
//   - late_*       : completed on a later calendar day (1-3d / 4-7d / 8+d)
//
// When dueTime is absent:
//   - early   : completed on a prior calendar day
//   - on_time : completed on the same calendar day
//   - late_*  : completed on a later calendar day
//   (no late_same_day bucket — there's no time to compare against)
// Time-of-day windows for routines (local minutes). A routine set to "anytime" with no specific
// time has no planned moment, so it isn't timed.
const ROUTINE_WINDOWS = { morning: [5 * 60, 12 * 60], afternoon: [12 * 60, 17 * 60], evening: [17 * 60, 22 * 60] };

function classifyItem(dueDate, dueTime, completedAt, tz) {
  if (!dueDate) return { bucket: 'no_due', diffDays: 0 };

  // dueDate is stored as midnight UTC for the calendar date — read it as UTC,
  // not in the user's timezone (which would shift it back a day for UTC- users).
  const dueDateStr  = dueDate.toISOString().split('T')[0];
  const compDateStr = completedAt.toLocaleDateString('en-CA', { timeZone: tz });
  const diffDays = Math.round(
    (new Date(compDateStr + 'T00:00:00.000Z') - new Date(dueDateStr + 'T00:00:00.000Z')) / 86400000
  );

  if (diffDays < 0) return { bucket: 'early', diffDays };

  if (diffDays === 0 && dueTime) {
    const [dueH, dueM] = dueTime.split(':').map(Number);
    const dueMinutes  = dueH * 60 + dueM;
    const compMinutes = getLocalMinutes(completedAt, tz);
    const delta = compMinutes - dueMinutes;
    if (delta < 0)   return { bucket: 'early',         diffDays: 0 };
    if (delta <= 30) return { bucket: 'on_time',        diffDays: 0 };
    return              { bucket: 'late_same_day', diffDays: 0, lateMinutes: delta };
  }

  if (diffDays === 0) return { bucket: 'on_time',   diffDays };
  if (diffDays <= 3)  return { bucket: 'late_1_3',  diffDays };
  if (diffDays <= 7)  return { bucket: 'late_4_7',  diffDays };
  return                     { bucket: 'late_8plus', diffDays };
}

// Timing for one routine completion, or null when the routine has no planned moment.
// A set time works like a task's due time. A time-of-day window is early before it opens, on time
// while it's open, and late after it closes on the same day. Other days use the same buckets as tasks.
function classifyRoutineCompletion(completedDate, routine, completedAt, tz) {
  if (routine.specificTime) return classifyItem(completedDate, routine.specificTime, completedAt, tz);
  const window = ROUTINE_WINDOWS[routine.timeOfDay];
  if (!window) return null;
  const day = classifyItem(completedDate, null, completedAt, tz);
  if (day.bucket !== 'on_time') return day;
  const [startMin, endMin] = window;
  const minutes = getLocalMinutes(completedAt, tz);
  if (minutes < startMin) return { bucket: 'early', diffDays: 0 };
  if (minutes <= endMin)  return { bucket: 'on_time', diffDays: 0 };
  return { bucket: 'late_same_day', diffDays: 0, lateMinutes: minutes - endMin };
}

router.get('/', requireAuth, async (req, res, next) => {
  try {
    const a = await computeAnalytics(req.session.userId, req.user.timezone || 'America/New_York', req.query.range);
    res.render('analytics/index', {
      title: 'Analytics',
      range: a.range,
      rangeLabel: a.rangeLabel,
      summary: a.summary,
      standsOut: await refineWithAi(a.standsOut),
      streak: a.streak,
      weeklyDataJson: JSON.stringify(a.weeklyData),
      onTimeRateTrendJson: JSON.stringify(a.onTimeRateTrend),
      hasOnTimeRateTrend: a.hasOnTimeRateTrend,
      todDataJson: JSON.stringify(a.todData),
      hasTodData: a.hasTodData,
      lateAgeStats: a.lateAgeStats,
      velocityDataJson: JSON.stringify(a.velocityData),
      velocityTrend: a.velocityTrend,
      hasVelocityData: a.hasVelocityData,
      priorityData: a.priorityData,
      heatmap: a.heatmap,
      routineStats: a.routineStats,
      routineVelDataJson: JSON.stringify(a.routineVelData),
      hasRoutineVelData: a.hasRoutineVelData,
    });
  } catch (err) {
    next(err);
  }
});

// Everything the Analytics page shows; shared with the app API (routes/api.js)
async function computeAnalytics(userId, tz, rangeParam) {
  const range = ['30', '90', 'all'].includes(rangeParam) ? rangeParam : '30';

  const now = new Date();
  const todayStr = now.toLocaleDateString('en-CA', { timeZone: tz });
  const today = new Date(todayStr + 'T00:00:00.000Z');

  let cutoff, numWeeks, rangeLabel;
  if (range === '90') {
    cutoff = new Date(today.getTime() - 90 * 86400000);
    numWeeks = 13;
    rangeLabel = 'Last 90 days';
  } else if (range === 'all') {
    cutoff = new Date('2020-01-01T00:00:00.000Z');
    numWeeks = 26;
    rangeLabel = 'All time';
  } else {
    cutoff = new Date(today.getTime() - 30 * 86400000);
    numWeeks = 5;
    rangeLabel = 'Last 30 days';
  }

  const [rawTasks, rawReminders, routineCompsInRange] = await Promise.all([
    prisma.task.findMany({
      where: { userId, status: 'done', completedAt: { not: null, gte: cutoff } },
      select: { id: true, dueDate: true, dueTime: true, completedAt: true, priority: true },
    }),
    prisma.reminder.findMany({
      where: { userId, completed: true, completedAt: { not: null, gte: cutoff } },
      select: { id: true, dueDate: true, dueTime: true, completedAt: true, priority: true },
    }),
    prisma.routineCompletion.findMany({
      where: { userId, completedAt: { not: null, gte: cutoff } },
      select: { completedDate: true, completedAt: true, routine: { select: { timeOfDay: true, specificTime: true } } },
    }),
  ]);

  const timedItems = [...rawTasks, ...rawReminders].map(item => {
    const { bucket, diffDays, lateMinutes } = classifyItem(item.dueDate, item.dueTime, item.completedAt, tz);
    return { ...item, bucket, diffDays, lateMinutes: lateMinutes || 0 };
  });
  // Timed routine completions join the same buckets; untimed ones are left out of the timing analysis
  const routineItems = routineCompsInRange.flatMap(c => {
    const cls = c.routine ? classifyRoutineCompletion(c.completedDate, c.routine, c.completedAt, tz) : null;
    if (!cls) return [];
    return [{ completedAt: c.completedAt, priority: null, isRoutine: true, bucket: cls.bucket,
              diffDays: cls.diffDays, lateMinutes: cls.lateMinutes || 0 }];
  });
  const items = [...timedItems, ...routineItems];

  // Summary
  const withDue = items.filter(i => i.bucket !== 'no_due');
  const noDue   = items.filter(i => i.bucket === 'no_due');

  // True on-time: early or within 30-min grace window
  const trueOnTime   = withDue.filter(i => i.bucket === 'early' || i.bucket === 'on_time');
  // Same-day: completed the right calendar day regardless of time
  const sameDayItems = withDue.filter(i => i.bucket === 'early' || i.bucket === 'on_time' || i.bucket === 'late_same_day');
  // Day-late items only (for avg days late — same_day items have diffDays=0)
  const dayLateItems = withDue.filter(i => ['late_1_3', 'late_4_7', 'late_8plus'].includes(i.bucket));

  const trueOnTimeRate = withDue.length > 0 ? Math.round(trueOnTime.length   / withDue.length * 100) : null;
  const sameDayRate    = withDue.length > 0 ? Math.round(sameDayItems.length  / withDue.length * 100) : null;
  const avgDaysLate    = dayLateItems.length > 0
    ? Math.round(dayLateItems.reduce((s, i) => s + i.diffDays, 0) / dayLateItems.length * 10) / 10
    : null;

  const dowCounts = [0, 0, 0, 0, 0, 0, 0];
  items.forEach(i => {
    const localDay = new Intl.DateTimeFormat('en-US', { timeZone: tz, weekday: 'short' }).format(new Date(i.completedAt));
    const idx = DAY_ABBR.indexOf(localDay);
    if (idx >= 0) dowCounts[idx]++;
  });
  const maxDowCount = Math.max(...dowCounts);
  const topDowIdx   = maxDowCount > 0 ? dowCounts.indexOf(maxDowCount) : -1;

  const summary = {
    total: items.length,
    withDueCount: withDue.length,
    noDueCount: noDue.length,
    trueOnTimeRate,
    sameDayRate,
    avgDaysLate,
    topDay: topDowIdx >= 0 ? DAYS[topDowIdx] : null,
    topDayCount: topDowIdx >= 0 ? maxDowCount : 0,
  };

  // Weekly stacked bar
  const todayDow = today.getUTCDay();
  const currentWeekSunday = new Date(today.getTime() - todayDow * 86400000);
  const gridStart = new Date(currentWeekSunday.getTime() - (numWeeks - 1) * 7 * 86400000);

  const weeklyData = [];
  for (let w = 0; w < numWeeks; w++) {
    const weekStart = new Date(gridStart.getTime() + w * 7 * 86400000);
    const weekEnd   = new Date(weekStart.getTime() + 7 * 86400000);
    const label = weekStart.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
    const counts = { early: 0, on_time: 0, late_same_day: 0, late_1_3: 0, late_4_7: 0, late_8plus: 0 };
    items.forEach(item => {
      if (item.bucket === 'no_due') return;
      const comp = new Date(item.completedAt);
      if (comp >= weekStart && comp < weekEnd) counts[item.bucket]++;
    });
    weeklyData.push({ label, ...counts });
  }

  // On-time rate trend per week (% of items with due dates completed early or on time)
  const onTimeRateTrend = weeklyData.map(w => {
    const total = w.early + w.on_time + w.late_same_day + w.late_1_3 + w.late_4_7 + w.late_8plus;
    return { label: w.label, rate: total > 0 ? Math.round((w.early + w.on_time) / total * 100) : null, total };
  });
  const hasOnTimeRateTrend = onTimeRateTrend.some(w => w.total > 0);

  // Priority breakdown — uses true on-time rate (early + on_time, not late_same_day)
  const priorityData = ['high', 'medium', 'low', 'none'].map(priority => {
    const pItems  = withDue.filter(i => i.priority === priority);
    const pTrue   = pItems.filter(i => i.bucket === 'early' || i.bucket === 'on_time');
    const pSameDay= pItems.filter(i => ['early','on_time','late_same_day'].includes(i.bucket));
    const trueRate   = pItems.length > 0 ? Math.round(pTrue.length    / pItems.length * 100) : null;
    const sdRate     = pItems.length > 0 ? Math.round(pSameDay.length / pItems.length * 100) : null;
    return { priority, label: PRIORITY_LABELS[priority], total: pItems.length,
             trueOnTimeCount: pTrue.length, trueRate, sameDayCount: pSameDay.length, sdRate };
  });

  // DOW heatmap — always 12 weeks
  const heatNumWeeks = 12;
  const heatGridStart = new Date(currentWeekSunday.getTime() - (heatNumWeeks - 1) * 7 * 86400000);

  let heatItems = items;
  if (range === '30') {
    const heatCutoff = heatGridStart;
    const [heatTasks, heatReminders] = await Promise.all([
      prisma.task.findMany({
        where: { userId, status: 'done', completedAt: { not: null, gte: heatCutoff } },
        select: { completedAt: true },
      }),
      prisma.reminder.findMany({
        where: { userId, completed: true, completedAt: { not: null, gte: heatCutoff } },
        select: { completedAt: true },
      }),
    ]);
    heatItems = [...heatTasks, ...heatReminders].map(i => ({ completedAt: i.completedAt }));
  }

  const countMap = {};
  heatItems.forEach(i => {
    const dateStr = new Date(i.completedAt).toLocaleDateString('en-CA', { timeZone: tz });
    countMap[dateStr] = (countMap[dateStr] || 0) + 1;
  });
  // Add routine completions to heatmap using completedDate (already the local date as @db.Date)
  const heatRoutineComps = await prisma.routineCompletion.findMany({
    where: { userId, completedDate: { gte: heatGridStart } },
    select: { completedDate: true },
  });
  heatRoutineComps.forEach(c => {
    const dateStr = c.completedDate.toISOString().split('T')[0];
    countMap[dateStr] = (countMap[dateStr] || 0) + 1;
  });
  const maxHeatCount = Math.max(1, ...Object.values(countMap));

  const heatWeeks = [];
  const weekLabels = [];
  for (let w = 0; w < heatNumWeeks; w++) {
    const weekStart = new Date(heatGridStart.getTime() + w * 7 * 86400000);
    weekLabels.push(weekStart.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }));
    const week = [];
    for (let d = 0; d < 7; d++) {
      const date    = new Date(heatGridStart.getTime() + (w * 7 + d) * 86400000);
      const dateStr = date.toISOString().split('T')[0];
      const isFuture = date > today;
      const count = countMap[dateStr] || 0;
      const intensity = isFuture ? 0 : Math.min(4, Math.ceil(count / maxHeatCount * 4));
      week.push({
        dateStr, isFuture, count, intensity,
        title: date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }) + ': ' + count + ' completed',
      });
    }
    heatWeeks.push(week);
  }
  const heatmap = { weeks: heatWeeks, maxCount: maxHeatCount, dayLabels: DAY_ABBR, weekLabels };

  // Metric 1: Time-of-day pattern — tasks, reminders, and routines (with completedAt)
  const hourCounts = new Array(24).fill(0);
  [...items.filter(i => !i.isRoutine), ...routineCompsInRange].forEach(item => {
    const h = parseInt(
      new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: 'numeric', hour12: false })
        .format(new Date(item.completedAt)), 10
    ) % 24;
    hourCounts[h]++;
  });
  const TOD_LABELS = ['12am','2am','4am','6am','8am','10am','12pm','2pm','4pm','6pm','8pm','10pm'];
  const todData = TOD_LABELS.map((label, i) => ({ label, count: hourCounts[i * 2] + hourCounts[i * 2 + 1] }));
  const hasTodData = todData.some(b => b.count > 0);

  // Metric 2: Late 8+ days — age at completion
  const late8Items = items.filter(i => i.bucket === 'late_8plus');
  let lateAgeStats = null;
  if (late8Items.length > 0) {
    const diffs = late8Items.map(i => i.diffDays).sort((a, b) => a - b);
    const avg = Math.round(diffs.reduce((s, d) => s + d, 0) / diffs.length * 10) / 10;
    const mid = Math.floor(diffs.length / 2);
    const median = diffs.length % 2 === 0
      ? Math.round((diffs[mid - 1] + diffs[mid]) / 2 * 10) / 10
      : diffs[mid];
    lateAgeStats = { count: late8Items.length, avg, median, max: diffs[diffs.length - 1] };
  }

  // Metrics 3 & 4: shared all-time fetch (streak needs all history; velocity filters to 12w)
  const [allHistTasks, allHistReminders, allHistRoutineComps] = await Promise.all([
    prisma.task.findMany({ where: { userId, status: 'done', completedAt: { not: null } }, select: { completedAt: true } }),
    prisma.reminder.findMany({ where: { userId, completed: true, completedAt: { not: null } }, select: { completedAt: true } }),
    prisma.routineCompletion.findMany({ where: { userId }, select: { completedDate: true } }),
  ]);
  const allHistItems = [...allHistTasks, ...allHistReminders];

  // Metric 3: Productivity streak (all-time, timezone-aware)
  const allDatesSet = new Set(
    allHistItems.map(i => new Date(i.completedAt).toLocaleDateString('en-CA', { timeZone: tz }))
  );
  // Include routine completion dates in the streak (completedDate is already the local date)
  allHistRoutineComps.forEach(c => {
    allDatesSet.add(c.completedDate.toISOString().split('T')[0]);
  });
  let currentStreak = 0;
  {
    let dStr = todayStr;
    if (!allDatesSet.has(dStr)) dStr = subtractOneDay(dStr); // give benefit of the doubt if today is in progress
    for (let i = 0; i < 5000; i++) {
      if (!allDatesSet.has(dStr)) break;
      currentStreak++;
      dStr = subtractOneDay(dStr);
    }
  }
  let bestStreak = 0;
  {
    const sorted = Array.from(allDatesSet).sort();
    let run = 0;
    for (let i = 0; i < sorted.length; i++) {
      run = (i > 0 && subtractOneDay(sorted[i]) === sorted[i - 1]) ? run + 1 : 1;
      if (run > bestStreak) bestStreak = run;
    }
  }
  const streak = { current: currentStreak, best: Math.max(bestStreak, currentStreak) };

  // Metric 4: Completion velocity — always 12 weeks regardless of range toggle
  const velNumWeeks = 12;
  const velStart = new Date(currentWeekSunday.getTime() - (velNumWeeks - 1) * 7 * 86400000);
  const velItems = allHistItems.filter(i => i.completedAt >= velStart);
  const velocityData = [];
  for (let w = 0; w < velNumWeeks; w++) {
    const wStart = new Date(velStart.getTime() + w * 7 * 86400000);
    const wEnd   = new Date(wStart.getTime() + 7 * 86400000);
    velocityData.push({
      label: wStart.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }),
      count: velItems.filter(i => i.completedAt >= wStart && i.completedAt < wEnd).length,
    });
  }
  const last4Avg  = velocityData.slice(-4).reduce((s, w) => s + w.count, 0) / 4;
  const prior4Avg = velocityData.slice(-8, -4).reduce((s, w) => s + w.count, 0) / 4;
  let velocityTrend = 'steady';
  if (prior4Avg > 0) {
    const pctChange = (last4Avg - prior4Avg) / prior4Avg;
    velocityTrend = pctChange > 0.1 ? 'up' : pctChange < -0.1 ? 'down' : 'steady';
  } else if (last4Avg > 0) {
    velocityTrend = 'up';
  }
  const hasVelocityData = velocityData.some(w => w.count > 0);

  // Routines completion (always last 30 days) + 8-week velocity
  const thirtyDaysAgo = new Date(today.getTime() - 30 * 86400000);
  const routineVelWeeks = 8;
  const routineVelStart = new Date(currentWeekSunday.getTime() - (routineVelWeeks - 1) * 7 * 86400000);

  const [routines, routineVelComps, allStreakHistory] = await Promise.all([
    prisma.routine.findMany({ where: { userId, active: true }, orderBy: { title: 'asc' } }),
    prisma.routineCompletion.findMany({
      where: { userId, completedDate: { gte: routineVelStart } },
      select: { routineId: true, completedDate: true },
    }),
    prisma.routineStreakHistory.findMany({
      where: { userId },
      orderBy: { startDate: 'desc' },
    }),
  ]);

  let routineStats = { overallRate: null, totalExpected: 0, totalCompleted: 0, byRoutine: [] };
  let routineVelData = [];
  let hasRoutineVelData = false;

  if (routines.length > 0) {
    const completions = await prisma.routineCompletion.findMany({
      where: { routineId: { in: routines.map(r => r.id) }, completedDate: { gte: thirtyDaysAgo } },
      select: { routineId: true, completedDate: true, completedAt: true },
    });

    const compByRoutine = {};
    completions.forEach(c => {
      if (!compByRoutine[c.routineId]) compByRoutine[c.routineId] = { dates: new Set(), completedAts: [] };
      compByRoutine[c.routineId].dates.add(c.completedDate.toISOString().split('T')[0]);
      if (c.completedAt) compByRoutine[c.routineId].completedAts.push(c.completedAt);
    });

    // Index streak history by routineId
    const histByRoutine = {};
    allStreakHistory.forEach(h => {
      if (!histByRoutine[h.routineId]) histByRoutine[h.routineId] = [];
      histByRoutine[h.routineId].push(h);
    });

    let totalExpected = 0;
    let totalCompleted = 0;

    const byRoutine = routines.map(routine => {
      let expected = 0;
      // Floor the window at whichever is later: 30 days ago or the routine's creation date.
      const createdFloor = routine.createdAt
        ? new Date(routine.createdAt.toISOString().split('T')[0] + 'T00:00:00.000Z')
        : thirtyDaysAgo;
      const windowStart = createdFloor > thirtyDaysAgo ? createdFloor : thirtyDaysAgo;
      for (let i = 0; i <= 30; i++) {
        const d = new Date(thirtyDaysAgo.getTime() + i * 86400000);
        if (d > today) continue;
        if (d < windowStart) continue;
        if (routine.startDate) {
          if (d.toISOString().split('T')[0] < routine.startDate.toISOString().split('T')[0]) continue;
        }
        if (isScheduledDay(routine, d)) expected++;
      }
      const completedInfo = compByRoutine[routine.id] || { dates: new Set(), completedAts: [] };
      // Only completions on days that count toward `expected`, so the rate can't exceed 100%
      const windowStartStr = windowStart.toISOString().split('T')[0];
      const startStr = routine.startDate ? routine.startDate.toISOString().split('T')[0] : null;
      const completed = [...completedInfo.dates].filter(ds =>
        ds >= windowStartStr && ds <= todayStr && (!startStr || ds >= startStr) &&
        isScheduledDay(routine, new Date(ds + 'T00:00:00.000Z'))
      ).length;
      const rate = expected > 0 ? Math.round(completed / expected * 100) : null;
      totalExpected  += expected;
      totalCompleted += completed;

      // Specific-time on-time rate: for routines with specificTime, compare actual completedAt vs scheduled time
      let specificTimeRate = null;
      if (routine.specificTime && completedInfo.completedAts.length > 0) {
        const [spH, spM] = routine.specificTime.split(':').map(Number);
        const spMinutes = spH * 60 + spM;
        const onTimeCount = completedInfo.completedAts.filter(ca => {
          return getLocalMinutes(new Date(ca), tz) <= spMinutes + 30;
        }).length;
        specificTimeRate = Math.round(onTimeCount / completedInfo.completedAts.length * 100);
      }

      const history = histByRoutine[routine.id] || [];
      const completedStreaks = history.filter(h => !h.isActive);
      const streakCount = history.length;
      const streakAvg = streakCount > 0
        ? Math.round(history.reduce((s, h) => s + h.length, 0) / streakCount)
        : 0;
      // Most recently ended (broken) streak
      const lastBroken = completedStreaks.length > 0
        ? completedStreaks.sort((a, b) => new Date(b.endDate) - new Date(a.endDate))[0]
        : null;
      // Top 3 past streaks by length (excluding current active)
      const topStreaks = [...history]
        .sort((a, b) => b.length - a.length)
        .slice(0, 3)
        .map(h => ({
          length: h.length,
          startDate: h.startDate.toISOString().split('T')[0],
          endDate: h.endDate.toISOString().split('T')[0],
          isActive: h.isActive,
        }));

      return {
        id: routine.id, title: routine.title, frequency: routine.frequency,
        specificTime: routine.specificTime, timeOfDay: routine.timeOfDay,
        expected, completed, rate,
        streakCurrent: routine.streakCurrent, streakBest: routine.streakBest,
        streakCount, streakAvg, lastBroken, topStreaks,
        specificTimeRate, timedSampleSize: completedInfo.completedAts.length,
      };
    }).sort((a, b) => {
      if (a.rate === null && b.rate === null) return 0;
      if (a.rate === null) return 1;
      if (b.rate === null) return -1;
      return a.rate - b.rate;
    });

    const overallRate = totalExpected > 0 ? Math.round(totalCompleted / totalExpected * 100) : null;
    routineStats = { overallRate, totalExpected, totalCompleted, byRoutine };

    // 8-week aggregate routine velocity
    for (let w = 0; w < routineVelWeeks; w++) {
      const wStart = new Date(routineVelStart.getTime() + w * 7 * 86400000);
      const wEnd   = new Date(wStart.getTime() + 7 * 86400000);
      let weekExpected = 0;
      let weekCompleted = 0;
      routines.forEach(routine => {
        const createdFloor = routine.createdAt.toISOString().split('T')[0];
        const startFloor   = routine.startDate ? routine.startDate.toISOString().split('T')[0] : null;
        for (let d = 0; d < 7; d++) {
          const day    = new Date(wStart.getTime() + d * 86400000);
          if (day > today) continue;
          const dayStr = day.toISOString().split('T')[0];
          if (dayStr < createdFloor) continue;
          if (startFloor && dayStr < startFloor) continue;
          if (isScheduledDay(routine, day)) weekExpected++;
        }
      });
      // Same routines and days as weekExpected (active routines, scheduled days only)
      const activeById = Object.fromEntries(routines.map(r => [r.id, r]));
      routineVelComps.forEach(c => {
        const routine = activeById[c.routineId];
        if (!routine || c.completedDate < wStart || c.completedDate >= wEnd || c.completedDate > today) return;
        const dayStr = c.completedDate.toISOString().split('T')[0];
        if (dayStr < routine.createdAt.toISOString().split('T')[0]) return;
        if (routine.startDate && dayStr < routine.startDate.toISOString().split('T')[0]) return;
        if (isScheduledDay(routine, c.completedDate)) weekCompleted++;
      });
      const rate = weekExpected > 0 ? Math.round(weekCompleted / weekExpected * 100) : null;
      routineVelData.push({
        label: wStart.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }),
        expected: weekExpected, completed: weekCompleted, rate,
      });
    }
    hasRoutineVelData = routineVelData.some(w => w.expected > 0);
  }

  return {
    range,
    rangeLabel,
    summary,
    streak,
    weeklyData,
    onTimeRateTrend,
    hasOnTimeRateTrend,
    todData,
    hasTodData,
    lateAgeStats,
    velocityData,
    velocityTrend,
    hasVelocityData,
    priorityData,
    heatmap,
    routineStats,
    routineVelData,
    hasRoutineVelData,
    standsOut: standsOut({ summary, routineStats }),
  };
}

module.exports = { router, computeAnalytics };
