require('../helpers/env');
const { describe, it, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { PrismaClient } = require('@prisma/client');
const { prisma } = require('../helpers/app');

// Upgrading is the riskiest thing this project ships. These tests build real databases in
// scratch databases on the test server, so nothing here touches the main test database.
const ROOT = path.join(__dirname, '..', '..');
const MIGRATIONS = fs.readdirSync(path.join(ROOT, 'prisma', 'migrations')).filter((n) => /^\d{14}_/.test(n)).sort();
const SERVER_URL = process.env.DATABASE_URL;             // the test database (the harness has already checked its name)
const urlFor = (db) => SERVER_URL.replace(/\/[^/?]+(\?|$)/, `/${db}$1`);
const made = [];

async function newDb(label) {
  const name = `obelo_mig_${label}_${process.pid}_test`;
  await prisma.$executeRawUnsafe(`DROP DATABASE IF EXISTS "${name}"`);
  await prisma.$executeRawUnsafe(`CREATE DATABASE "${name}"`);
  made.push(name);
  return { name, url: urlFor(name) };
}

const run = (cmd, args, url, extra = {}) => execFileSync(cmd, args, {
  cwd: ROOT, env: { ...process.env, DATABASE_URL: url }, encoding: 'utf8', stdio: 'pipe', ...extra,
});
const baseline = (url) => run('node', ['scripts/baseline-migrations.js'], url);   // what the container does before migrating
const deploy = (url, schema) => run('npx', ['prisma', 'migrate', 'deploy', ...(schema ? ['--schema', schema] : [])], url);

// A copy of the schema folder holding only the first `count` migrations: "the database at an older release"
function oldRelease(count) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'obelo-mig-'));
  fs.copyFileSync(path.join(ROOT, 'prisma', 'schema.prisma'), path.join(dir, 'schema.prisma'));
  fs.mkdirSync(path.join(dir, 'migrations'));
  fs.copyFileSync(path.join(ROOT, 'prisma', 'migrations', 'migration_lock.toml'), path.join(dir, 'migrations', 'migration_lock.toml'));
  for (const m of MIGRATIONS.slice(0, count)) fs.cpSync(path.join(ROOT, 'prisma', 'migrations', m), path.join(dir, 'migrations', m), { recursive: true });
  return path.join(dir, 'schema.prisma');
}

// Nothing may differ between "the migrations applied" and what schema.prisma says
function drift(url) {
  try {
    run('npx', ['prisma', 'migrate', 'diff', '--from-url', url, '--to-schema-datamodel', 'prisma/schema.prisma', '--exit-code'], url);
    return '';
  } catch (err) { return String(err.stdout || err.message).slice(0, 800); }
}

