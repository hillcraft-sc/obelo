const prisma = require('../lib/prisma');
const ai = require('../lib/aiProvider');

// Per-user daily message count (resets at server midnight)
const dailyCounts = {};
let countDate = new Date().toDateString();

function checkRateLimit(userId) {
  const today = new Date().toDateString();
  if (today !== countDate) { Object.keys(dailyCounts).forEach(k => delete dailyCounts[k]); countDate = today; }
  const limit = parseInt(process.env.AI_CHAT_DAILY_LIMIT || '50');
  const count = dailyCounts[userId] || 0;
  if (count >= limit) throw new Error(`Daily limit of ${limit} messages reached. Resets at midnight.`);
  dailyCounts[userId] = count + 1;
  return limit - dailyCounts[userId];
}

async function buildContext(userId, userTimezone) {
  const now = new Date();
  const tz  = userTimezone || 'America/New_York';
  const todayStr = now.toLocaleDateString('en-CA', { timeZone: tz });
  const todayStart = new Date(todayStr + 'T00:00:00.000Z');
  const todayEnd   = new Date(todayStart.getTime() + 86400000);
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 86400000);

  const [tasks, reminders, notes, calEvents, routines, doneTasks, doneReminders] = await Promise.all([
    prisma.task.findMany({
      where: { userId, status: { notIn: ['done', 'archived'] } },
      orderBy: [{ status: 'asc' }, { dueDate: 'asc' }],
      take: 40,
    }),
    prisma.reminder.findMany({
      where: { userId, completed: false, dueDate: { gte: thirtyDaysAgo } },
      orderBy: { dueDate: 'asc' },
      take: 20,
    }),
    // Private and locked notes never go to the AI provider
    prisma.note.findMany({
      where: { userId, private: false, locked: false },
      orderBy: { updatedAt: 'desc' },
      take: 30,
      select: { id: true, type: true, title: true, content: true, tags: true, author: true, source: true, createdAt: true, updatedAt: true, flaggedForReview: true },
    }),
    prisma.calendarEvent.findMany({
      where: { userId, startAt: { gte: todayStart, lt: new Date(todayEnd.getTime() + 7 * 86400000) } },
      orderBy: { startAt: 'asc' },
      take: 20,
      include: { source: { select: { name: true } } },
    }),
    prisma.routine.findMany({
      where: { userId, active: true },
      take: 20,
      include: {
        completions: {
          where: { completedDate: { gte: new Date(new Date(todayStr + 'T00:00:00.000Z').getTime() - 30 * 86400000) } },
          orderBy: { completedDate: 'desc' },
          select: { completedDate: true, completedAt: true },
        },
        streakHistory: {
          orderBy: { startDate: 'desc' },
          take: 10,
          select: { length: true, startDate: true, endDate: true, isActive: true },
        },
      },
    }),
    prisma.task.findMany({
      where: { userId, status: 'done', completedAt: { not: null, gte: thirtyDaysAgo } },
      select: { dueDate: true, dueTime: true, completedAt: true },
    }),
    prisma.reminder.findMany({
      where: { userId, completed: true, completedAt: { not: null, gte: thirtyDaysAgo } },
      select: { dueDate: true, dueTime: true, completedAt: true },
    }),
  ]);

  const lines = [];

  lines.push(`== TASKS (${tasks.length}) ==`);
  for (const t of tasks) {
    const due = t.dueDate ? ` [due ${t.dueDate.toISOString().split('T')[0]}]` : '';
    const time = t.dueTime ? ` @${t.dueTime}` : '';
    lines.push(`[${t.status}/${t.priority}] ${t.title}${due}${time}${t.tags.length ? ' tags:' + t.tags.join(',') : ''}`);
  }

  lines.push(`\n== REMINDERS (${reminders.length}) ==`);
  for (const r of reminders) {
    const due = r.dueDate ? r.dueDate.toISOString().split('T')[0] : 'no date';
    lines.push(`${r.title} [due ${due}${r.dueTime ? ' ' + r.dueTime : ''}]`);
  }

  lines.push(`\n== NOTES & JOURNAL (${notes.length} most recent) ==`);
  for (const n of notes) {
    const excerpt = n.content ? n.content.slice(0, 300).replace(/\n/g, ' ') : '';
    const meta = [n.type !== 'note' ? n.type : null, n.author ? `by ${n.author}` : null, n.source || null].filter(Boolean).join(', ');
    lines.push(`[${n.updatedAt.toISOString().split('T')[0]}] "${n.title}"${meta ? ` (${meta})` : ''}${n.tags.length ? ' #' + n.tags.join(' #') : ''}${n.flaggedForReview ? ' [flagged]' : ''}`);
    if (excerpt) lines.push(`  ${excerpt}${n.content && n.content.length > 300 ? '…' : ''}`);
  }

  lines.push(`\n== CALENDAR — NEXT 7 DAYS (${calEvents.length}) ==`);
  for (const e of calEvents) {
    const when = e.allDay ? e.startAt.toISOString().split('T')[0] : e.startAt.toLocaleString('en-US', { timeZone: tz, month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    lines.push(`${when} — ${e.title}${e.source ? ` (${e.source.name})` : ''}`);
  }

  lines.push(`\n== ACTIVE ROUTINES (completions last 30 days) ==`);
  for (const r of routines) {
    const dates = r.completions.map(c => c.completedDate.toISOString().split('T')[0]).join(', ');
    let extra = '';
    if (r.specificTime) {
      const timedComps = r.completions.filter(c => c.completedAt);
      if (timedComps.length > 0) {
        const [spH, spM] = r.specificTime.split(':').map(Number);
        const spMinutes = spH * 60 + spM;
        const onTimeCount = timedComps.filter(c => {
          const parts = new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: 'numeric', minute: 'numeric', hour12: false }).formatToParts(new Date(c.completedAt));
          const h = parseInt(parts.find(p => p.type === 'hour').value, 10) % 24;
          const m = parseInt(parts.find(p => p.type === 'minute').value, 10);
          return h * 60 + m <= spMinutes + 30;
        }).length;
        extra = ` specificTime:${r.specificTime} onTimeRate:${Math.round(onTimeCount / timedComps.length * 100)}% (${timedComps.length} timed completions)`;
      } else {
        extra = ` specificTime:${r.specificTime} (no timed completion data yet)`;
      }
    }
    const histStr = r.streakHistory && r.streakHistory.length > 0
      ? r.streakHistory.map(h => `${h.length}d(${h.startDate.toISOString().split('T')[0]}→${h.endDate.toISOString().split('T')[0]}${h.isActive ? '*' : ''})`).join(',')
      : 'none';
    lines.push(`${r.title} (${r.frequency}, ${r.timeOfDay}${extra}) streak:${r.streakCurrent}/best:${r.streakBest} streakHistory:[${histStr}] completed:[${dates || 'none'}]`);
  }

  // Completion analytics (last 30 days)
  const allDone = [...doneTasks, ...doneReminders];
  if (allDone.length > 0) {
    const withDue = allDone.filter(i => i.dueDate && i.completedAt);
    let trueOnTimeCount = 0, sameDayLateCount = 0;
    let lateSum = 0, lateCount = 0;
    for (const i of withDue) {
      const dueDateStr  = i.dueDate.toISOString().split('T')[0];
      const compDateStr = i.completedAt.toLocaleDateString('en-CA', { timeZone: tz });
      const diffDays = Math.round(
        (new Date(compDateStr + 'T00:00:00.000Z') - new Date(dueDateStr + 'T00:00:00.000Z')) / 86400000
      );
      if (diffDays < 0) { trueOnTimeCount++; continue; }
      if (diffDays === 0 && i.dueTime) {
        const [dueH, dueM] = i.dueTime.split(':').map(Number);
        const dueMinutes = dueH * 60 + dueM;
        const parts = new Intl.DateTimeFormat('en-US', {
          timeZone: tz, hour: 'numeric', minute: 'numeric', hour12: false,
        }).formatToParts(i.completedAt);
        const compH = parseInt(parts.find(p => p.type === 'hour').value, 10) % 24;
        const compM = parseInt(parts.find(p => p.type === 'minute').value, 10);
        const delta = compH * 60 + compM - dueMinutes;
        if (delta <= 30) { trueOnTimeCount++; } else { sameDayLateCount++; }
        continue;
      }
      if (diffDays === 0) { trueOnTimeCount++; continue; }
      lateSum += diffDays; lateCount++;
    }
    const trueOnTimeRate = withDue.length > 0 ? Math.round(trueOnTimeCount / withDue.length * 100) : null;
    const sameDayRate    = withDue.length > 0 ? Math.round((trueOnTimeCount + sameDayLateCount) / withDue.length * 100) : null;
    const avgLate        = lateCount > 0 ? Math.round(lateSum / lateCount * 10) / 10 : null;

    const dowCounts = [0,0,0,0,0,0,0];
    const DOW_ABBR = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    allDone.forEach(i => {
      const localDay = new Intl.DateTimeFormat('en-US', { timeZone: tz, weekday: 'short' }).format(new Date(i.completedAt));
      const idx = DOW_ABBR.indexOf(localDay);
      if (idx >= 0) dowCounts[idx]++;
    });
    const maxDow = Math.max(...dowCounts);
    const topDow = maxDow > 0 ? DOW_ABBR[dowCounts.indexOf(maxDow)] : null;

    lines.push(`\n== COMPLETION ANALYTICS (last 30 days) ==`);
    lines.push(`Completed: ${allDone.length} items (${withDue.length} with due dates, ${allDone.length - withDue.length} without)`);
    if (trueOnTimeRate !== null) lines.push(`True on-time rate: ${trueOnTimeRate}% (completed before or within 30 min of due time)`);
    if (sameDayRate !== null && sameDayRate !== trueOnTimeRate) lines.push(`Same-day rate: ${sameDayRate}% (completed on the correct calendar day)`);
    if (sameDayLateCount > 0) lines.push(`Same-day late: ${sameDayLateCount} item${sameDayLateCount !== 1 ? 's' : ''} completed on the right day but past the due time`);
    if (avgLate !== null) lines.push(`Avg days late (day-late items): ${avgLate}`);
    if (topDow) lines.push(`Most productive day: ${topDow} (${maxDow} completions)`);
  }

  return lines.join('\n');
}

