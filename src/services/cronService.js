const cron = require('node-cron');
const prisma = require('../lib/prisma');
const pushover = require('./pushoverService');
const ntfy = require('./ntfyService');
const email = require('./emailService');
const caldav = require('./caldavService');
const log = require('./logService');
const { recalcStreak } = require('./routineStreaks');
const { fmtHHMM, prefsHour12 } = require('../lib/timeFormat');

// Send a notification via all channels configured for this pref
async function sendViaChannels(user, userPrefs, channels, { title, message, url, urlTitle, priority }) {
  const ch = channels || { pushover: true };

  if (ch.pushover && userPrefs.pushoverEnabled && userPrefs.pushoverKey) {
    await pushover.send(userPrefs.pushoverKey, { title, message, url, urlTitle, priority }).catch(e => {
      log.error('cron', `Pushover send failed for user ${user.id}: ${e.message}`);
    });
  }
  if (ch.ntfy && userPrefs.ntfyEnabled && userPrefs.ntfyTopic) {
    await ntfy.send(userPrefs.ntfyTopic, { title, message, url, urlTitle, priority });
  }
  const emailTo = userPrefs.notifEmail || user.email;
  if (ch.email && emailTo) {
    const body = url ? `${message}\n\n${url}` : message;
    await email.sendEmail(emailTo, title, body);
  }
}

async function checkDueReminders(at) {
  // reminderAt values sit exactly on the minute; fire those that fall in minute `at`
  const windowStart = at;
  const windowEnd   = new Date(at.getTime() + 60 * 1000);

  let reminders;
  try {
    reminders = await prisma.reminder.findMany({
      where: {
        completed: false,
        reminderAt: { gte: windowStart, lt: windowEnd },
      },
      include: {
        user: {
          select: {
            email: true, preferences: true,
            notificationPrefs: { where: { type: 'task_due' } },
          },
        },
      },
    });
  } catch (err) {
    log.error('cron', `Reminder query failed: ${err.message}`);
    return;
  }

  for (const reminder of reminders) {
    const prefs = reminder.user?.preferences || {};
    const dueStr = reminder.dueDate
      ? new Date(reminder.dueDate).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' })
      : '';
    const timeStr = fmtHHMM(reminder.dueTime, prefsHour12(prefs));
    const detail = [dueStr, timeStr].filter(Boolean).join(' at ');
    const url = `${process.env.APP_URL || 'http://localhost:3000'}/reminders/${reminder.id}`;

    const push = {
      title: reminder.title,
      message: detail || reminder.notes || 'Reminder',
      url,
      urlTitle: 'View reminder',
      priority: reminder.priority === 'high' ? 1 : 0,
    };
    if (prefs.pushoverEnabled && prefs.pushoverKey) await pushover.send(prefs.pushoverKey, push);
    if (prefs.ntfyEnabled && prefs.ntfyTopic) await ntfy.send(prefs.ntfyTopic, push);

    // Email follows the "Task & reminder alerts" email channel in Settings → Notifications
    const duePref = reminder.user?.notificationPrefs?.[0];
    const emailTo = prefs.notifEmail || reminder.user?.email;
    if (duePref?.enabled && duePref.channels?.email && emailTo) {
      const body = [detail, reminder.notes].filter(Boolean).join('\n\n');
      await email.sendEmail(emailTo, `Reminder: ${reminder.title}`, `${body || 'Reminder'}\n\n${url}`);
    }
  }

  if (reminders.length > 0) {
    log.info('cron', `Sent ${reminders.length} reminder notification(s)`);
  }
}

