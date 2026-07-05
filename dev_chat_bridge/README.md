# Glaze — Dev Chat Bridge (Cloudflare Worker)

Two-way "chat with developer" without hosting a server. The app talks only to
this Worker; the Telegram bot token lives in Worker secrets and never ships to
clients.

Each app user maps to one **forum topic** in a private Telegram supergroup.
Multiple developers can answer inside a topic — every reply carries that dev's
real name, id, and avatar back to the app.

## One-time setup

### 1. Create (or reuse) the bot
1. New bot: [@BotFather](https://t.me/BotFather) → `/newbot` → copy the **token**.
   **Reusing an existing send-only bot** (e.g. one that only posts workflow
   notifications) is fine — just use its token. Caveat: a bot has exactly one
   webhook, and step 4 sets ours globally for that token. Only reuse a bot that
   does **not** already consume updates (no other webhook / no `getUpdates`
   consumer), or step 4 will override it. Send-only bots are safe.
2. `/setprivacy` → select the bot → **Disable**.
   (Required: with privacy ON the bot won't receive plain messages in the group,
   so dev replies inside topics would never reach the webhook. This is a global
   bot setting and does not affect send-only notification posting.)

### 2. Create the group
1. Create a **supergroup** (not a channel), add your developers.
2. Group settings → **Topics** → enable.
3. Add the bot as **admin** with **Manage Topics** permission.
4. Get the group id (starts with `-100…`): temporarily add
   [@RawDataBot](https://t.me/RawDataBot), read `chat.id`, then remove it.
   Put that id in `wrangler.toml` → `GROUP_ID`.

### 3. Deploy the Worker
```bash
npm i -g wrangler
wrangler login

# create KV, then paste the printed id into wrangler.toml (kv_namespaces.id)
wrangler kv namespace create CHAT

# secrets
wrangler secret put BOT_TOKEN        # paste bot token
wrangler secret put WEBHOOK_SECRET   # any long random string, remember it

wrangler deploy                      # prints https://glaze-dev-chat.<you>.workers.dev
```

### 4. Register the Telegram webhook
Replace `<TOKEN>`, `<WORKER_URL>`, `<WEBHOOK_SECRET>`:
```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=<WORKER_URL>/tg&secret_token=<WEBHOOK_SECRET>"
```
Expect `{"ok":true,...}`. Sanity check: `GET <WORKER_URL>/health` → `{"ok":true}`.

Give the app the base URL `<WORKER_URL>` (this goes in the Flutter config).

## Endpoints
| Method | Path | Purpose |
|--------|------|---------|
| POST | `/send` | `{ userId, nick, text }` — app → group topic |
| GET  | `/poll?userId=&since=` | dev replies newer than `since` (ms) |
| POST | `/tg` | Telegram webhook (dev replies → queue) |
| GET  | `/avatar?devId=` | proxied dev avatar bytes (404 → show initials) |

## Notes
- Messages auto-expire from KV after 14 days.
- Per-user send rate limit: 20/min (the URL is public; tune in `index.js`).
- Single-device assumption per `userId` — the client owns its own sent-message
  history; `/poll` only returns dev → user messages.
