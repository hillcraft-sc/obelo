// The SSO settings are OIDC_*; the older AUTHENTIK_* names still work.
const { describe, it, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const oidc = require('../../src/services/oidcService');

const NAMES = ['ISSUER', 'CLIENT_ID', 'CLIENT_SECRET', 'REDIRECT_URI'].flatMap(k => [`OIDC_${k}`, `AUTHENTIK_${k}`]);
const saved = Object.fromEntries(NAMES.map(n => [n, process.env[n]]));
function setEnv(values) {
  for (const n of NAMES) delete process.env[n];
  Object.assign(process.env, values);
}
afterEach(() => {
  for (const n of NAMES) { if (saved[n] === undefined) delete process.env[n]; else process.env[n] = saved[n]; }
});

describe('SSO setting names', () => {
  it('is off when nothing is set', () => {
    setEnv({});
    assert.equal(oidc.isConfigured(), false);
    assert.deepEqual(oidc.legacyNamesInUse(), []);
  });

  it('works with the new names and has nothing to warn about', () => {
    setEnv({ OIDC_ISSUER: 'https://sso.invalid/', OIDC_CLIENT_ID: 'a', OIDC_CLIENT_SECRET: 'b' });
    assert.equal(oidc.isConfigured(), true);
    assert.deepEqual(oidc.legacyNamesInUse(), []);
  });

  it('still works with the old names, and lists them for the warning', () => {
    setEnv({ AUTHENTIK_ISSUER: 'https://sso.invalid/', AUTHENTIK_CLIENT_ID: 'a', AUTHENTIK_CLIENT_SECRET: 'b' });
    assert.equal(oidc.isConfigured(), true);
    assert.deepEqual(oidc.legacyNamesInUse(), ['AUTHENTIK_ISSUER', 'AUTHENTIK_CLIENT_ID', 'AUTHENTIK_CLIENT_SECRET']);
  });

  it('prefers the new name when both are set, and does not warn about a name that is replaced', () => {
    setEnv({ OIDC_REDIRECT_URI: 'https://new.invalid/cb', AUTHENTIK_REDIRECT_URI: 'https://old.invalid/cb' });
    assert.equal(oidc.getRedirectUri(), 'https://new.invalid/cb');
    assert.deepEqual(oidc.legacyNamesInUse(), []);
  });

  it('falls back to the old redirect name', () => {
    setEnv({ AUTHENTIK_REDIRECT_URI: 'https://old.invalid/cb' });
    assert.equal(oidc.getRedirectUri(), 'https://old.invalid/cb');
  });
});
