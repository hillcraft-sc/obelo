const crypto = require('crypto');
const log = require('./logService');
const notifyMode = require('../lib/notifyMode');

// ntfy (https://ntfy.sh) — free, open-source push notifications, usually self-hosted next to
// Obelo. Each user subscribes to their own randomly named topic in the ntfy app.
// NTFY_URL is the server's public base URL; NTFY_TOKEN is only needed if the server
// requires authentication to publish.

function serverUrl() {
  return (process.env.NTFY_URL || '').trim().replace(/\/+$/, '');
}

function isConfigured() {
  return !!serverUrl();
}

// Topics are effectively passwords on an open ntfy server, so make them unguessable
function newTopic() {
  return 'vt-' + crypto.randomBytes(15).toString('base64url');
}

// Pushover-style priority (0 normal, 1 high) → ntfy priority (3 default, 4 high)
async function send(topic, { title, message, url, urlTitle, priority = 0 }, { force = false } = {}) {
  if (!isConfigured() || !topic) return false;
  if (!force && notifyMode.isDryRun()) {
    log.info('ntfy', `Dry run: would send "${title || 'Obelo'}"`);
    return true;
  }
  const body = {
    topic,
    title:    title || 'Obelo',
    message:  message || ' ',
    priority: priority >= 1 ? 4 : 3,
    ...(url && { click: url, actions: [{ action: 'view', label: urlTitle || 'Open', url, clear: true }] }),
  };
  const headers = { 'Content-Type': 'application/json' };
  const token = (process.env.NTFY_TOKEN || '').trim();
  if (token) headers.Authorization = `Bearer ${token}`;

  try {
    const res = await fetch(serverUrl(), { method: 'POST', headers, body: JSON.stringify(body) });
    if (!res.ok) {
      log.error('ntfy', `Publish failed (${res.status}): ${(await res.text()).slice(0, 200)}`);
      return false;
    }
    return true;
  } catch (err) {
    log.error('ntfy', `Publish failed: ${err.message}`);
    return false;
  }
}

module.exports = { send, isConfigured, newTopic, serverUrl };
