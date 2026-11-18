const nodemailer = require('nodemailer');
const log = require('./logService');
const notifyMode = require('../lib/notifyMode');

let _transport = null;

function getFrom() {
  const raw = (process.env.SMTP_FROM || '').trim();
  if (!raw) return process.env.SMTP_USER;
  if (raw.includes('@')) return raw;
  return `${raw} <${process.env.SMTP_USER}>`;
}

function getTransport() {
  if (_transport) return _transport;
  _transport = nodemailer.createTransport({
    host:   process.env.SMTP_HOST,
    port:   parseInt(process.env.SMTP_PORT || '587'),
    secure: process.env.SMTP_SECURE === 'true',
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
  return _transport;
}

function isConfigured() {
  return !!(process.env.SMTP_HOST && process.env.SMTP_USER);
}

// Resolves true when the message was handed to the SMTP server, false otherwise (never throws)
async function sendEmail(to, subject, text, html, { force = false } = {}) {
  if (!isConfigured()) {
    log.warn('email', `SMTP not configured — skipping email to ${to}`);
    return false;
  }
  if (!force && notifyMode.isDryRun()) {
    log.info('email', `Dry run: would send "${subject}" to ${to}`);
    return true;
  }
  try {
    const msg = { from: getFrom(), to, subject, text };
    if (html) msg.html = html;
    const info = await getTransport().sendMail(msg);
    log.info('email', `Sent to ${to}`, { subject, messageId: info.messageId });
    return true;
  } catch (err) {
    log.error('email', `Send failed to ${to}: ${err.message}`, { subject });
    return false;
  }
}

module.exports = { sendEmail, isConfigured };