after(async () => {
  for (const name of made) await prisma.$executeRawUnsafe(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`).catch(() => {});
});

describe('a new install', () => {
  it('applies every migration to an empty database, and the result matches schema.prisma', async () => {
    const db = await newDb('empty');
    baseline(db.url);
    deploy(db.url);
    assert.equal(drift(db.url), '', 'the migrations and schema.prisma disagree');
    const client = new PrismaClient({ datasources: { db: { url: db.url } } });
    try {
      const rows = await client.$queryRaw`SELECT count(*)::int AS n FROM _prisma_migrations WHERE finished_at IS NOT NULL`;
      assert.ok(rows[0].n >= MIGRATIONS.length - 1, `${rows[0].n} migrations recorded for ${MIGRATIONS.length} folders`);
    } finally { await client.$disconnect(); }
  });

  it('running the deploy again changes nothing', async () => {
    const db = await newDb('again');
    baseline(db.url); deploy(db.url);
    assert.match(deploy(db.url), /No pending migrations/);
  });
});

describe('upgrading from an older release keeps what people wrote', () => {
  // Point in time -> the newest migration the old database already had. Each stops after one that
  // changed the schema in a way that matters.
  const CUTS = [
    ['the schema as of early July', '20260702000001_add_routine_streak_history'],
    ['as of mid October', '20261007000001_drop_password_hash'],
    ['just before folders', '20261111120000_remove_health'],
    ['just before password sign-in (3.44)', '20261112120000_add_folders'],
    ['just before setup codes (3.45)', '20261114120000_add_password_signin'],
  ];

  for (const [label, lastApplied] of CUTS) {
    it(`from ${label}`, async () => {
      const count = MIGRATIONS.indexOf(lastApplied) + 1;
      assert.ok(count > 0, `migration ${lastApplied} not found`);
      const db = await newDb(`cut${count}`);
      baseline(db.url);
      deploy(db.url, oldRelease(count));

      const client = new PrismaClient({ datasources: { db: { url: db.url } } });
      try {
        // what a real install holds: people, and the things they wrote
        await client.$executeRawUnsafe(`INSERT INTO users (username, display_name) VALUES ('sam', 'Sam'), ('ann', 'Ann')`);
        await client.$executeRawUnsafe(`INSERT INTO notes (user_id, title, content, updated_at) SELECT id, 'Note of ' || username, 'body </script> ''"', now() FROM users`);
        await client.$executeRawUnsafe(`INSERT INTO tasks (user_id, title, updated_at) SELECT id, 'Task of ' || username, now() FROM users`);
        await client.$executeRawUnsafe(`INSERT INTO reminders (user_id, title) SELECT id, 'Reminder of ' || username FROM users`);
        await client.$executeRawUnsafe(`INSERT INTO bookmarks (user_id, url, updated_at) SELECT id, 'https://example.com/' || username, now() FROM users`);
        await client.$executeRawUnsafe(`INSERT INTO lists (user_id, title) SELECT id, 'List of ' || username FROM users`);
        const before = await client.$queryRawUnsafe(`SELECT (SELECT json_agg(u ORDER BY username) FROM (SELECT username, display_name FROM users) u) AS users,
          (SELECT json_agg(title ORDER BY title) FROM notes) AS notes, (SELECT json_agg(title ORDER BY title) FROM tasks) AS tasks,
          (SELECT json_agg(title ORDER BY title) FROM reminders) AS reminders, (SELECT json_agg(url ORDER BY url) FROM bookmarks) AS bookmarks,
          (SELECT json_agg(title ORDER BY title) FROM lists) AS lists`);

        deploy(db.url);   // the upgrade: the real migrations, on top of the old database

        const after = await client.$queryRawUnsafe(`SELECT (SELECT json_agg(u ORDER BY username) FROM (SELECT username, display_name FROM users) u) AS users,
          (SELECT json_agg(title ORDER BY title) FROM notes) AS notes, (SELECT json_agg(title ORDER BY title) FROM tasks) AS tasks,
          (SELECT json_agg(title ORDER BY title) FROM reminders) AS reminders, (SELECT json_agg(url ORDER BY url) FROM bookmarks) AS bookmarks,
          (SELECT json_agg(title ORDER BY title) FROM lists) AS lists`);
        assert.deepEqual(after, before, 'people\'s data changed in the upgrade');
        const content = await client.$queryRawUnsafe(`SELECT content FROM notes LIMIT 1`);
        assert.equal(content[0].content, `body </script> '"`);
      } finally { await client.$disconnect(); }
      assert.equal(drift(db.url), '', 'after upgrading, the database does not match schema.prisma');
    });
  }
});

describe('what the migrations are allowed to do', () => {
  it('none of them drops or rewrites data without being listed here', () => {
    // A migration that drops a table or column, or changes a column's type, needs the maintainer's
    // go-ahead and a backup note in the changelog . When one is added on
    // purpose, add it here too, so it can't slip in by accident.
    const ALLOWED = {
      '20261007000001_drop_password_hash': 'the old password column (sign-in was SSO only)',
      '20261111120000_remove_health': 'two unused tables were dropped',
    };
    const found = {};
    for (const m of MIGRATIONS) {
      const sql = fs.readFileSync(path.join(ROOT, 'prisma', 'migrations', m, 'migration.sql'), 'utf8');
      if (/\bDROP\s+(TABLE|COLUMN)\b|\bALTER\s+COLUMN\b[^;]*\bTYPE\b|\bDELETE\s+FROM\b|\bTRUNCATE\b/i.test(sql)) found[m] = true;
    }
    const unexpected = Object.keys(found).filter((m) => !(m in ALLOWED));
    assert.deepEqual(unexpected, [], 'a migration drops or rewrites data: it needs the maintainer\'s go-ahead, a changelog note to back up first, and a line in this test');
  });

  it('every migration folder has a migration.sql', () => {
    for (const m of MIGRATIONS) assert.ok(fs.existsSync(path.join(ROOT, 'prisma', 'migrations', m, 'migration.sql')), m);
  });
});
