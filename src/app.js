require('dotenv').config();

if (!process.env.SESSION_SECRET) {
  console.error('FATAL: SESSION_SECRET environment variable is not set. Refusing to start.');
  process.exit(1);
}

const express = require('express');
const session = require('express-session');
const PgSession = require('connect-pg-simple')(session);
const csrf = require('./middleware/csrf');
const expressLayouts = require('express-ejs-layouts');
const helmet = require('helmet');
const { rateLimit } = require('express-rate-limit');
const path = require('path');

const { version } = require('../package.json');
const { loadUser, requireAuth } = require('./middleware/auth');
const loadModules = require('./middleware/modules');
const log = require('./services/logService');
const ai = require('./lib/aiProvider');
const uploads = require('./lib/uploads');
const oidc = require('./services/oidcService');
const sessionLifetime = require('./lib/sessionLifetime');
const notifyMode = require('./lib/notifyMode');
const userSessions = require('./lib/userSessions');
const { upgradeStoredCredentials } = require('./lib/credentials');
const prisma = require('./lib/prisma');

const authRoutes = require('./routes/auth');
const { router: dashboardRoutes } = require('./routes/dashboard');
const { router: notesRoutes } = require('./routes/notes');
const { router: tasksRoutes } = require('./routes/tasks');
const { router: remindersRoutes } = require('./routes/reminders');
const { router: routinesRoutes } = require('./routes/routines');
const { router: calendarRoutes } = require('./routes/calendar');
const captureRoutes = require('./routes/capture');
const aiRoutes       = require('./routes/ai');
const { router: settingsRoutes } = require('./routes/settings');
const searchRoutes   = require('./routes/search');
const adminRoutes    = require('./routes/admin');
const listsRoutes       = require('./routes/lists');
const bookmarksRoutes   = require('./routes/bookmarks');
const helpRoutes        = require('./routes/help');
const { router: analyticsRoutes } = require('./routes/analytics');
const apiRoutes         = require('./routes/api');
const cronService = require('./services/cronService');

const app = express();

app.set('trust proxy', 1);
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(expressLayouts);
app.set('layout', 'layouts/main');
app.set('layout extractScripts', true);
app.set('layout extractStyles', true);

// ── Security headers (helmet) ─────────────────────────────────────────────
// CSP allows the CDNs used by the app (Tailwind, HTMX, Chart.js, Sortable).
// 'unsafe-inline' for scripts is unavoidable due to inline tailwind.config
// blocks in EJS layouts; all other directives are strict.
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc:  ["'self'"],
      scriptSrc:   ["'self'", "'unsafe-inline'"],
      // Helmet 8 sets script-src-attr:'none' by default which blocks all inline
      // onclick/onsubmit handlers in CSP-L3 browsers even with unsafe-inline
      // in script-src. Override to match our existing unsafe-inline posture.
      scriptSrcAttr: ["'unsafe-inline'"],
      styleSrc:    ["'self'", "'unsafe-inline'"],
      imgSrc:      ["'self'", 'data:', 'https://www.gravatar.com', 'https://icons.duckduckgo.com'],
      fontSrc:     ["'self'"],
      connectSrc:  ["'self'"],
      frameSrc:    ["'none'"],
      objectSrc:   ["'none'"],
      baseUri:     ["'self'"],
      formAction:  ["'self'"],
      frameAncestors: ["'none'"],
    },
  },
  crossOriginEmbedderPolicy: false,
}));

// ── Body parser with size limits ──────────────────────────────────────────
app.use(express.urlencoded({ extended: true, limit: '5mb' }));
app.use(express.json({ limit: '5mb' }));

// ── Session ───────────────────────────────────────────────────────────────
// sameSite: 'lax' blocks cross-site POST (CSRF) while allowing OIDC
// callback redirects (top-level GET navigations from the OAuth provider).
// rolling + idle maxAge: the session ends after SESSION_IDLE_HOURS without use;
// sessionLifetime.enforce adds the absolute SESSION_MAX_DAYS limit.
app.use(
  session({
    store: new PgSession({
      conString: process.env.DATABASE_URL,
      tableName: 'sessions',
      createTableIfMissing: true,
    }),
    secret: process.env.SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    rolling: true,
    cookie: {
      maxAge: sessionLifetime.idleMs,
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
    },
  })
);
app.use(sessionLifetime.enforce);
app.use(userSessions.trackActivity);

