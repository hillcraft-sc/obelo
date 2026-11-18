const express = require('express');
const { requireAuth } = require('../middleware/auth');
const aiChat = require('../services/aiChatService');

const router = express.Router();

// GET /ai — chat page
router.get('/', requireAuth, (req, res) => {
  if (!req.session.aiMessages) req.session.aiMessages = [];
  res.render('ai/index', {
    title:    'AI Chat',
    messages: req.session.aiMessages,
    error:    null,
  });
});

// POST /ai/message — HTMX: send a message, get back HTML fragment
router.post('/message', requireAuth, async (req, res, next) => {
  try {
    if (!req.session.aiMessages) req.session.aiMessages = [];

    const input = (req.body.message || '').trim();
    if (!input) return res.send('');

    // Append user message to session history
    req.session.aiMessages.push({ role: 'user', content: input });

    // Keep last 20 turns to avoid huge context
    if (req.session.aiMessages.length > 40) {
      req.session.aiMessages = req.session.aiMessages.slice(-40);
    }

    const { reply, remaining } = await aiChat.chat(
      req.session.aiMessages,
      req.user.id,
      req.user,
    );

    // Append assistant reply
    req.session.aiMessages.push({ role: 'assistant', content: reply });
    await req.session.save();

    // Return both message bubbles as HTML
    res.send(renderMessage('user', input) + renderMessage('assistant', reply, remaining));
  } catch (err) {
    res.send(renderError(err.message));
  }
});

// POST /ai/clear — clear session conversation
router.post('/clear', requireAuth, (req, res) => {
  req.session.aiMessages = [];
  req.session.save(() => res.redirect('/ai'));
});

function renderMessage(role, content, remaining) {
  const isUser = role === 'user';
  const escaped = content
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/\n/g, '<br>');

  if (isUser) {
    return `<div class="flex justify-end mb-4">
      <div class="max-w-[80%] px-4 py-2.5 rounded-2xl rounded-tr-sm bg-indigo-600 text-white text-sm leading-relaxed">${escaped}</div>
    </div>`;
  }

  const rem = remaining !== undefined
    ? `<div class="text-[10px] text-gray-600 mt-1 text-right">${remaining} messages remaining today</div>`
    : '';

  return `<div class="flex justify-start mb-4">
    <div class="max-w-[85%]">
      <div class="px-4 py-2.5 rounded-2xl rounded-tl-sm bg-gray-800 border border-gray-700 text-gray-100 text-sm leading-relaxed">${escaped}</div>
      ${rem}
    </div>
  </div>`;
}

function renderError(msg) {
  const safe = String(msg).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return `<div class="flex justify-start mb-4">
    <div class="px-4 py-2.5 rounded-2xl bg-red-950 border border-red-800 text-red-300 text-sm">${safe}</div>
  </div>`;
}

module.exports = router;
