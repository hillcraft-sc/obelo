const log = require('./logService');
const notifyMode = require('../lib/notifyMode');

async function send(userKey, { title, message, url, urlTitle, priority = 0 }, { force = false } = {}) {
  if (!process.env.PUSHOVER_APP_TOKEN || !userKey) return null;
  if (!force && notifyMode.isDryRun()) {
    log.info('pushover', `Dry run: would send "${title || 'Obelo'}"`);
    return { status: 1, dryRun: true };
  }

  const body = new URLSearchParams({
    token: process.env.PUSHOVER_APP_TOKEN,
    user: userKey,
    title: title || 'Obelo',
    message: message || ' ',
    priority: String(priority),
    ...(url ? { url } : {}),
    ...(urlTitle ? { url_title: urlTitle } : {}),
  });

  try {
    const res = await fetch('https://api.pushover.net/1/messages.json', {
      method: 'POST',
      body,
    });
    return res.json();
  } catch (err) {
    console.error('[pushover] send failed:', err.message);
    return null;
  }
}

module.exports = { send };
