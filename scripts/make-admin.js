require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const readline = require('readline');
const prisma = new PrismaClient();

function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => rl.question(question, ans => { rl.close(); resolve(ans); }));
}

async function main() {
  const identifier = process.argv[2];
  if (!identifier) {
    console.error('Usage: node scripts/make-admin.js <username or email>   (promotes a user, or creates an SSO admin)');
    process.exit(1);
  }

  let user = await prisma.user.findFirst({
    where: { OR: [{ username: identifier }, { email: identifier }] },
  });

  if (user) {
    await prisma.user.update({ where: { id: user.id }, data: { role: 'admin' } });
    console.log(`✓ ${user.displayName} (@${user.username}) is now admin`);
    if (!user.passwordHash && !user.oidcSub) {
      console.log(`  Note: @${user.username} has no password and hasn't signed in with SSO yet.`);
      console.log(`  Give them a setup code (Admin → Users → Password link) or run: node scripts/set-password.js ${user.username}`);
    }
    return;
  }

  // User doesn't exist — create them for single sign-on: the account needs the email of the
  // person's SSO account, and their first SSO sign-in links to it. It has no password. (For a
  // password admin, use the setup page on a new server, or scripts/set-password.js.)
  console.log(`No user found for "${identifier}". Creating new admin user...`);
  const email = (identifier.includes('@') ? identifier : await prompt('Email of their SSO account: '))
    .trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    console.error('A valid email is required — it links their first SSO sign-in to this account.');
    console.error('No SSO? Open the site and use the setup page, or create the user under Admin → Users.');
    process.exit(1);
  }
  const username = identifier.includes('@') ? email.split('@')[0].replace(/[^a-z0-9_-]/g, '_') : identifier;

  user = await prisma.user.create({
    data: {
      username,
      displayName: username,
      email,
      role:        'admin',
    },
  });
  console.log(`✓ Created admin user @${user.username} (id: ${user.id}) — sign in with SSO as ${email}`);
  console.log(`  It has no password. For password sign-in, run: node scripts/set-password.js ${user.username}`);
}

main()
  .catch(err => { console.error(err); process.exit(1); })
  .finally(() => prisma.$disconnect());
