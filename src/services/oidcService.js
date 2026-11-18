let _discovery = null;

// Settings are OIDC_*. The older AUTHENTIK_* names are still read when the new one is empty.
const KEYS = ['ISSUER', 'CLIENT_ID', 'CLIENT_SECRET', 'REDIRECT_URI'];
function setting(key) {
  return process.env[`OIDC_${key}`] || process.env[`AUTHENTIK_${key}`] || '';
}

// Old names that are set and not yet replaced by the new name (for a start-up warning).
function legacyNamesInUse() {
  return KEYS.filter(k => process.env[`AUTHENTIK_${k}`] && !process.env[`OIDC_${k}`])
    .map(k => `AUTHENTIK_${k}`);
}

function isConfigured() {
  return !!(
    setting('ISSUER') &&
    setting('CLIENT_ID') &&
    setting('CLIENT_SECRET')
  );
}

function getRedirectUri() {
  return (
    setting('REDIRECT_URI') ||
    `${process.env.APP_URL || 'http://localhost:3000'}/auth/oidc/callback`
  );
}

async function getDiscovery() {
  if (_discovery) return _discovery;
  const base = setting('ISSUER').replace(/\/$/, '');
  const res = await fetch(`${base}/.well-known/openid-configuration`);
  if (!res.ok) throw new Error(`OIDC discovery failed: ${res.status} ${res.statusText}`);
  _discovery = await res.json();
  return _discovery;
}

async function buildAuthUrl(state, nonce) {
  const d = await getDiscovery();
  const params = new URLSearchParams({
    client_id:     setting('CLIENT_ID'),
    redirect_uri:  getRedirectUri(),
    response_type: 'code',
    scope:         'openid email profile',
    state,
    nonce,
  });
  return `${d.authorization_endpoint}?${params}`;
}

async function exchangeCode(code) {
  const d = await getDiscovery();
  const res = await fetch(d.token_endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type:    'authorization_code',
      code,
      redirect_uri:  getRedirectUri(),
      client_id:     setting('CLIENT_ID'),
      client_secret: setting('CLIENT_SECRET'),
    }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Token exchange failed: ${res.status} ${body}`);
  }
  return res.json();
}

async function getUserInfo(accessToken) {
  const d = await getDiscovery();
  const res = await fetch(d.userinfo_endpoint, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`Userinfo request failed: ${res.status}`);
  return res.json();
}

// Reset cached discovery (useful if issuer changes at runtime)
function reset() { _discovery = null; }

module.exports = { isConfigured, getRedirectUri, getDiscovery, buildAuthUrl, exchangeCode, getUserInfo, reset, legacyNamesInUse };
