# Monblant ExtBlocks — Compatibility Specification

**Status:** Phase 0 (RFC, pre-implementation)
**Scope:** GlazeFlutter ↔ SillyTavern ExtBlocks (Monblant) API/JSON compatibility
**Reference:** https://gitgud.io/Monblant/extblocks
**Target audience:** GlazeFlutter maintainers, GlazeFlutter lead developer
**Implementation timeline:** ~4-5 weeks (24 phases, 1 commit per phase)

---

## 1. Goal

Allow SillyTavern ExtBlocks extensions (Monblant's 4-type block model) to run inside
GlazeFlutter's `jsRunner` / `interactive` blocks with **minimal or no rewriting**,
and to allow GlazeFlutter presets to interoperate with Monblant preset JSON files.

**Out of scope:** running Monblant's *own extension* (`extblocks/index.js`,
jQuery, SillTavern's `getContext`, etc.) — we expose the *API surface* that
Monblant scripts use, but we do not embed ST's DOM/runtime. Scripts that
depend on ST-specific DOM (e.g. `#chat`, `#send_textarea`, ST's full
`eventSource.on('MESSAGE_RECEIVED', ...)` chain with `event_data` payload
containing ST-specific fields) will need light rewriting.

---

## 2. Block type mapping

| Monblant block type | GlazeFlutter block type | Notes |
|---|---|---|
| **Generated** (LLM fills an XML-like tag in its reply) | `BlockType.infoblock` | 1:1 — already supported, no changes needed. |
| **Generated — Rewrite** (rewrites the main char response) | `BlockType.infoblock` with new `isRewrite: true` flag | New flag in `BlockConfig`. Pipeline: LLM fills `<rewritten text>` block, replaces last assistant message. |
| **Generated — Accumulative** (YAML state with updater blocks) | `BlockType.infoblock` with new `isAccumulative: true` flag | New flag. State stored in `ChatSession.sessionVars['__glaze_extblocks_accumulative__']`. Updater block uses MongoDB-style operators parsed server-side. |
| **Script** (STScript or JS) | `BlockType.jsRunner` | 1:1 — already supported. STScript fallback: best-effort regex parser (subset). |
| **Script — Interactive** (HTML/JS panel) | `BlockType.interactive` | 1:1 — already supported. |

The 4 Monblant block types collapse into our 4 types via flags. This means
Monblant preset JSON imports cleanly into our schema.

---

## 3. Monblant JSON preset shape → GlazeFlutter `ExtensionPreset`

Monblant stores a preset as a list of block configs (each with
`name`, `type`, `triggers`, `role`, `depth`, `position`, `period`, `keyword`,
`template`, `prompt`, etc.). Our `BlockConfig` covers 90% of the fields
already. New fields to add (Phase 12):

| New field | Type | Default | Used by |
|---|---|---|---|
| `isRewrite` | `bool` | `false` | Rewrite block flag (Phase 2) |
| `isAccumulative` | `bool` | `false` | Accumulative block flag (Phase 3) |
| `trigger` extended | `BlockTrigger` enum + extras | `afterAssistant` | New: `swipe`, `generationPause` (Phase 6) |
| `period` | `int` | `0` | Every N messages; 0 = disabled (Phase 5) |
| `keyword` | `String` | `''` | Trigger keyword; '' = disabled (Phase 5) |
| `injectPosition` | `InjectPosition` enum | `inChat` | New: `afterMainPrompt`, `beforeMainPrompt`, `inChat` (Phase 19) |
| `injectRole` | `InjectRole` enum | `system` | `system`, `assistant`, `user` (Phase 19) |
| `updaterBlockId` | `String?` | `null` | For accumulative blocks: id of updater block (Phase 3) |
| `accumulativeState` | `Map<String, dynamic>` | `{}` | Initial YAML state (Phase 3) |
| `background` | `bool` | `false` | Background generation (no UI streaming) (Phase 10) |
| `parallel` | `bool` | `false` | Run with other blocks in parallel (Phase 10) |
| `scriptType` | `ScriptType` enum | `js` | `js` or `stscript` (Phase 4) |
| `stscriptCode` | `String` | `''` | STScript source (Phase 4) |

---

## 4. JS shim — what we expose

Monblant scripts expect a SillyTavern-compatible runtime. We expose the
following globals inside the sandboxed `jsRunner` / `interactive` iframe
**in addition to** our own `window.glaze.*` SDK:

### Phase 1 — jQuery shim
```js
window.jQuery = window.$ = createJQueryShim();
```

Minimal jQuery subset (covers ~95% of Monblant script usage):
- Selector: `$(selector)` returns chainable jQuery-like object
- DOM: `.append / .prepend / .html / .text / .attr / .css / .addClass / .removeClass / .toggleClass / .on / .off / .trigger / .find / .closest / .parent / .children / .eq / .first / .last`
- AJAX: `$.ajax({ url, type, data, headers, success, error })` — routes through `glaze.generateText` proxy
- Utilities: `$.extend / .inArray / .grep / .map / .each / .parseHTML`

Full jQuery event delegation, Sizzle selectors, and animation engine are
**not** emulated. Monblant scripts that use those need light rewriting.

### Phase 2 — `getContext()` shim
```js
window.SillyTavern = window.SillyTavern || {};
SillyTavern.getContext = async () => ({
  chat: [...],                          // current messages (from MessageVariables)
  characterId: 'uuid',                  // current character
  chatId: 'uuid',                       // current session id
  characters: [...],                    // all characters
  groups: [],                           // (always empty — MVP no groups)
  name1: 'Char Name',                   // {{char}}
  name2: 'User',                        // {{user}}
  description: '...',                   // {{description}}
  personality: '...',                   // {{personality}}
  scenario: '...',                      // {{scenario}}
  persona: '...',                       // {{persona}}
  systemPrompt: '...',                  // {{systemPrompt}}
  isChatBusy: false,                    // INV-C1
  apiProvider: 'openai',                // current API
  apiModel: 'gpt-4o',                   // current model
  onlineStatus: 'online',
  maxContext: 8192,
  streamingProcessor: 'normal',
  ...
});
```

`getContext` returns a *frozen* snapshot — mutating the object does not
propagate back. Use `glaze.setVariables('chat', ...)` to persist changes.

### Phase 3 — `eventOn / eventOff / eventEmit` shim
```js
window.eventOn = (event, handler) => /* register listener */;
window.eventOff = (event, handler) => /* remove listener */;
window.eventEmit = (event, data) => /* fire */;
```

**Events we support** (bridged from our pipeline):
- `MESSAGE_RECEIVED` — fired after assistant message persisted
- `MESSAGE_SENT` — fired after user message persisted
- `MESSAGE_SWIPED` — fired on swipe (Phase 6)
- `CHAT_CHANGED` — fired on session switch
- `CHARACTER_MESSAGE_RENDERED` — fired when assistant message displayed
- `USER_MESSAGE_RENDERED` — fired when user message displayed
- `GENERATION_ENDED` — fired after main gen ends (success or abort)
- `GENERATION_STARTED` — fired before main gen
- `EXTENSION_SETTINGS_UPDATED` — fired when user changes settings

Payload shape mirrors ST's `event_data` field with our own fields where
ST has no equivalent (e.g. `genId` for cancellation).

### Phase 4 — `eventSource` shim
```js
window.eventSource = (event) => ({
  on(handler) { /* register */ },
  off(handler) { /* unregister */ },
});
```

`eventSource(event).on(handler)` is syntactic sugar for
`eventOn(event, handler)`. Subscribing to `eventSource.make(event, ...)`
for *creating* new event types is **not supported** — Monblant scripts
that do this need rewriting.

### Phase 5 — `saveChatDebounced()` shim
```js
window.saveChatDebounced = async () => {
  // Persist the in-memory chat state back to our storage.
  // Monblant scripts mutate `getContext().chat` and call this to commit.
  // We diff against the persisted session vars and atomic-write the diff.
};
```

**Implementation note:** `saveChatDebounced` accumulates changes in a
300ms debounce window, then atomic-writes the merged diff to
`ChatSession.sessionVars`. Scripts that need immediate persistence can
call `glaze.setVariables('chat', ...)` directly.

### Phase 6 — `modifyChat` / `insertMessage` / `setChatMessages` shim
```js
window.modifyChat = async (modifier) => /* atomic update session via repo */;
window.insertMessage = async (message, options) => /* append/replace message */;
window.setChatMessages = async (chat) => /* replace entire session */;
window.appendMessageToChat = async (message, options) => /* append-only */;
window.deleteMessage = async (messageId) => /* remove */;
```

All mutations go through `ChatRepo.updateMessages()` (new atomic method
added in this phase) — no raw `getById` + `put`.

### Phase 7 — `extension_settings` shim
```js
window.extension_settings = {
  'extblocks': { /* per-preset settings, namespaced */ },
  /* ...other extensions... */
};
window.loadExtensionSettings = async (id) => { /* hydrate */ };
window.saveExtensionSettingsDebounced = async () => { /* persist */ };
window.getContext = async () => /* includes extension_settings */;
```

Stored in `SharedPreferences['glaze.ext_settings.<preset_id>.<ext_id>']`.
**Scoped to the active preset** to avoid cross-preset leaks.

### Phase 8 — `getRequestHeaders()` shim
```js
window.getRequestHeaders = async () => ({
  'Content-Type': 'application/json',
  'Authorization': 'Bearer <key>',   // from active API config
  'x-api-key': '<key>',              // Anthropic-style alt
  'anthropic-version': '2023-06-01',
  ...
});
```

**Security:** keys never leave Dart — the shim is callable, but the
`Authorization` value is fetched from the active `ApiConfig` and only
included for cross-origin requests to the matching API endpoint. The shim
is **capability-gated** by `glaze.makeHttpRequest` (Phase 9), not exposed
to scripts that don't need it.

### Phase 9 — Slash command shim
```js
window.registerSlashCommand = (name, callback, options) => /* register */;
window.executeSlashCommand = async (text) => /* parse + dispatch */;
```

Implemented as a thin wrapper over our `CommandRegistry` (Phase 16 of
this RFC). STScript syntax (`/command key=value "arg with spaces"`)
is parsed by a best-effort regex parser.

---

## 5. Macros

### Phase 10 — ST-style macros

We already support `{{char}}`, `{{user}}`, `{{description}}`, `{{personality}}`.
**New macros to add:**

| Macro | Maps to |
|---|---|
| `{{lastMessageId}}` | Last `ChatMessage.id` |
| `{{lastMessage}}` | Last `ChatMessage.content` |
| `{{lastCharMessage}}` | Last assistant message content |
| `{{lastUserMessage}}` | Last user message content |
| `{{scenario}}` | `Character.scenario` |
| `{{persona}}` | Active persona name (from `PersonaRepo`) |
| `{{systemPrompt}}` | Full main system prompt |
| `{{chat}}` | Full chat log (joined) |
| `{{exampleDialogue}}` | Character's example dialogue |
| `{{wiBefore}}`, `{{wiAfter}}`, `{{wiExamples}}`, `{{wiDepth}}`, `{{wiAll}}` | Lorebook macros (MVP stub: empty) |

### Phase 14 — ExtBlocks-specific macros

| Macro | Behavior |
|---|---|
| `{{ExtBlocks::block_name}}` | Reads the last stored state of the block named `block_name` (calls `BlockService.getPreviousBlockContext(block, msgId, true)`) |
| `{{ExtBlocks-GetBlockByName::block_name}}` | Alias of above |
| `{{ExtBlocks-Call::name1,name2::prompt}}` | Calls `BlockService.generateBlocksByName([name1, name2], prompt)` — inline block generation |
| `{{ExtBlocks-CallRewrite::name::prompt}}` | Calls `BlockService.rewriteBlocksByName([name], prompt)` |
| `{{ExtBlocks-CallScript::name1,name2}}` | Calls `BlockService.executeScriptsByName([name1, name2])` |

---

## 6. BlockService JS API (Phase 17)

Mirrors Monblant's `BlockService` so existing scripts that use
`BlockService.getAllBlocks()`, `BlockService.getPreviousBlockContextUnconditional(...)`,
etc. work as-is:

```js
window.BlockService = {
  getAllBlocks: () => [...blocks],            // all enabled + disabled
  getBlocksByType: (types, enabledOnly) => [...],
  getAllEnabledBlocks: () => [...],
  getAllPreviousBlocks: () => '...',          // joined string
  getPreviousBlockContextUnconditional: (block, messageId, mayCurrent, count) => '...',
  injectBlock: (blockState, blockConfig) => { /* call glaze.injectPrompt */ },
  addBlocksToExtra: async (messageId, blocksStr) => { /* append */ },
  purgeBlocksExtra: async (messageId) => { /* clear */ },
  updateBlocksDisplay: async (messageId) => { /* re-render */ },
  selfReloadCurrentChat: async () => { /* re-fetch from DB */ },
};
```

`MessageId` is a Monblant concept (numeric index into `chat` array). We
map it to our `ChatMessage.id` (UUID) by index lookup.

---

## 7. Plugins (Phase 18)

Monblant exposes `GeneratedPlugin`, `RewritePlugin`, `AccumulationPlugin`,
`ScriptPlugin`. We re-implement them as thin wrappers over our pipeline:

| Monblant plugin | Our pipeline target |
|---|---|
| `GeneratedPlugin.generateBlockContent(blocks, msgId, allBlocks, additionalMacro)` | `InfoBlockService.generateSingleBlockContent` |
| `GeneratedPlugin.execute(blocks, options)` | New `GeneratedBridge.execute()` |
| `RewritePlugin.generateRewrite(block, msgId, allBlocks, additionalMacro)` | New `RewriteBridge.generate()` |
| `RewritePlugin.execute(blocks, options)` | New `RewriteBridge.execute()` |
| `AccumulationPlugin.execute(blocks, options)` | New `AccumulationBridge.execute()` (YAML + MongoDB) |
| `ScriptPlugin.execute(blocks, options)` | New `ScriptBridge.execute()` (JS + STScript) |
| `GenerationService.handleBlocksGeneration(...)` | New `GenerationServiceBridge.handle()` |

`ScriptPlugin.execute({ execution_order: 'before' \| 'after' })` filters
blocks by execution order. We support both 'before' and 'after'.

---

## 8. Triggers (Phase 15)

| Monblant trigger | Our trigger | Implementation |
|---|---|---|
| `User Message` | `BlockTrigger.afterUser` | **Existing.** `ChatNotifier.sendMessage` → `unawaited(_dispatchAfterUserBlocks(...))`. |
| `Char Message` | `BlockTrigger.afterAssistant` | **Existing.** `ExtensionPostGenService.processAfterGeneration`. |
| `Swipe` | New `BlockTrigger.swipe` | Wire to `ChatNotifier.regenerateLastAssistant` / `_replaceSwipe`. |
| `Generation Pause` | New `BlockTrigger.generationPause` | New SSE-stream keyword detector. |
| `Periodic (period)` | `BlockTrigger.periodic` extended | New `period: int` field. Counter: `messageCount % period == 0`. |
| `Periodic (keyword)` | `BlockTrigger.periodic` extended | New `keyword: String` field. Detector scans LLM output for substring match. |
| `Periodic (interval)` | `BlockTrigger.periodic` (existing) | Already supported via `periodicIntervalSeconds`. |

---

## 9. Block injection (Phase 19)

| Monblant injection | Our support |
|---|---|
| Role: `system / assistant / user` | New `injectRole: InjectRole` enum. |
| Position: `After Main Prompt` | New `injectPosition: afterMainPrompt`. Inserts at start of system message body. |
| Position: `Before Main Prompt` | New `injectPosition: beforeMainPrompt`. Inserts before system message entirely. |
| Position: `In Chat` (depth) | **Existing** — `injectLastN` (positive = from end, 0 = disabled). Extend to support **negative depth** (from start, e.g. `-3` = first 3 messages). |
| `injectPrefix` | **Existing** — string prepended to each injection. |

---

## 10. Connection profiles (Phase 13)

Monblant's "API Presets" map directly to our `ConnectionProfiles`:

| Monblant | GlazeFlutter |
|---|---|
| `API Presets` (Big/Medium/Small) | `ExtensionPreset.connectionProfiles.{big,medium,small}` |
| `Connection Profile` (ST-side) | `ApiConfig` (in our `ApiConfigs` table) |
| Battery-icon preset selector on a block | New `BlockConfig.apiConfigSlot: 'big' \| 'medium' \| 'small'` |

Block-level preset selector: when `BlockConfig.apiConfigSlot` is non-empty,
the block uses the `ConnectionProfiles.<slot>.apiConfigId` instead of
`BlockConfig.apiConfigId` directly. Mirrors Monblant's cycle-through icon.

---

## 11. Slash commands (Phase 16)

| Command | Maps to |
|---|---|
| `/extblocks-generate name="block1,block2" is_separate=true additional_prompt` | `GenerationServiceBridge.handle({ trigger: 'manual', names: [...], isSeparate, additionalPrompt })` |
| `/extblocks-regenerate` | Re-run the last triggered block group |
| `/extblocks-flushinjects` | `glaze.uninjectPrompt` for all injected blocks |
| `/extblocks-storage-append message` | `BlockService.addBlocksToExtra(lastMessageId, message)` |
| `/extblocks-storage-purge` | `BlockService.purgeBlocksExtra(lastMessageId)` |
| `/extblocks-storage-export` | New system message with all previous block states |
| `/extblocks-rewrite name="..." additional_prompt` | `RewriteBridge.execute` |
| `/extblocks-execute-script name="script1,script2"` | `ScriptBridge.execute` |
| `/extblocks-abort-generation` | Cancel current block gen |
| `/extblocks-status [on|off]` | Toggle extension globally |
| `/extblocks-block-status name="..." [scope] [on|off]` | Toggle specific block |

The current `/trigger`, `/getvar`, `/setvar`, `/inject`, `/toast` we
already wired in `WiredCommandRegistry` (Phase 5 of js-extensions MVP)
stay as is. The `/extblocks-*` namespace is new.

---

## 12. UI changes (Phase 20)

In the preset editor (`preset_editor_screen.dart`):

| Element | Behavior |
|---|---|
| Preset top bar | Add buttons: **Import preset JSON** (file picker), **Export preset JSON** (download) |
| Block editor dialog | New fields: `isRewrite`, `isAccumulative`, `period`, `keyword`, `updaterBlockId`, `injectPosition`, `injectRole`, `injectDepth` (sign-aware), `scriptType` (`js` / `stscript`), `background`, `parallel` |
| Block row | Battery-icon for `apiConfigSlot` (Big/Medium/Small/None) — cycle on tap |

In the extensions screen (`extensions_screen.dart`):

| Element | Behavior |
|---|---|
| Settings group | Add **Import from Monblant preset (.json)** action |

---

## 13. Embedded blocks (Phase 21)

Monblant stores blocks in two places:
1. **Preset** (global) — we already have this
2. **Character card** (`character.data.extensions.extblocks_blocks`) — we
   need to read/write `Character.extensions['extblocks_blocks']`

**Implementation:** new atomic method `CharacterRepo.updateExtblocksBlocksJson(charId, updater)`
mirrors the existing `updateExtensionsJson`. Preset editor distinguishes
"Preset blocks" vs "Embedded blocks" tabs (Monblant's UI).

---

## 14. Test plan (Phase 22)

| Test file | Cases | What it pins |
|---|---|---|
| `test/monblant_jquery_shim_test.dart` | 12 | Selector, DOM, AJAX routing, utilities |
| `test/monblant_getcontext_shim_test.dart` | 8 | Snapshot shape, frozen, name1/name2/char/user/... |
| `test/monblant_event_shim_test.dart` | 10 | eventOn/Off/Emit + Monblant payload shape |
| `test/monblant_save_chat_shim_test.dart` | 6 | Debounce + atomic write |
| `test/monblant_modify_chat_shim_test.dart` | 9 | modify/insert/setMessages/append/delete atomicity |
| `test/monblant_extension_settings_shim_test.dart` | 5 | Per-preset namespace, debounced persist |
| `test/monblant_request_headers_shim_test.dart` | 4 | Auth key never leaves Dart, scoped to active API |
| `test/monblant_macros_test.dart` | 8 | All new macros expand correctly |
| `test/monblant_blockservice_test.dart` | 12 | All BlockService JS API methods |
| `test/monblant_plugins_test.dart` | 10 | Plugin execute paths |
| `test/monblant_triggers_test.dart` | 8 | Swipe, generationPause, period, keyword |
| `test/monblant_inject_test.dart` | 6 | All inject positions + roles |
| `test/monblant_connection_profile_test.dart` | 5 | Battery-icon cycling, slot override |
| `test/monblant_slash_commands_test.dart` | 11 | All /extblocks-* commands |
| `test/monblant_preset_import_test.dart` | 6 | Read Monblant JSON, field mapping |
| `test/monblant_embedded_blocks_test.dart` | 4 | Read/write char.extensions.extblocks_blocks |
| `test/monblant_rewrite_block_test.dart` | 6 | Rewrite pipeline: LLM → replace last message |
| `test/monblant_accumulative_block_test.dart` | 8 | YAML state, $set/$inc/$push/$pull updater |
| `test/monblant_integration_tarot_test.dart` | 1 | **Real Monblant Tarot script — imports as-is and runs** |

**Total: ~140 new test cases, plus the integration test that imports
the real `tavern_helper_script-🔮 Tarot EXT-BLOCKS.json` and verifies it
parses the `<tarot>` tag from a fake LLM response and stores it via
`saveChatDebounced` round-trip.**

---

## 15. Out of scope (explicitly not implemented)

These are ST-runtime concepts we **do not** emulate because they conflict
with our architecture, security model, or simply aren't useful for the
use case:

| ST concept | Why skipped |
|---|---|
| ST's full `eventSource` with `event_types` registration | We expose a fixed event catalog. Custom event types are not supported. |
| ST's DOM (`#chat`, `#send_textarea`, `#option_*`) | We render in our own isolated containers. Scripts that target ST DOM need rewriting. |
| ST's `/api/backends/...` HTTP proxy | Our own `glaze.generateText` is the only LLM path. Scripts that need raw HTTP use `glaze.makeHttpRequest` (capability-gated). |
| ST's world info (lorebook) engine | Out of scope — Phase 25 (separate sprint). |
| ST's regex/preset scripts | Not part of ExtBlocks, out of scope. |
| ST's character group chats | Not in our MVP. |
| ST's full STScript parser | Best-effort subset only. Complex STScripts need rewriting as JS. |
| ST's "vector storage" / long-term memory | Out of scope. |
| ST's quick reply / hotkeys | Out of scope. |

---

## 16. Migration example: Tarot script

Original Monblant Tarot script (from `tavern_helper_script-🔮 Tarot EXT-BLOCKS.json`,
27 KB) uses:
- `window.jQuery` (DOM manipulation in ST chat)
- `extension_settings[tarot]` (config)
- `eventSource.on('MESSAGE_RECEIVED', ...)` (re-render on new message)
- `getContext().chat` (read messages)
- `saveChatDebounced()` (persist state)
- `modifyChat(...)` (mutate last message)
- `#chat` direct DOM access
- `eventEmit('MESSAGE_RENDERED', ...)` (custom events)
- `<tarot>` tag parsing in assistant output

**After our shim layer (Phase 1-9), expected behavior:**

| Monblant call | Our shim | Works as-is? |
|---|---|---|
| `$(selector)` | jQuery shim (subset) | ⚠️ Partial — selectors that match DOM nodes we render. |
| `window.jQuery.ajax(...)` | Routes through our shim (which calls `glaze.makeHttpRequest`) | ✅ Yes, but auth header is auto-injected. |
| `extension_settings['tarot']` | Per-preset namespace | ✅ Yes. |
| `eventSource.on('MESSAGE_RECEIVED', ...)` | eventSource shim | ✅ Yes. |
| `getContext().chat` | Frozen snapshot | ⚠️ Yes for read, mutations don't propagate (use `modifyChat`). |
| `saveChatDebounced()` | Atomic write | ✅ Yes. |
| `modifyChat(...)` | Atomic session update | ✅ Yes. |
| `#chat` direct DOM | Our container has its own root | ❌ No — need to use `glaze.renderPanel(html)` instead. |
| `eventEmit('MESSAGE_RENDERED', ...)` | eventEmit shim | ✅ Yes (within our event catalog). |
| `<tarot>` tag parsing | Pure regex in script | ✅ Yes. |

**Migration cost for Tarot:** ~30 minutes of light edits to:
- Replace `$('#chat').append(...)` with `glaze.renderPanel(...)`
- Replace direct DOM queries with `glaze.querySelector` (capability-gated)
- The rest works as-is

This is the **target compatibility bar** for Phase 22's integration test.

---

## 17. Risk register

| Risk | Mitigation |
|---|---|
| jQuery shim diverges from real jQuery on edge cases | Limit to Monblant-observed usage; document unsupported features. |
| `modifyChat` race with active generation | Mutex with `ChatNotifier`; reject if INV-C1 busy. |
| `getRequestHeaders` leaks API key | Capability-gated + scoped to matching API origin. |
| STScript parser incomplete | Document supported subset; recommend rewriting as JS. |
| `eventSource` subscription leaks | Auto-cleanup on iframe dispose. |
| 4-5 week timeline slips | Each phase is independent + revertable; can ship subset early. |
| Monblant ships breaking changes | Pin to their `1.0.1` (current manifest version); subscribe to upstream RSS. |

---

## 18. Open questions for lead developer

1. **Storage of `extension_settings`:** `SharedPreferences` (per-preset namespace) or new Drift table `ExtensionSettings` (more queryable)?
2. **Embedded blocks in character cards:** read-only from presets (use preset), or allow per-character overrides? (Monblant allows both.)
3. **Rewrite block side effects:** when `isRewrite: true` triggers, do we preserve the *original* response anywhere (e.g. as `info_block` history), or fully replace?
4. **Accumulative block state lifetime:** per-session (Monblant default) or per-character (persistent across sessions)?
5. **STScript parser effort:** best-effort regex subset (3 days) or full recursive-descent parser (1 week)?
6. **`/extblocks-storage-export` format:** plain text, YAML, or JSON?

---

## 19. Approval & sign-off

- [ ] Lead developer review
- [ ] Timeline confirmation (4-5 weeks)
- [ ] Open questions answered (Section 18)
- [ ] Migration target approved (Section 16 — Tarot as the reference script)

Once approved, Phase 1 (jQuery shim) begins immediately.
