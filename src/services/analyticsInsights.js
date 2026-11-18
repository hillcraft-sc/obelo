// "What stands out" on Analytics: a few plain findings from the user's own data, each with a link
// to the items behind it. Rules produce the findings. When AI is set up, it only rewords them, and
// falls back to the rule wording if the reply is missing or doesn't match.

const ai = require('../lib/aiProvider');

const MAX_FINDINGS = 5;

function standsOut(a) {
  const findings = [];
  const { summary, routineStats } = a;
  const byRoutine = routineStats?.byRoutine || [];

  // Untimed routines can't be timed, so ask for a time of day (decision: routines get a time of day)
  const untimed = byRoutine.filter((r) => r.timeOfDay === 'anytime' && !r.specificTime);
  if (untimed.length > 0) {
    findings.push({
      tone: 'neutral',
      href: '/routines',
      text: `Set a time of day for ${untimed.length === 1 ? untimed[0].title : `${untimed.length} routines`} to see when you do ${untimed.length === 1 ? 'it' : 'them'}.`,
    });
  }

  for (const r of byRoutine) {
    if (r.rate !== null && r.expected >= 5 && r.rate < 50) {
      findings.push({
        tone: 'warn', href: `/routines/${r.id}`,
        text: `${r.title} was done on ${r.rate}% of its expected days in the last 30 days.`,
      });
    }
  }

  for (const r of byRoutine) {
    if (r.specificTimeRate !== null && r.timedSampleSize >= 5 && r.specificTimeRate < 50) {
      findings.push({
        tone: 'warn', href: `/routines/${r.id}`,
        text: `${r.title} is usually done late: on time ${r.specificTimeRate}% of the time.`,
      });
    }
  }

  for (const r of byRoutine) {
    if (r.streakCurrent >= 7) {
      findings.push({
        tone: 'good', href: `/routines/${r.id}`,
        text: `${r.title}: a ${r.streakCurrent}-day streak.`,
      });
    }
  }

  if (summary && summary.withDueCount >= 5 && summary.trueOnTimeRate !== null) {
    if (summary.trueOnTimeRate < 50) {
      findings.push({
        tone: 'warn', href: '/tasks',
        text: `Only ${summary.trueOnTimeRate}% of dated tasks and reminders were done on time.`,
      });
    } else if (summary.trueOnTimeRate >= 80) {
      findings.push({
        tone: 'good', href: '/tasks',
        text: `${summary.trueOnTimeRate}% of dated tasks and reminders were done on time.`,
      });
    }
  }

  if (findings.length === 0) {
    return [{ tone: 'neutral', href: null, text: 'Not enough data yet. This list fills in as you complete things.' }];
  }
  // Warnings first, then good news, then neutral prompts
  const rank = { warn: 0, good: 1, neutral: 2 };
  return findings.sort((x, y) => rank[x.tone] - rank[y.tone]).slice(0, MAX_FINDINGS);
}

// Rewords the rule findings with AI, when it's set up. Returns the same list, with the wording replaced.
async function refineWithAi(findings) {
  if (!ai.isConfigured() || findings.length === 0) return findings;
  try {
    const reply = await ai.complete({
      feature: 'chat',
      system: 'You rewrite short findings about a person\'s habits and tasks. Keep every number exactly as given. ' +
        'Be plain and kind, one sentence each. Do not add advice beyond what is given. ' +
        'Reply with only a JSON array of strings, in the same order and the same length as the input.',
      messages: [{ role: 'user', content: JSON.stringify(findings.map((f) => f.text)) }],
    });
    const match = String(reply || '').match(/\[[\s\S]*\]/);
    const texts = match ? JSON.parse(match[0]) : null;
    if (!Array.isArray(texts) || texts.length !== findings.length || texts.some((t) => typeof t !== 'string')) {
      return findings;
    }
    return findings.map((f, i) => ({ ...f, text: texts[i].trim() || f.text }));
  } catch {
    return findings;
  }
}

module.exports = { standsOut, refineWithAi };
