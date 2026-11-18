const prisma = require('../lib/prisma');

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function todayUtcStr() {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth()+1).padStart(2,'0')}-${String(now.getUTCDate()).padStart(2,'0')}`;
}

// Returns true if `date` is a day this routine is scheduled to run.
function isScheduledDay(routine, date) {
  const dow = date.getUTCDay();
  const dayName = DAYS[dow];
  switch (routine.frequency) {
    case 'daily':    return true;
    case 'weekdays': return dow >= 1 && dow <= 5;
    case 'weekends': return dow === 0 || dow === 6;
    case 'weekly':
    case 'custom':   return (routine.scheduleDays || []).includes(dayName);
    default:         return true;
  }
}

// Returns true if the routine had a scheduled occurrence strictly between
// fromStr and toStr (both 'YYYY-MM-DD') that isn't accounted for — i.e. a
// missed day. Used to decide whether two dates are part of the same streak.
function hasScheduledDayBetweenExclusive(routine, fromStr, toStr) {
  let cursor = new Date(fromStr + 'T00:00:00.000Z').getTime() + 86400000;
  const endMs = new Date(toStr + 'T00:00:00.000Z').getTime();
  while (cursor < endMs) {
    if (isScheduledDay(routine, new Date(cursor))) return true;
    cursor += 86400000;
  }
  return false;
}

async function recalcStreak(routine, todayStr) {
  const completions = await prisma.routineCompletion.findMany({
    where: { routineId: routine.id },
    orderBy: { completedDate: 'asc' },
  });

  const today = todayStr || todayUtcStr();

  if (completions.length === 0) {
    await prisma.$transaction([
      prisma.routine.update({ where: { id: routine.id }, data: { streakCurrent: 0 } }),
      prisma.routineStreakHistory.deleteMany({ where: { routineId: routine.id } }),
    ]);
    return 0;
  }

  const dates = completions.map(c => c.completedDate.toISOString().split('T')[0]);

  // Group completions into runs: a run continues as long as no scheduled
  // occurrence of the routine was missed between two consecutive completions.
  // (For a daily routine this is the same as "exactly 1 day apart"; for a
  // weekly/custom-schedule routine, consecutive scheduled dates can be days
  // apart and still form an unbroken run.)
  const runs = [];
  let runStart = dates[0];
  let runEnd = dates[0];
  let runLength = 1;
  for (let i = 1; i < dates.length; i++) {
    if (!hasScheduledDayBetweenExclusive(routine, dates[i - 1], dates[i])) {
      runEnd = dates[i];
      runLength++;
    } else {
      runs.push({ startDate: runStart, endDate: runEnd, length: runLength });
      runStart = dates[i];
      runEnd = dates[i];
      runLength = 1;
    }
  }
  runs.push({ startDate: runStart, endDate: runEnd, length: runLength });

  // Current streak: the last run is still alive if no scheduled occurrence
  // has been missed between its end and today — today itself doesn't count
  // against it, since there's still time left today to complete it.
  const lastRun = runs[runs.length - 1];
  const streak = !hasScheduledDayBetweenExclusive(routine, lastRun.endDate, today) ? lastRun.length : 0;
  const streakBest = Math.max(...runs.map(r => r.length));

  await prisma.$transaction([
    prisma.routineStreakHistory.deleteMany({ where: { routineId: routine.id } }),
    prisma.routineStreakHistory.createMany({
      data: runs.map((run, i) => ({
        routineId: routine.id,
        userId: routine.userId,
        startDate: new Date(run.startDate + 'T00:00:00.000Z'),
        endDate: new Date(run.endDate + 'T00:00:00.000Z'),
        length: run.length,
        isActive: i === runs.length - 1 && streak > 0,
      })),
    }),
    prisma.routine.update({ where: { id: routine.id }, data: { streakCurrent: streak, streakBest } }),
  ]);

  return streak;
}

module.exports = { DAYS, isScheduledDay, hasScheduledDayBetweenExclusive, recalcStreak };
