/**
 * Glaze "Chat with developer" bridge.
 *
 * A single Cloudflare Worker that proxies a two-way chat between the app and a
 * private Telegram supergroup (with Topics enabled). The bot token never leaves
 * the Worker — the client only knows the Worker URL.
 *
 * Routing model: each app user gets one forum topic in the group. Any developer
 * can reply inside that topic; their real name + id + avatar are carried back to
 * the app, so replies are attributed per-dev (not a flat "dev").
 *
 * Endpoints:
 *   POST /send            { userId, nick, text }  -> app to Telegram
 *   GET  /poll?userId&since                        -> dev replies newer than `since`
 *   POST /tg                                        -> Telegram webhook (dev replies)
 *   GET  /avatar?devId                              -> proxied Telegram avatar bytes
 *
 * KV keys (binding CHAT):
 *   topic:<userId>   = threadId              (user -> topic)
 *   user:<threadId>  = userId                (topic -> user, reverse lookup)
 *   nick:<userId>    = last known nick
 *   msg:<userId>:<ts>:<rnd> = JSON dev message (TTL 14d, auto-cleaned)
 *   rl:<userId>      = per-minute send counter (TTL 60s)
 */

const MSG_TTL = 60 * 60 * 24 * 14; // 14 days
const RATE_LIMIT_PER_MIN = 20;
const MAX_TEXT = 4000;

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    try {
      switch (url.pathname) {
        case "/send":   return req.method === "POST" ? handleSend(req, env) : bad(405);
        case "/poll":   return handlePoll(url, env);
        case "/tg":     return req.method === "POST" ? handleWebhook(req, env) : bad(405);
        case "/avatar": return handleAvatar(url, env, ctx);
        case "/health": return json({ ok: true });
        default:        return bad(404);
      }
    } catch (e) {
      return json({ error: String(e && e.message || e) }, 500);
    }
  },
};

/* ------------------------------ app -> Telegram ----------------------------- */

async function handleSend(req, env) {
  const body = await req.json().catch(() => null);
  if (!body) return json({ error: "bad json" }, 400);

  const userId = clean(body.userId, 64);
  const nick   = clean(body.nick, 48) || "user";
  const text   = String(body.text ?? "").slice(0, MAX_TEXT).trim();
  if (!userId || !text) return json({ error: "userId and text required" }, 400);

  // Basic anti-spam: the Worker URL is public, so cap sends per user per minute.
  const rlKey = `rl:${userId}`;
  const count = Number(await env.CHAT.get(rlKey)) || 0;
  if (count >= RATE_LIMIT_PER_MIN) return json({ error: "rate_limited" }, 429);
  await env.CHAT.put(rlKey, String(count + 1), { expirationTtl: 60 });

  // Find or create this user's topic.
  let threadId = await env.CHAT.get(`topic:${userId}`);
  const prevNick = await env.CHAT.get(`nick:${userId}`);

  if (!threadId) {
    const r = await tg(env, "createForumTopic", {
      chat_id: env.GROUP_ID,
      name: topicName(nick, userId),
    });
    if (!r.ok) return json({ error: "topic_create_failed", detail: r.description }, 502);
    threadId = String(r.result.message_thread_id);
    await env.CHAT.put(`topic:${userId}`, threadId);
    await env.CHAT.put(`user:${threadId}`, userId);
  } else if (nick !== prevNick) {
    // Keep the topic title in sync when the user renames themselves.
    await tg(env, "editForumTopic", {
      chat_id: env.GROUP_ID,
      message_thread_id: Number(threadId),
      name: topicName(nick, userId),
    });
  }
  await env.CHAT.put(`nick:${userId}`, nick);

  const sent = await tg(env, "sendMessage", {
    chat_id: env.GROUP_ID,
    message_thread_id: Number(threadId),
    text,
  });
  if (!sent.ok) return json({ error: "send_failed", detail: sent.description }, 502);

  return json({ ok: true });
}

/* ------------------------------ Telegram -> app ----------------------------- */

async function handleWebhook(req, env) {
  // Reject anything that isn't Telegram calling with our shared secret.
  if (req.headers.get("X-Telegram-Bot-Api-Secret-Token") !== env.WEBHOOK_SECRET) {
    return bad(401);
  }
  const update = await req.json().catch(() => null);
  const m = update && (update.message || update.edited_message);
  if (!m || !m.message_thread_id || m.from?.is_bot) return json({ ok: true });

  const text = m.text || m.caption;
  if (!text) return json({ ok: true }); // ignore stickers/service messages

  const userId = await env.CHAT.get(`user:${String(m.message_thread_id)}`);
  if (!userId) return json({ ok: true }); // reply in a topic we don't track

  const dev = m.from;
  const devName =
    [dev.first_name, dev.last_name].filter(Boolean).join(" ") ||
    (dev.username ? "@" + dev.username : "dev");

  const ts = Date.now();
  const msg = { fromDev: true, devId: String(dev.id), devName, text, ts };
  const key = `msg:${userId}:${ts}:${Math.random().toString(36).slice(2, 6)}`;
  await env.CHAT.put(key, JSON.stringify(msg), { expirationTtl: MSG_TTL });

  return json({ ok: true });
}

async function handlePoll(url, env) {
  const userId = clean(url.searchParams.get("userId"), 64);
  const since = Number(url.searchParams.get("since")) || 0;
  if (!userId) return json({ error: "userId required" }, 400);

  const list = await env.CHAT.list({ prefix: `msg:${userId}:` });
  const messages = [];
  for (const k of list.keys) {
    const ts = Number(k.name.split(":")[2]);
    if (ts > since) {
      const raw = await env.CHAT.get(k.name);
      if (raw) messages.push(JSON.parse(raw));
    }
  }
  messages.sort((a, b) => a.ts - b.ts);
  return json({ messages, now: Date.now() });
}

/* -------------------------------- avatars ---------------------------------- */

async function handleAvatar(url, env, ctx) {
  const devId = clean(url.searchParams.get("devId"), 32);
  if (!devId) return bad(400);

  const cache = caches.default;
  const cacheKey = new Request(url.toString());
  const hit = await cache.match(cacheKey);
  if (hit) return hit;

  const photos = await tg(env, "getUserProfilePhotos", { user_id: devId, limit: 1 });
  const sizes = photos?.result?.photos?.[0];
  if (!sizes || !sizes.length) return bad(404); // client falls back to initials

  const fileId = sizes[sizes.length - 1].file_id;
  const file = await tg(env, "getFile", { file_id: fileId });
  const path = file?.result?.file_path;
  if (!path) return bad(404);

  const img = await fetch(`https://api.telegram.org/file/bot${env.BOT_TOKEN}/${path}`);
  const resp = new Response(img.body, {
    headers: {
      "Content-Type": img.headers.get("content-type") || "image/jpeg",
      "Cache-Control": "public, max-age=86400",
    },
  });
  ctx.waitUntil(cache.put(cacheKey, resp.clone()));
  return resp;
}

/* -------------------------------- helpers ---------------------------------- */

async function tg(env, method, body) {
  const r = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return r.json();
}

function topicName(nick, userId) {
  return `${nick} · ${userId.slice(0, 6)}`.slice(0, 128);
}

function clean(v, max) {
  return String(v ?? "").replace(/[^\w @.\-·]/g, "").trim().slice(0, max);
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}

function bad(status) {
  return new Response(null, { status });
}
