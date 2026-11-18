const Anthropic = require('@anthropic-ai/sdk');
const OpenAI = require('openai');

// Instance-level AI configuration, set by whoever hosts Obelo (see .env.example).
// Providers: anthropic | openai | openai-compatible (Ollama, LM Studio, vLLM, llama.cpp, OpenRouter, ...)
const PROVIDERS = ['anthropic', 'openai', 'openai-compatible'];

const MAX_TOKENS = { chat: 4096, capture: 2048 };

class AiError extends Error {
  constructor(message, { status = 502, cause } = {}) {
    super(message);
    this.name = 'AiError';
    this.status = status;
    if (cause) this.cause = cause;
  }
}

function getConfig() {
  const provider = (process.env.AI_PROVIDER || '').trim().toLowerCase();
  const chat     = (process.env.AI_CHAT_MODEL || '').trim();
  const capture  = (process.env.AI_CAPTURE_MODEL || '').trim();

  return {
    provider,
    apiKey:    (process.env.AI_API_KEY || '').trim(),
    baseURL:   (process.env.AI_BASE_URL || '').trim(),
    models:    { chat: chat || capture, capture: capture || chat },
    timeoutMs: (parseInt(process.env.AI_TIMEOUT_SECONDS) || 120) * 1000,
  };
}

// Returns null when usable, otherwise a host-facing reason
function configProblem(cfg = getConfig()) {
  if (!cfg.provider) return 'AI_PROVIDER is not set';
  if (!PROVIDERS.includes(cfg.provider)) return `AI_PROVIDER "${cfg.provider}" is not one of ${PROVIDERS.join(', ')}`;
  if (cfg.provider !== 'openai-compatible' && !cfg.apiKey) return 'AI_API_KEY is not set';
  if (cfg.provider === 'openai-compatible' && !cfg.baseURL) return 'AI_BASE_URL is required for openai-compatible';
  if (!cfg.models.chat) return 'AI_CHAT_MODEL / AI_CAPTURE_MODEL are not set';
  return null;
}

function isConfigured() {
  return configProblem() === null;
}

function describe() {
  const cfg = getConfig();
  const problem = configProblem(cfg);
  if (problem) return `AI disabled (${problem})`;
  const where = cfg.baseURL ? ` at ${cfg.baseURL}` : '';
  return `AI provider: ${cfg.provider}${where} — chat: ${cfg.models.chat}, capture: ${cfg.models.capture}`;
}

let cached = null;
function getClient(cfg) {
  const key = `${cfg.provider}|${cfg.apiKey}|${cfg.baseURL}|${cfg.timeoutMs}`;
  if (cached?.key === key) return cached.client;

  const opts = { timeout: cfg.timeoutMs, maxRetries: 1 };
  const client = cfg.provider === 'anthropic'
    ? new Anthropic({ ...opts, apiKey: cfg.apiKey })
    : new OpenAI({
        ...opts,
        // Most local servers ignore the key, but the SDK requires a non-empty one
        apiKey:  cfg.apiKey || 'not-needed',
        baseURL: cfg.baseURL || undefined,
      });
  cached = { key, client };
  return client;
}

// Models/servers that rejected native JSON mode; we fall back to prompt-only JSON for them
const jsonModeUnsupported = new Set();

// Some local reasoning models (DeepSeek-R1, Qwen3, ...) inline their reasoning in the reply
function stripThinking(text) {
  return text.replace(/<think>[\s\S]*?<\/think>/gi, '').trim();
}

async function callAnthropic(client, { model, system, messages, maxTokens, jsonSchema }) {
  const params = { model, max_tokens: maxTokens, system, messages };
  if (jsonSchema) params.output_config = { format: { type: 'json_schema', schema: jsonSchema } };

  const res = await client.messages.create(params);
  if (res.stop_reason === 'refusal') throw new AiError('The AI model declined to answer that request.');
  return res.content.filter(b => b.type === 'text').map(b => b.text).join('');
}

async function callOpenAI(client, cfg, { model, system, messages, maxTokens, jsonSchema, feature }) {
  const params = {
    model,
    messages: [{ role: 'system', content: system }, ...messages],
  };
  // OpenAI deprecated max_tokens; many OpenAI-compatible servers only understand max_tokens
  if (cfg.provider === 'openai') params.max_completion_tokens = maxTokens;
  else params.max_tokens = maxTokens;
  if (jsonSchema) {
    params.response_format = {
      type: 'json_schema',
      json_schema: { name: feature, schema: jsonSchema, strict: true },
    };
  }

  const res = await client.chat.completions.create(params);
  const choice = res.choices?.[0];
  if (choice?.message?.refusal) throw new AiError('The AI model declined to answer that request.');
  return choice?.message?.content || '';
}

function normalizeError(err, cfg, model) {
  if (err instanceof AiError) return err;
  const status = err?.status;
  const where  = cfg.provider === 'openai-compatible' ? 'the AI server' : `the ${cfg.provider} API`;

  if (err instanceof Anthropic.APIConnectionError || err instanceof OpenAI.APIConnectionError) {
    const timedOut = err instanceof Anthropic.APIConnectionTimeoutError || err instanceof OpenAI.APIConnectionTimeoutError;
    return new AiError(timedOut ? `${where} took too long to respond.` : `Couldn't reach ${where}.`, { cause: err });
  }
  if (status === 401 || status === 403) return new AiError(`${where} rejected the configured API key.`, { cause: err });
  if (status === 404) return new AiError(`Model "${model}" was not found on ${where}.`, { cause: err });
  if (status === 429) return new AiError(`${where} is rate-limiting requests — try again shortly.`, { status: 429, cause: err });
  return new AiError(`${where} returned an error${status ? ` (${status})` : ''}.`, { cause: err });
}

/**
 * Run a single completion for a feature and return the reply text.
 * @param {object} opts
 * @param {'chat'|'capture'} opts.feature   selects AI_CHAT_MODEL / AI_CAPTURE_MODEL
 * @param {string} opts.system
 * @param {{role:'user'|'assistant', content:string}[]} opts.messages
 * @param {object} [opts.jsonSchema]         request native JSON output matching this schema where supported
 */
async function complete({ feature, system, messages, jsonSchema }) {
  const cfg = getConfig();
  const problem = configProblem(cfg);
  if (problem) throw new AiError("AI isn't configured on this server.", { status: 503 });

  const model  = cfg.models[feature];
  const client = getClient(cfg);
  const modeKey = `${cfg.provider}|${cfg.baseURL}|${model}`;
  const req = {
    feature, model, system, messages,
    maxTokens:  MAX_TOKENS[feature] || MAX_TOKENS.chat,
    jsonSchema: jsonSchema && !jsonModeUnsupported.has(modeKey) ? jsonSchema : null,
  };
  const call = r => (cfg.provider === 'anthropic' ? callAnthropic(client, r) : callOpenAI(client, cfg, r));

  try {
    let text;
    try {
      text = await call(req);
    } catch (err) {
      // Model/server doesn't support native JSON mode — remember and retry with prompt-only JSON
      if (req.jsonSchema && err?.status === 400) {
        console.warn(`[ai] ${model}: native JSON mode rejected (${err.message}); falling back to prompt-only JSON`);
        jsonModeUnsupported.add(modeKey);
        text = await call({ ...req, jsonSchema: null });
      } else {
        throw err;
      }
    }
    return stripThinking(text);
  } catch (err) {
    const normalized = normalizeError(err, cfg, model);
    console.error(`[ai] ${feature} request failed (${cfg.provider}, ${model}):`, err?.message || err);
    throw normalized;
  }
}

module.exports = { complete, isConfigured, describe, AiError };