async function checkDueRoutines(at) {
  const now = at;

  let routines;
  try {
    routines = await prisma.routine.findMany({
      where: { active: true, notify: true },
      include: { user: { select: { timezone: true, preferences: true } } },
    });
  } catch (err) {
    log.error('cron', `Routine query failed: ${err.message}`);
    return;
  }

  let notified = 0;
  for (const routine of routines) {
    const tz = routine.user?.timezone || 'UTC';

    // Compute user's local HH:MM and day-of-week in their timezone
    const tzParts = new Intl.DateTimeFormat('en-US', {
      timeZone: tz, weekday: 'short',
      hour: '2-digit', minute: '2-digit', hour12: false,
    }).formatToParts(now).reduce((a, p) => { a[p.type] = p.value; return a; }, {});
    const timeStr = tzParts.hour === '24' ? `00:${tzParts.minute}` : `${tzParts.hour}:${tzParts.minute}`;
    if (timeStr !== routine.specificTime) continue;

    const DAY_NAMES = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    const localDow = DAY_NAMES.indexOf(tzParts.weekday);
    const dayName  = DAY_NAMES[localDow >= 0 ? localDow : 0];

    const isDue = (() => {
      switch (routine.frequency) {
        case 'daily':    return true;
        case 'weekdays': return localDow >= 1 && localDow <= 5;
        case 'weekends': return localDow === 0 || localDow === 6;
        case 'weekly':
        case 'custom':   return (routine.scheduleDays || []).includes(dayName);
        default:         return true;
      }
    })();
    if (!isDue) continue;

    // Use user's local date — completions are stored as the user's local UTC-midnight date
    const userTodayStr = now.toLocaleDateString('en-CA', { timeZone: tz });
    const today = new Date(userTodayStr + 'T00:00:00.000Z');
    // A routine that has not started yet must not send reminders (the routines page already hides it)
    if (routine.startDate && routine.startDate.toISOString().slice(0, 10) > userTodayStr) continue;
    const done = await prisma.routineCompletion.findFirst({
      where: { routineId: routine.id, completedDate: today },
    });
    if (done) continue;

    const prefs = routine.user?.preferences || {};
    const usePushover = prefs.pushoverEnabled && prefs.pushoverKey;
    const useNtfy     = prefs.ntfyEnabled && prefs.ntfyTopic;
    if (!usePushover && !useNtfy) continue;

    const push = {
      title: `Routine: ${routine.title}`,
      message: routine.description || 'Time to check off your routine!',
      url: `${process.env.APP_URL || 'http://localhost:3000'}/routines/${routine.id}`,
      urlTitle: 'Mark complete',
    };
    if (usePushover) await pushover.send(prefs.pushoverKey, push);
    if (useNtfy) await ntfy.send(prefs.ntfyTopic, push);
    notified++;
  }

  if (notified > 0) {
    log.info('cron', `Sent ${notified} routine notification(s)`);
  }
}

async function sendDailyDigests(at) {
  const now = at;

  const prefs = await prisma.notificationPref.findMany({
    where: { type: 'daily_digest', enabled: true },
    include: { user: { select: { id: true, email: true, displayName: true, timezone: true, preferences: true } } },
  }).catch(err => { console.error('[cron] digest pref query failed:', err.message); return []; });

  for (const pref of prefs) {
    const user = pref.user;
    const userPrefs = user.preferences || {};

    const tz = user.timezone || 'America/New_York';
    const userTimeRaw = now.toLocaleTimeString('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false });
    const currentTime = userTimeRaw === '24:00' ? '00:00' : userTimeRaw;
    if (currentTime !== pref.sendTime) continue;

    const todayStr = now.toLocaleDateString('en-CA', { timeZone: tz });
    const dayStart = new Date(todayStr + 'T00:00:00.000Z');
    const dayEnd   = new Date(dayStart.getTime() + 86400000);

    const [tasks, events] = await Promise.all([
      prisma.task.findMany({
        where: { userId: user.id, status: { notIn: ['done', 'archived'] }, priority: { in: ['high', 'medium'] } },
        orderBy: [{ priority: 'asc' }, { dueDate: 'asc' }],
        take: 5,
      }),
      prisma.calendarEvent.findMany({
        where: { userId: user.id, startAt: { gte: dayStart, lt: dayEnd } },
        orderBy: [{ allDay: 'desc' }, { startAt: 'asc' }],
        take: 5,
      }),
    ]);

    const lines = [];
    if (events.length) {
      lines.push('📅 Today:');
      for (const e of events) {
        const time = e.allDay ? 'All day' : e.startAt.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: tz, hour12: prefsHour12(userPrefs) });
        lines.push(`  ${time} — ${e.title}`);
      }
    }
    if (tasks.length) {
      lines.push('✅ Top tasks:');
      for (const t of tasks) {
        const due = t.dueDate ? ` (due ${t.dueDate.toISOString().split('T')[0]})` : '';
        lines.push(`  • ${t.title}${due}`);
      }
    }
    if (!lines.length) lines.push('Nothing urgent today — enjoy the day!');

    await sendViaChannels(user, userPrefs, pref.channels, {
      title:    `Good morning, ${user.displayName}`,
      message:  lines.join('\n'),
      url:      `${process.env.APP_URL || 'http://localhost:3000'}/`,
      urlTitle: 'Open Obelo',
    });
    log.info('cron', `Daily digest sent to user ${user.id}`);
  }
}