// ── Rate limiting ─────────────────────────────────────────────────────────
const skipInDev = () => process.env.NODE_ENV === 'development';

// Capture/AI: 30 API calls per minute per IP (Claude API cost protection)
const captureLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Rate limit exceeded — slow down.',
  skip: skipInDev,
});
app.use('/capture', captureLimiter);
app.use('/api/v1/capture', captureLimiter);
app.use('/ai/message', captureLimiter);
app.use('/api/v1/ai/message', captureLimiter);

// PIN unlock / PIN change: 10 attempts per 15 minutes per IP
const pinLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many attempts — please try again later.',
  skip: skipInDev,
});
// Connecting a calendar account makes the server log in somewhere with a password: 20 tries per 15 minutes per IP
const calendarConnectLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many attempts — please try again later.',
  skip: skipInDev,
});
app.post('/calendar/sources', calendarConnectLimiter);
app.post('/api/v1/calendar/sources', calendarConnectLimiter);
app.use('/settings/note-lock-pin', pinLimiter);
app.use('/settings/password', pinLimiter);

app.use(csrf);
app.use(loadUser);
app.use(loadModules);
app.use((req, res, next) => { res.locals.demoMode = require('./lib/demo').isDemo(); res.locals._version = version; res.locals.aiEnabled = ai.isConfigured(); res.locals.googleSiteVerification = process.env.GOOGLE_SITE_VERIFICATION || ''; next(); });

// Log 4xx/5xx HTTP responses
app.use((req, res, next) => {
  const ip = req.headers['x-forwarded-for']?.split(',')[0].trim() || req.socket.remoteAddress;
  res.on('finish', () => {
    if (res.statusCode >= 500) {
      log.error('http', `${res.statusCode} ${req.method} ${req.path}`, { ip, status: res.statusCode });
    } else if (res.statusCode >= 400) {
      log.warn('http', `${res.statusCode} ${req.method} ${req.path}`, { ip, status: res.statusCode });
    }
  });
  next();
});

// Dynamic manifest — must come before express.static so it takes priority over public/manifest.json
app.get('/manifest.json', (req, res) => {
  const { isDarkTheme } = require('./config/themes');
  const prefs = req.user?.preferences || {};
  const theme = prefs.theme || 'dark';
  const dark = isDarkTheme(theme, prefs.customBase);
  const prefix = 'obelo';
  const bgColor =
    theme === 'midnight' ? '#080e1c' :
    theme === 'forest'   ? '#080f07' :
    theme === 'mocha'    ? '#110b04' :
    theme === 'breeze'   ? '#dce9f7' :
    theme === 'ctp-latte' ? '#dce0e8' :
    theme === 'ctp-frappe' ? '#292c3c' :
    theme === 'ctp-macchiato' ? '#1e2030' :
    theme === 'ctp-mocha' ? '#181825' :
    dark ? '#030712' : '#f1f5f9';

  res.json({
    name: 'Obelo',
    short_name: 'Obelo',
    description: 'Your personal productivity hub',
    start_url: '/',
    scope: '/',
    display: 'standalone',
    orientation: 'portrait-primary',
    background_color: bgColor,
    theme_color: bgColor,
    categories: ['productivity', 'utilities'],
    icons: [
      { src: `/icons/${prefix}-192.png`, sizes: '192x192', type: 'image/png', purpose: 'any maskable' },
      { src: `/icons/${prefix}-512.png`, sizes: '512x512', type: 'image/png', purpose: 'any maskable' },
    ],
    shortcuts: [
      { name: 'Capture',   short_name: 'Capture',   url: '/capture',   icons: [{ src: `/icons/${prefix}-192.png`, sizes: '192x192' }] },
      { name: 'Today',     short_name: 'Today',     url: '/',          icons: [{ src: `/icons/${prefix}-192.png`, sizes: '192x192' }] },
      { name: 'Tasks',     short_name: 'Tasks',     url: '/tasks',     icons: [{ src: `/icons/${prefix}-192.png`, sizes: '192x192' }] },
      { name: 'Notes',     short_name: 'Notes',     url: '/notes',     icons: [{ src: `/icons/${prefix}-192.png`, sizes: '192x192' }] },
      { name: 'Reminders', short_name: 'Reminders', url: '/reminders', icons: [{ src: `/icons/${prefix}-192.png`, sizes: '192x192' }] },
    ],
  });
});

