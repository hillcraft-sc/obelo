const prisma = require('../lib/prisma');
const { fmtHHMM, prefsHour12 } = require('../lib/timeFormat');

const requireAuth = (req, res, next) => {
  if (!req.session.userId) {
    return res.redirect('/auth/login');
  }
  next();
};

const loadUser = async (req, res, next) => {
  if (!req.session.userId) return next();

  try {
    const user = await prisma.user.findUnique({
      where: { id: req.session.userId },
      select: {
        id: true,
        username: true,
        email: true,
        role: true,
        displayName: true,
        timezone: true,
        preferences: true,
      },
    });

    if (!user) {
      req.session.destroy();
      if (req.originalUrl.startsWith('/api/')) return res.status(401).json({ error: 'Signed out' });
      return res.redirect('/auth/login');
    }

    req.user = user;
    res.locals.currentUser = user;
    const use12h = prefsHour12(user.preferences);
    res.locals.hour12 = use12h;
    res.locals.fmtTime = (hhmm) => fmtHHMM(hhmm, use12h);
  } catch (err) {
    return next(err);
  }

  next();
};

const requireAdmin = (req, res, next) => {
  if (!req.session.userId) return res.redirect('/auth/login');
  if (req.user?.role !== 'admin') {
    return res.status(403).render('error', {
      layout: 'layouts/main',
      title: 'Forbidden',
      error: { status: 403, message: 'Admin access required.' },
    });
  }
  next();
};

module.exports = { requireAuth, requireAdmin, loadUser };