async function sendSlippingTasksAlert(at) {
  const now = at;

  const prefs = await prisma.notificationPref.findMany({
    where: { type: 'slipping_tasks', enabled: true },
    include: { user: { select: { id: true, email: true, displayName: true, timezone: true, preferences: true } } },
  }).catch(err => { console.error('[cron] slipping pref query failed:', err.message); return []; });

  for (const pref of prefs) {
    const user = pref.user;
    const userPrefs = user.preferences || {};

    const tz = user.timezone || 'America/New_York';
    const userTimeRaw = now.toLocaleTimeString('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false });
    const currentTime = userTimeRaw === '24:00' ? '00:00' : userTimeRaw;
    if (currentTime !== pref.sendTime) continue;
    // Weekly on Monday in the user's timezone (server-UTC Monday misses evening send times in the Americas)
    if (now.toLocaleDateString('en-US', { timeZone: tz, weekday: 'short' }) !== 'Mon') continue;

    const overdue = await prisma.task.findMany({
      where: {
        userId: user.id,
        status: { notIn: ['done', 'archived'] },
        dueDate: { lt: now },
      },
      orderBy: { dueDate: 'asc' },
      take: 8,
    });

    if (!overdue.length) continue;

    const lines = [`${overdue.length} task${overdue.length > 1 ? 's' : ''} slipping:`];
    for (const t of overdue) {
      const due = t.dueDate.toISOString().split('T')[0];
      lines.push(`  • ${t.title} (was due ${due})`);
    }

    await sendViaChannels(user, userPrefs, pref.channels, {
      title:    'Slipping tasks',
      message:  lines.join('\n'),
      url:      `${process.env.APP_URL || 'http://localhost:3000'}/tasks`,
      urlTitle: 'View tasks',
      priority: 1,
    });
    log.info('cron', `Slipping tasks alert sent to user ${user.id}`);
  }
}

// Format a Date as HH:MM in a given IANA timezone
function toHHMM(date, tz) {
  const s = date.toLocaleTimeString('en-US', {
    timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false,
  });
  return s === '24:00' ? '00:00' : s;
}

async function checkTaskAndReminderAlerts(at) {
  const now = at;
  const appUrl = process.env.APP_URL || 'http://localhost:3000';

  let enabledPrefs;
  try {
    enabledPrefs = await prisma.notificationPref.findMany({
      where: { type: 'task_due', enabled: true },
      include: { user: { select: { id: true, email: true, displayName: true, timezone: true, preferences: true } } },
    });
  } catch (err) {
    log.error('cron', `task_due pref query failed: ${err.message}`);
    return;
  }

  for (const pref of enabledPrefs) {
    const user = pref.user;
    const prefs = user.preferences || {};
    const tz = user.timezone || 'America/New_York';

    // Local time strings at: now, +15 min, and -5 min (overdue grace)
    const soon = new Date(now.getTime() + 15 * 60 * 1000);
    const past = new Date(now.getTime() - 5  * 60 * 1000);
    const nowHHMM  = toHHMM(now,  tz);
    const soonHHMM = toHHMM(soon, tz);
    const pastHHMM = toHHMM(past, tz);

    // UTC day-start/end boundaries for today, soon-day, and past-day
    function dayBounds(d) {
      const dateStr = d.toLocaleDateString('en-CA', { timeZone: tz });
      const start   = new Date(dateStr + 'T00:00:00.000Z');
      return { start, end: new Date(start.getTime() + 86400000) };
    }
    const todayBounds = dayBounds(now);
    const soonBounds  = dayBounds(soon);
    const pastBounds  = dayBounds(past);

    // Reminder windows: the whole minute 15 min ahead / 5 min behind `at`
    const r15Start = new Date(now.getTime() + 15 * 60 * 1000);
    const r15End   = new Date(now.getTime() + 16 * 60 * 1000);
    const rOvStart = new Date(now.getTime() - 5  * 60 * 1000);
    const rOvEnd   = new Date(now.getTime() - 4  * 60 * 1000);

    let results;
    try {
      results = await Promise.all([
        // Tasks due in 15 min
        prisma.task.findMany({ where: {
          userId: user.id, status: { notIn: ['done','archived'] },
          dueDate: { gte: soonBounds.start, lt: soonBounds.end }, dueTime: soonHHMM,
        }}),
        // Tasks due right now
        prisma.task.findMany({ where: {
          userId: user.id, status: { notIn: ['done','archived'] },
          dueDate: { gte: todayBounds.start, lt: todayBounds.end }, dueTime: nowHHMM,
        }}),
        // Tasks overdue by ~5 min (5-min grace, fires once)
        prisma.task.findMany({ where: {
          userId: user.id, status: { notIn: ['done','archived'] },
          dueDate: { gte: pastBounds.start, lt: pastBounds.end }, dueTime: pastHHMM,
        }}),
        // Reminders firing in ~15 min
        prisma.reminder.findMany({ where: {
          userId: user.id, completed: false,
          reminderAt: { gte: r15Start, lt: r15End },
        }}),
        // Reminders overdue by ~5-6 min
        prisma.reminder.findMany({ where: {
          userId: user.id, completed: false,
          reminderAt: { gte: rOvStart, lt: rOvEnd },
        }}),
      ]);
    } catch (err) {
      log.error('cron', `task_due query failed for user ${user.id}: ${err.message}`);
      continue;
    }

    const [tasksSoon, tasksNow, tasksOverdue, remindersSoon, remindersOverdue] = results;

    for (const task of tasksSoon) {
      await sendViaChannels(user, prefs, pref.channels, {
        title:    `Due in 15 min: ${task.title}`,
        message:  `Scheduled for ${fmtHHMM(soonHHMM, prefsHour12(prefs))}`,
        url:      `${appUrl}/tasks`,
        urlTitle: 'View tasks',
        priority: 0,
      });
    }
    for (const task of tasksNow) {
      await sendViaChannels(user, prefs, pref.channels, {
        title:    task.title,
        message:  `Due now${task.notes ? ' — ' + task.notes.slice(0, 80) : ''}`,
        url:      `${appUrl}/tasks`,
        urlTitle: 'View tasks',
        priority: task.priority === 'high' ? 1 : 0,
      });
    }
    for (const task of tasksOverdue) {
      await sendViaChannels(user, prefs, pref.channels, {
        title:    `Missed: ${task.title}`,
        message:  `Was due at ${fmtHHMM(pastHHMM, prefsHour12(prefs))} — mark done or reschedule`,
        url:      `${appUrl}/tasks`,
        urlTitle: 'View tasks',
        priority: task.priority === 'high' ? 1 : 0,
      });
    }
    for (const rem of remindersSoon) {
      const atStr = rem.reminderAt
        ? rem.reminderAt.toLocaleTimeString('en-US', { timeZone: tz, hour: 'numeric', minute: '2-digit', hour12: prefsHour12(prefs) })
        : '';
      await sendViaChannels(user, prefs, pref.channels, {
        title:    `Reminder in 15 min: ${rem.title}`,
        message:  atStr ? `Coming up at ${atStr}` : (rem.notes || 'Upcoming reminder'),
        url:      `${appUrl}/reminders/${rem.id}`,
        urlTitle: 'View reminder',
        priority: 0,
      });
    }
    for (const rem of remindersOverdue) {
      await sendViaChannels(user, prefs, pref.channels, {
        title:    `Missed reminder: ${rem.title}`,
        message:  rem.notes || 'This reminder was due a few minutes ago',
        url:      `${appUrl}/reminders/${rem.id}`,
        urlTitle: 'View reminder',
        priority: rem.priority === 'high' ? 1 : 0,
      });
    }

    const sent = tasksSoon.length + tasksNow.length + tasksOverdue.length +
                 remindersSoon.length + remindersOverdue.length;
    if (sent > 0) {
      log.info('cron', `task_due: sent ${sent} alert(s) for user ${user.id}`);
    }
  }
}

// Streaks are otherwise only recalculated when a routine is ticked, so a missed day would
// leave the old streak showing until the next completion. Runs hourly in each user's timezone.
async function refreshRoutineStreaks() {
  let routines;
  try {
    routines = await prisma.routine.findMany({
      where: { active: true },
      include: { user: { select: { timezone: true } } },
    });
  } catch (err) {
    log.error('cron', `Routine streak query failed: ${err.message}`);
    return;
  }
  for (const routine of routines) {
    try {
      const today = new Date().toLocaleDateString('en-CA', { timeZone: routine.user?.timezone || 'UTC' });
      await recalcStreak(routine, today);
    } catch (err) {
      log.error('cron', `Streak refresh failed for routine ${routine.id}: ${err.message}`);
    }
  }
}

async function syncAllCalendars() {
  let users;
  try {
    users = await prisma.user.findMany({ select: { id: true } });
  } catch (err) {
    log.error('cron', `Calendar sync user query failed: ${err.message}`);
    return;
  }
  for (const user of users) {
    try {
      await caldav.syncAllForUser(user.id);
    } catch (err) {
      log.error('cron', `Calendar sync failed for user ${user.id}: ${err.message}`);
    }
  }
}

// ── Minute scheduler with catch-up ────────────────────────────────────────────
// The time-based alerts above each handle one minute. The last minute processed is stored
// in system_settings, so after a restart (e.g. a deploy) the minutes that were missed are
// processed too, instead of their notifications being silently skipped. Catch-up is capped
// so a long outage doesn't unleash a burst of stale alerts.

const WATERMARK_KEY    = 'scheduler_last_minute';
const CATCH_UP_MINUTES = 15;
const MINUTE           = 60 * 1000;
let ticking = false;

async function runMinuteChecks(at) {
  const checks = [checkDueReminders, checkDueRoutines, checkTaskAndReminderAlerts, sendDailyDigests, sendSlippingTasksAlert];
  for (const check of checks) {
    try {
      await check(at);
    } catch (err) {
      log.error('cron', `${check.name} failed for ${at.toISOString()}: ${err.message}`);
    }
  }
}

async function tick() {
  if (ticking) return;             // a slow run is still going; its successor catches up
  ticking = true;
  try {
    const current = Math.floor(Date.now() / MINUTE) * MINUTE;
    const saved   = await prisma.systemSetting.findUnique({ where: { key: WATERMARK_KEY } });
    const last    = saved ? Date.parse(saved.value) : NaN;

    let first = Number.isFinite(last) ? last + MINUTE : current;
    const earliest = current - (CATCH_UP_MINUTES - 1) * MINUTE;
    if (first < earliest) {
      log.warn('cron', `Scheduler was down for ${Math.round((current - first) / MINUTE)} min; notifications from before ${new Date(earliest).toISOString()} were skipped`);
      first = earliest;
    }
    if (first < current) {
      log.info('cron', `Catching up ${Math.round((current - first) / MINUTE)} missed minute(s) of notifications`);
    }

    for (let m = first; m <= current; m += MINUTE) {
      // Advance the watermark before sending, so a crash mid-minute can't cause duplicates
      await prisma.systemSetting.upsert({
        where:  { key: WATERMARK_KEY },
        update: { value: new Date(m).toISOString() },
        create: { key: WATERMARK_KEY, value: new Date(m).toISOString() },
      });
      await runMinuteChecks(new Date(m));
    }
  } catch (err) {
    log.error('cron', `Scheduler tick failed: ${err.message}`);
  } finally {
    ticking = false;
  }
}

function start() {
  cron.schedule('* * * * *', tick);
  tick();                          // catch up right away after a restart
  cron.schedule('*/15 * * * *', async () => {
    await syncAllCalendars();
  });
  cron.schedule('5 * * * *', refreshRoutineStreaks);
  refreshRoutineStreaks();
  log.info('cron', 'Scheduler started');
}

module.exports = { start, tick };
