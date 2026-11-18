const crypto = require('crypto');
const prisma = require('../lib/prisma');
const { MODULES, mobileNavFor, sidebarGroupsFor } = require('../config/modules');
const { isDarkTheme, customAccentVars, notePaperChoice, isPaperDark } = require('../config/themes');
const ai = require('../lib/aiProvider');

function gravatarUrl(email, size = 80) {
  const hash = crypto.createHash('md5').update((email || '').trim().toLowerCase()).digest('hex');
  return `https://www.gravatar.com/avatar/${hash}?s=${size}&d=identicon`;
}

module.exports = async (req, res, next) => {
  if (!req.session.userId) {
    res.locals.enabledModules = [];
    res.locals.mobileNavModules = [];
    res.locals.sidebarGroups = [];
    res.locals._theme   = 'dark';
    res.locals._isDark  = true;
    return next();
  }

  try {
    const userModules = await prisma.userModule.findMany({
      where: { userId: req.session.userId },
    });

    const enabledKeys  = new Set(userModules.filter((m) =>  m.enabled).map((m) => m.moduleKey));
    const recordedKeys = new Set(userModules.map((m) => m.moduleKey));
    const posMap       = Object.fromEntries(
      userModules.filter((m) => m.position != null).map((m) => [m.moduleKey, m.position])
    );
    const defaultOrder = Object.fromEntries(MODULES.map((m, i) => [m.key, i]));

    // Show a module if: not hidden, and (always-on, user never set a preference, or explicitly enabled)
    const enabled = MODULES
      .filter((m) => !m.hidden && (!m.requiresAi || ai.isConfigured()))
      .filter((m) => m.alwaysEnabled || !recordedKeys.has(m.key) || enabledKeys.has(m.key))
      .sort((a, b) => {
        if (a.key === 'dashboard') return -1;
        if (b.key === 'dashboard') return 1;
        if (a.key === 'settings')  return 1;
        if (b.key === 'settings')  return -1;
        const pa = posMap[a.key] != null ? posMap[a.key] : defaultOrder[a.key];
        const pb = posMap[b.key] != null ? posMap[b.key] : defaultOrder[b.key];
        return pa - pb;
      });

    res.locals.enabledModules = enabled;
    res.locals.mobileNavModules = mobileNavFor(enabled);
    res.locals.sidebarGroups = sidebarGroupsFor(enabled);
    res.locals.currentPath = req.path;

    // Compute theme/icon locals used by layout and partials
    const prefs = req.user?.preferences || {};
    const _theme = prefs.theme || 'dark';
    const _isDark = isDarkTheme(_theme, prefs.customBase);
    res.locals._theme      = _theme;
    res.locals._statusColors = prefs.statusColors === 'tailwind' ? 'tailwind' : 'catppuccin';
    res.locals._isDark     = _isDark;
    res.locals._notePaper  = notePaperChoice(prefs);   // 'theme' | 'dark' | 'white'
    res.locals._paperDark  = isPaperDark(prefs);
    res.locals._customAccentVars = _theme === 'custom'
      ? customAccentVars(prefs.customAccent || '#6366f1', _isDark)
      : null;
    const avatarExt = prefs.avatarExt || null;
    res.locals._avatarUrl   = avatarExt ? '/settings/avatar' : (req.user?.email ? gravatarUrl(req.user.email) : null);
    res.locals._hasCustomAvatar = !!avatarExt;
    res.locals._gravatarUrl = res.locals._avatarUrl; // backward compat

    const maintenanceSetting = await prisma.systemSetting.findUnique({ where: { key: 'maintenance_message' } });
    res.locals._maintenanceMessage = maintenanceSetting?.value?.trim() || null;
  } catch (err) {
    return next(err);
  }

  next();
};
