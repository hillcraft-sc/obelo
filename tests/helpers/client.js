// A tiny HTTP client that keeps cookies, like a browser or the app does.
// Each client gets its own IP (through X-Forwarded-For) so rate limits don't leak between tests.

let nextIp = 10;
const freshIp = () => `10.1.${Math.floor(nextIp / 250)}.${(nextIp++ % 250) + 1}`;

class Client {
  constructor(base, { ip, https = false, app = false } = {}) {
    this.base = base;
    this.ip = ip || freshIp();
    this.https = https;   // pretend a TLS-terminating proxy is in front
    this.app = app;       // send the header the apps send
    this.jar = new Map();
  }

  // The page token for the current session, read from a public page like a browser would.
  // Sent on web (non-API) writes unless a test passes its own headers or sets csrf: false.
  async csrfToken() {
    const sid = this.jar.get('connect.sid') || '';
    if (this._csrf && this._csrf.sid === sid) return this._csrf.token;
    const h = { 'X-Forwarded-For': this.ip };
    if (this.https) h['X-Forwarded-Proto'] = 'https';
    if (sid) h.Cookie = [...this.jar].map(([k, v]) => `${k}=${v}`).join('; ');
    const res = await fetch(this.base + '/privacy', { headers: h, redirect: 'manual' });
    this._storeCookies(res);
    const m = /name="csrf-token" content="([0-9a-f]+)"/.exec(await res.text());
    this._csrf = { sid: this.jar.get('connect.sid') || '', token: m ? m[1] : '' };
    return this._csrf.token;
  }

  _storeCookies(res) {
    for (const c of res.headers.getSetCookie?.() || []) {
      const [pair] = c.split(';');
      const i = pair.indexOf('=');
      const name = pair.slice(0, i), value = pair.slice(i + 1);
      if (/;\s*expires=Thu, 01 Jan 1970/i.test(c) || value === '') this.jar.delete(name); else this.jar.set(name, value);
    }
  }

  async request(method, path, { form, json, headers = {}, csrf = true } = {}) {
    const h = { 'X-Forwarded-For': this.ip, ...headers };
    if (csrf && method !== 'GET' && !path.startsWith('/api/v1') && !h['X-CSRF-Token']) h['X-CSRF-Token'] = await this.csrfToken();
    if (this.https) h['X-Forwarded-Proto'] = 'https';
    if (this.app || path.startsWith('/api/v1')) h['X-Obelo-Client'] = 'test';
    if (this.jar.size) h.Cookie = [...this.jar].map(([k, v]) => `${k}=${v}`).join('; ');
    let body;
    if (form) { h['Content-Type'] = 'application/x-www-form-urlencoded'; body = new URLSearchParams(form).toString(); }
    if (json) { h['Content-Type'] = 'application/json'; body = JSON.stringify(json); }
    const res = await fetch(this.base + path, { method, headers: h, body, redirect: 'manual' });
    for (const c of res.headers.getSetCookie?.() || []) {
      const [pair] = c.split(';');
      const i = pair.indexOf('=');
      const name = pair.slice(0, i), value = pair.slice(i + 1);
      if (/;\s*expires=Thu, 01 Jan 1970/i.test(c) || value === '') this.jar.delete(name); else this.jar.set(name, value);
    }
    const text = await res.text();
    return {
      status: res.status,
      location: res.headers.get('location'),
      text,
      json: () => JSON.parse(text),
      // a session other than the signed-out one the page token was read from
      hasCookie: () => this.jar.has('connect.sid') && this.jar.get('connect.sid') !== this._csrf?.sid,
    };
  }

  // multipart upload, like the apps and the note editor send
  async upload(path, field, buffer, filename = 'a.png', type = 'image/png') {
    const h = { 'X-Forwarded-For': this.ip };
    if (!path.startsWith('/api/v1')) h['X-CSRF-Token'] = await this.csrfToken();
    if (path.startsWith('/api/v1')) h['X-Obelo-Client'] = 'test';
    if (this.jar.size) h.Cookie = [...this.jar].map(([k, v]) => `${k}=${v}`).join('; ');
    const body = new FormData();
    body.append(field, new Blob([buffer], { type }), filename);
    const res = await fetch(this.base + path, { method: 'POST', headers: h, body, redirect: 'manual' });
    const text = await res.text();
    return { status: res.status, location: res.headers.get('location'), text, json: () => JSON.parse(text) };
  }

  hasSession() { return this.jar.has('connect.sid'); }

  get(path, opts) { return this.request('GET', path, opts); }
  post(path, opts) { return this.request('POST', path, opts); }
}

module.exports = { Client };
