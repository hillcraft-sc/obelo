// Adds the CSRF token to every state-changing request the page makes.
(function () {
  var meta = document.querySelector('meta[name="csrf-token"]');
  var token = meta ? meta.content : '';
  if (!token) return;
  window.obeloCsrfToken = token;
  var SAFE = /^(GET|HEAD|OPTIONS)$/i;

  function sameOrigin(url) {
    try { return new URL(url, location.href).origin === location.origin; } catch (e) { return false; }
  }

  // fetch()
  var realFetch = window.fetch;
  window.fetch = function (input, init) {
    var method = ((init && init.method) || (input && input.method) || 'GET');
    var url = typeof input === 'string' ? input : (input && input.url);
    if (!SAFE.test(method) && sameOrigin(url)) {
      init = init || {};
      var h = new Headers(init.headers || (input && input.headers) || {});
      h.set('X-CSRF-Token', token);
      init.headers = h;
    }
    return realFetch.call(this, input, init);
  };

  // HTMX
  document.addEventListener('htmx:configRequest', function (e) {
    if (!SAFE.test(e.detail.verb)) e.detail.headers['X-CSRF-Token'] = token;
  });

  // Plain <form method="post">: hidden field (query string for uploads)
  function prepare(root) {
    var forms = (root.matches && root.matches('form') ? [root] : []).concat([].slice.call(root.querySelectorAll ? root.querySelectorAll('form') : []));
    forms.forEach(function (f) {
      if ((f.getAttribute('method') || 'get').toLowerCase() !== 'post') return;
      var action = f.getAttribute('action') || '';
      if (action && !sameOrigin(action)) return;
      if (f.enctype === 'multipart/form-data') {
        var u = new URL(action || location.href, location.href);
        u.searchParams.set('_csrf', token);
        f.setAttribute('action', u.pathname + u.search);
        return;
      }
      if (f.querySelector('input[name="_csrf"]')) return;
      var i = document.createElement('input');
      i.type = 'hidden'; i.name = '_csrf'; i.value = token;
      f.appendChild(i);
    });
  }
  document.addEventListener('DOMContentLoaded', function () { prepare(document); });
  document.addEventListener('htmx:afterSwap', function (e) { prepare(e.detail.target || document); });
  document.addEventListener('htmx:load', function (e) { prepare(e.target); });
  // Forms built or cloned by scripts: make sure they have it at submit time
  document.addEventListener('submit', function (e) { if (e.target && e.target.tagName === 'FORM') prepare(e.target); }, true);
})();
