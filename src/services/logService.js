const prisma = require('../lib/prisma');

const LEVELS = { debug: 0, info: 1, warn: 2, error: 3 };
const MIN_LEVEL = LEVELS[process.env.LOG_LEVEL] ?? LEVELS.info;

async function write(level, category, message, meta) {
  if ((LEVELS[level] ?? 0) < MIN_LEVEL) return;

  const prefix = `[${level.toUpperCase()}] [${category}]`;
  if (level === 'error') console.error(prefix, message, meta ?? '');
  else console.log(prefix, message, meta ?? '');

  try {
    await prisma.appLog.create({
      data: { level, category, message, meta: meta ?? undefined },
    });
  } catch (err) {
    console.error('[log] failed to persist log entry:', err.message);
  }
}

module.exports = {
  debug: (cat, msg, meta) => write('debug', cat, msg, meta),
  info:  (cat, msg, msg2) => write('info',  cat, msg, msg2),
  warn:  (cat, msg, meta) => write('warn',  cat, msg, meta),
  error: (cat, msg, meta) => write('error', cat, msg, meta),
};
