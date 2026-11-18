// Obelo service worker — network-first for CSS, JS and pages (cache as offline fallback),
// cache-first for images and icons
const CACHE = 'obelo-v3'; // bumped so browsers drop the stale cached stylesheet from v2
const STATIC = [
  '/css/tailwind.css',
  '/js/htmx.min.js',
  '/js/marked.umd.js',
  '/js/sortable.min.js',
  '/js/chart.umd.min.js',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(STATIC)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const { request } = e;
  const url = new URL(request.url);

  // Let cross-origin requests (Gravatar, etc.) go through the browser natively
  if (url.origin !== self.location.origin) return;

  // Network-first for CSS and JS, so a new release's stylesheet is used on the next load.
  // The cache is only the offline fallback.
  if (url.pathname.startsWith('/css/') || url.pathname.startsWith('/js/')) {
    e.respondWith(
      fetch(request).then(res => {
        const clone = res.clone();
        caches.open(CACHE).then(c => c.put(request, clone));
        return res;
      }).catch(() => caches.match(request))
    );
    return;
  }

  // Cache-first for images and icons, which rarely change
  if (url.pathname.startsWith('/icons/') || url.pathname.startsWith('/img/')) {
    e.respondWith(
      caches.match(request).then(cached => cached || fetch(request).then(res => {
        const clone = res.clone();
        caches.open(CACHE).then(c => c.put(request, clone));
        return res;
      }))
    );
    return;
  }

  // Network-first for everything else (pages, API calls)
  e.respondWith(fetch(request).catch(() => caches.match(request)));
});