// Static files after session/loadUser so the manifest route above takes priority
// The checklist helper is shared with the browser (the note editor's Preview)
app.get('/js/checklist.js', (req, res) => res.sendFile(path.join(__dirname, 'services', 'checklist.js')));
app.use(express.static(path.join(__dirname, '..', 'public')));

// Public legal pages (no auth — Google checks these URLs)
app.get('/privacy', (req, res) => res.render('legal/privacy', { layout: 'layouts/auth', title: 'Privacy Policy' }));
app.get('/terms',   (req, res) => res.render('legal/terms',   { layout: 'layouts/auth', title: 'Terms of Service' }));

const { demoGuard } = require('./middleware/demo');
app.use(demoGuard);
app.use('/api/v1', apiRoutes);
app.use('/auth', authRoutes);
app.use('/notes', notesRoutes);
app.use('/tasks', tasksRoutes);
app.use('/reminders', remindersRoutes);
app.use('/routines', routinesRoutes);
app.use('/calendar', calendarRoutes);
app.use('/capture', captureRoutes);
app.use('/ai', aiRoutes);
app.use('/settings', settingsRoutes);
app.use('/search',   searchRoutes);
app.use('/admin',    adminRoutes);
app.use('/lists',     listsRoutes);
app.use('/bookmarks', bookmarksRoutes);
app.use('/help',      helpRoutes);
app.use('/analytics', analyticsRoutes);
app.use('/', dashboardRoutes);

// ── 404 handler ───────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).render('error', {
    layout: req.session?.userId ? 'layouts/main' : 'layouts/auth',
    title: 'Not Found',
    error: { status: 404, message: 'Page not found.' },
  });
});

// ── Global error handler ──────────────────────────────────────────────────
app.use((err, req, res, _next) => {
  const status = err.status || 500;
  if (status >= 500) {
    log.error('system', `Unhandled error: ${err.message}`, { path: req.path, stack: err.stack?.split('\n')[1]?.trim() });
  }
  const userMessage = status >= 500
    ? 'An unexpected error occurred. Please try again later.'
    : (err.message || 'Something went wrong.');
  res.status(status).render('error', {
    layout: req.session?.userId ? 'layouts/main' : 'layouts/auth',
    title: 'Error',
    error: { status, message: userMessage },
  });
});

const PORT = process.env.PORT || 3000;
// Only when run directly (node src/app.js, npm start, Docker). The tests import the app and start
// it themselves, without the scheduler.
if (require.main === module) app.listen(PORT, '0.0.0.0', () => {
  log.info('system', `Obelo started on port ${PORT}`, { env: process.env.NODE_ENV || 'development' });
  log.info('system', ai.describe());
  log.info('system', uploads.describe());
  log.info('system', sessionLifetime.describe());
  log.info('system', notifyMode.describe());
  if (!oidc.isConfigured()) {
    log.info('system', 'SSO is not configured (OIDC_ISSUER, OIDC_CLIENT_ID, OIDC_CLIENT_SECRET) — sign-in is by password only');
  }
  const legacy = oidc.legacyNamesInUse();
  if (legacy.length) {
    log.warn('system', `Old SSO setting names in use (${legacy.join(', ')}). They still work; rename them to ${legacy.map(n => n.replace('AUTHENTIK_', 'OIDC_')).join(', ')} in .env.`);
  }
  upgradeStoredCredentials(prisma, log)
    .then(n => { if (n) log.info('system', `Re-encrypted stored credentials for ${n} calendar source(s)`); })
    .catch(err => log.error('system', `Credential upgrade failed: ${err.message}`));
  cronService.start();
});

module.exports = app;
