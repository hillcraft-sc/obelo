// Fixtures: users made straight in the database (fast), then signed in the normal way.
const passwords = require('../../src/lib/passwords');
const { prisma } = require('./app');

// bcrypt is slow on purpose, so hash each test password once
const hashes = new Map();
async function hashOnce(password) {
  if (!hashes.has(password)) hashes.set(password, await passwords.hashPassword(password));
  return hashes.get(password);
}

async function createUser({ username, password, role = 'user', email = null, displayName } = {}) {
  return prisma.user.create({
    data: {
      username, email, role, displayName: displayName || username,
      passwordHash: password ? await hashOnce(password) : null,
    },
  });
}

// Signs the client in through the real login form. Returns the response.
async function signIn(client, username, password) {
  return client.post('/auth/login', { form: { username, password } });
}

const PASSWORD = 'a-long-enough-password-1';

module.exports = { createUser, signIn, PASSWORD };