// Optional cap for hosts running local models with small context windows (0/unset = no cap)
function capContext(context) {
  const max = parseInt(process.env.AI_CHAT_MAX_CONTEXT_CHARS) || 0;
  if (!max || context.length <= max) return context;
  console.warn(`[ai] chat context is ${context.length} chars; truncating to AI_CHAT_MAX_CONTEXT_CHARS=${max}`);
  const cut = context.lastIndexOf('\n', max);
  return context.slice(0, cut > 0 ? cut : max) + '\n[Remaining data omitted to fit the model\'s context limit.]';
}

// The chat only reads. Without this rule a model will happily answer "go ahead and set it up" with
// "Done!" and a list of things it never created, so the rule says plainly what it cannot do.
const READ_ONLY_RULE = "You can only read the user's data. You cannot create, change, complete, move or delete anything: no tasks, routines, reminders, notes, lists, bookmarks or calendar events. If the user asks you to set something up or change something, do not say or imply that you did. Say that you can't do that, then give the exact details (title, day, time, how often) so they can add it themselves in Obelo.";

function buildSystemPrompt(displayName, dateStr, context) {
  return `You are a personal assistant inside Obelo, a productivity app belonging to ${displayName}. You have access to their personal data shown below. Answer questions using only this data — do not hallucinate. When referencing entries, be specific (quote titles, dates). Be concise and conversational. If the data doesn't contain enough to answer, say so.

${READ_ONLY_RULE}

Today: ${dateStr}

${context}`;
}

async function chat(messages, userId, user) {
  if (!ai.isConfigured()) throw new Error("AI isn't configured on this server.");
  const remaining = checkRateLimit(userId);
  const context   = capContext(await buildContext(userId, user.timezone));

  const now = new Date();
  const dateStr = now.toLocaleString('en-US', {
    timeZone: user.timezone || 'America/New_York',
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
    hour: 'numeric', minute: '2-digit',
  });

  const systemPrompt = buildSystemPrompt(user.displayName, dateStr, context);

  const reply = await ai.complete({ feature: 'chat', system: systemPrompt, messages });

  return {
    reply:     reply || '(no response)',
    remaining,
  };
}

module.exports = { chat, checkRateLimit, buildSystemPrompt, READ_ONLY_RULE };
