# Plan: Agentic Studio — Marinara-Style Refactor

> **Status:** Draft. References `docs/PLAN_PIPELINE_SEPARATION.md`, `docs/ARCHITECTURE.md` § "Studio Mode Pipeline".
> **Goal:** Удешевить агентику на большом контексте, ресторить урезанный UI, упростить ментальную модель памяти.
> **Reference:** [Pasta-Devs/Marinara-Engine](https://github.com/Pasta-Devs/Marinara-Engine) — `packages/server/src/services/agents/` (agent-pipeline.ts, agent-executor.ts), `packages/shared/src/types/agent.ts`.

---

## 0. Постановка проблемы

### 0.1 Что не так сейчас

- **Дорого:** `MemoryStudioService.runPipeline` шлёт ~N×(фулл-промпт + фулл-история) на каждом ходу. На 100 сообщениях с большой картой — ~290k input/turn против ~40k у обычного режима (×7.3 оверхед). См. `lib/core/llm/memory_studio_service.dart:949` — intermediate-агенты получают `context.history` без трима; `maxFinalHistoryMessages=15` applies только к финалу.
- **UI похерен:** Двумя коммитами `dda65b6` и `9579d7e` (Jun 26 2026) из `studio_menu_dialog.dart` и `memory_generation_settings_sheet.dart` вырезано ~750 строк UI-конфигурации (POST-cleaner, агentic-write, sidecar-селекторы, generation/classifier/sidecar LLM поля). Всё переехало в `post_building_menu_dialog.dart` (491→1762 строк), но поверхность стала фрагментированной и запутанной.
- **Ментальная модель запутана:** 5 режимов памяти (`legacy`/`fast`/`balanced`/`deep`/`agentic`) + ортогональный Studio-перехват. `memory_studio_mode.dart` (95 строк) — мёртвый код. `memory_mode_studio` i18n-строка — orphan. `memory_book_controller.dart:139` неправильно репортит agentic как "Fast". Tool-schemas в `memory_agentic_tools.dart:10-134` определены, но не прикрепляются к LLM-вызовам — декоративны.

### 0.2 Что делает Marinara (референс)

1. **3 фазы вокруг одного генератора:** `pre_generation` (инъекты в промпт) → `parallel` (боковые трекеры во время генерации) → `post_processing` (правки ответа). Главный ответ пишет одна модель; агенты не дублируют генерацию.
2. **`recentMessages = last-N`, дефолт N=5** (`shared/types/agent.ts:DEFAULT_AGENT_CONTEXT_SIZE=5`, верхний кап `MAX_AGENT_CONTEXT_MESSAGES=200` — это две **разные** константы: дефолт vs hard-cap). Агенты получают `recentMessages.slice(-contextSize)` + `truncateAgentText(content, 2000)` + `stripHtmlTags`. **Важно:** `truncateAgentText` — это НЕ простая обрезка с конца. Если текст длиннее лимита, берётся **head 40% + маркер `[Trimmed to keep this agent request compact]` + tail 60%** — сохраняется и начало, и конец сообщения.
3. **Батчинг** агентов с одинаковым provider+model в один LLM-запрос (`agent-executor.ts:executeAgentBatch`) через `<agent_task>`-XML с парсингом `<result agent="...">`. Batch `maxTokens` = **СУММА** per-agent budgets (capped провайдером/моделью), `temperature` = **MIN** по группе. Legacy-fallback тег — `<result_TYPE>...</result_TYPE>` где `TYPE` = тип агента (`matchLegacyResultTag`), не `<result_type>`.
4. **Rolling summary + tail** для длинных RP — старые сообщения скрываются, остаётся tail + summary в `AgentContext.chatSummary` (`string | null` — подтверждено в типе; `null` для юзеров без summary).
5. **Per-agent connection override** — трекеры на Haiku/Flash, чат на Opus (`AgentConfig.connectionId`).
6. **`runInterval`** — часть трекеров запускается раз в N ходов, не каждый. Уже устоявшийся паттерн: `BUILT_IN_AGENT_RUN_INTERVAL_DEFAULTS` + `settings.runInterval` в shared.
7. **Конкурренси-лимиты:** `AGENT_PHASE_MAX_CONCURRENT_GROUPS=8`, `AGENT_GROUP_MAX_CONCURRENT_TOOL_CALLS=4`, `AGENT_BATCH_FALLBACK_MAX_CONCURRENT=4` + `maxParallelJobs`/`splitGroupForParallelJobs` (дробление группы на параллельные джобы). Не все агенты летят одновременно.
8. **Invalid-JSON retry:** до batch-fallback есть слой одиночного ретрая (`shouldRetryInvalidJsonAgent` → повтор со strict-JSON reminder).
9. **Фаза по типу:** `prose-guardian` и `continuity` **всегда** `post_processing` (`normalizeAgentPhaseForType`) — фаза не конфигурируется юзером.

### 0.3 Принцип рефактора

> **Не переписывать с нуля.** ~60% Studio-инфраструктуры утилизируется (cache, block-router, request-preset, StudioConfig/StudioAgent модель, DB schema, streaming scaffold). Удаляем оркестрацию 8-контроллеров и `AgentSwipe`, сохраняем остальное с семантической переинтерпретацией.

---

## 1. Целевая архитектура

### 1.1 Модель "трекеры вокруг генератора"

```
                  ┌─ pre_generation ─────────────────────────┐
                  │  [memory] [continuity] [director] ...    │
                  │  ↓ inject notes into prompt              │
  user turn  ────►│                                          │──► [main LLM] ──► response
                  │                                          │
                  │  parallel (fire alongside main gen):      │
                  │  [expression] [background] [world-state] │
                  │                                          │
                  │  post_processing (after response):       │
                  │  [prose-guardian] [continuity-check]     │
                  └──────────────────────────────────────────┘
```

- **Один генератор** (main LLM) пишет ответ. Трекеры — это sidecar-вызовы, не дублирующие генерацию.
- Трекеры получают **`recentMessages` (last-N, дефолт 5, hard-cap 200)** + char card + активные лорбуки + свой `promptShard`, а не фулл-историю. Per-message — `truncateAgentText` (head 40% + tail 60%) + `stripHtmlTags`.
- Трекеры с одинаковым provider+model **батчатся в один запрос** (`<agent_task>`-XML).
- `maxFinalHistoryMessages=15` остаётся у генератора — он опирается на трекер-значения (сжатый контекст), а не на сырой транскрипт.

### 1.2 Что сохраняется из существующего кода

| Компонент | Действие | Причина |
|---|---|---|
| `memory_studio_service.dart` `_briefCache` + refresh-policy (turn/scene/static) | **KEEP** | Трекеры кэшируются ещё лучше, чем briefs — меняются реже. |
| `memory_studio_service.dart` transport-request assembly + streaming scaffold | **SPLIT → `agent_runner.dart`** | Переиспользуется и генератором, и трекерами. |
| `studio_block_router.dart` | **REPURPOSE** | `blocks→buckets` = `preset→trackers`. Лучший фит. |
| `studio_request_preset.dart` (data shape) | **REPURPOSE** | `StudioRequestPreset` = named block list. Rewrite содержимое preset-ов. |
| `studio_config.dart` (`StudioConfig`/`StudioAgent`) | **REPURPOSE + MIGRATE** | `StudioAgent` уже = трекер. Модель сохраняется, но добавляются минимальные поля (`contextSize`, `runInterval`, `maxParallelJobs`). |
| `tables.dart` `StudioConfigRows` + `TrackerRows` | **KEEP + MIGRATE** | Таблицы уже сосуществуют; схема переиспользуется, но получит точечные миграции под новые tracker-поля. |
| `studio_decomposition_service.dart` `_synthesizeRoutedShard` | **SPLIT → 20-line util** | Verbatim-блок-конкатенация. |
| `studio_decomposition_service.dart` (8-slot decomposition) | **DELETE** | Это что Marinara отбрасывает. |
| `memory_studio_mode.dart` (95 lines) | **DELETE** | Мёртвый код. |
| `memory_mode_studio` i18n strings | **DELETE** | Orphans. |
| `AgentSwipe` / `agentSwipes` on `ChatMessage` + `studioFinalOnly` re-run | **DELETE** | Второе измерение swipe-ов для ре-рана одного intermediate. Нет intermediate → нет нужды. |
| `studioOutputs` per-message metadata | **REPURPOSE** | → "трекеры, поучаствовавшие в этом сообщении + их значения" (provenance). |

### 1.3 POST-processing policy

**Текущий POST-cleaner остаётся.** Он уже совпадает с правильной семантикой Marinara для rewrite-агентов: работает после полного ответа, а не пытается переписывать токены в real-time. Это нормальная модель для GlazeFlutter и её не нужно ломать ради копирования Marinara.

- **Не делаем hold mode.** Marinara умеет удерживать показ ответа за плейсхолдером, пока prose-guardian/continuity переписывают текст, но для нас это оверинжиниринг и ухудшает ощущение стрима. Оставляем текущий UX: ответ виден сразу, POST-cleaner потом предлагает/применяет diff.
- **Что можно улучшить:** добавить safety guard перед применением rewrite — не принимать cleaner-результат, если он потерял защищённые markdown/custom markers (`==...==`), fenced code blocks или HTML/XML-like теги, которые были в оригинале. Это дешёвое заимствование из Marinara `text-rewrite-safety.ts`, без hold-mode.
- **Continuity/prose rewrite не встраивать в Studio main stream.** Если continuity станет post-processing tracker, он должен отдавать отдельный rewrite/diff результат через существующую POST-cleaner-поверхность, а не мутировать токены во время генерации.

### 1.4 Связь с памятью (MemoryBook + memoryMode)

**MemoryBook-инжект НЕ пропадает при включении студии.** Подтверждено кодом:
- `prompt_payload_builder.dart` собирает MemoryBook injection в `payload.memoryContent` **до** studio-перехвата (`stream_generation_service.dart:89`).
- Studio-перехват (`:165`) получает тот же `payload`, передаёт в `runPipeline`.
- `_buildAgentMessages` (`memory_studio_service.dart:954`) блок `dynamic_context` добавляет memory в контекст каждого агента (`:1678`: `'memory'` в `dynamicIds`).
- Макрос `{{memory}}` в `promptShard`-ах раскрывается через `promptPayload.memoryContent` (`:1643`).

Память (`memoryMode`: fast/balanced/deep/agentic) **ортогональна трекерам** — как и сейчас. Memory injection идёт в `dynamic_context` блок пресета (не в `chat_history`), трекеры работают поверх уже-собранного контекста.

После трима last-N (Phase 3) — трим применяется **только к `chat_history` блоку** (`:948-952`). `static_context` (карточка, лорбуки) и `dynamic_context` (memory, summary, worldInfo) **остаются**. MemoryBook-записи продолжают инъектиться в трекер-контекст через `dynamic_context`, как и сейчас.

**Для пользователей без rolling summary:** долгую память покрывает MemoryBook (через `dynamic_context`), а не summary. Трим last-N безопасен — MemoryBook-записи (куртка, арки, лор) не зависят от длины истории, они статичный injection. `agentic-write-loop` (post-turn, уже есть) собирает факты в MemoryBook автоматически.

Трекер `memory` (если включён) — это **pre_generation трекер**, который может повлиять на injection (как agentic read loop сейчас). Остальные трекеры (continuity, world-state, expression, prose-guardian) — самостоятельны.

---

## 2. Фазы работ

### Phase 1 — Очистка мёртвого кода (нулевой риск, сразу)

**Цель:** убрать путаницу в ментальной модели перед рефактором.

> **Важно:** `memory_studio_mode.dart` — **частично живой**. `MemoryStudioSettings`/`MemoryStudioPolicy`/`MemoryStudioStage`/`MemoryStudioStagePlan`/`_defaultPipeline` — действительно мёртвые (`experimentalEnabled` нигде не выставляется в `true`, `canUseStage` всегда false, `defaultPipeline()` всегда `[]`). Но `MemoryStudioOutputDisposition` enum — **живой**: используется в `memory_studio_service.dart:444,482,503,544,2253` и `stream_generation_service.dart:644` как `StudioStageBrief.disposition`, причём **всегда `ephemeral`** (typing-маркер, не функциональная логика). Поэтому:
> - Phase 1 удаляет только мёртвые классы.
> - `MemoryStudioOutputDisposition` удаляется в **Phase 2** вместе с `StudioStageBrief` (когда оркестрация уходит, consumers пропадают).
>
> `PLAN_CONTINUITY_POST_CLEANER.md` и `PLAN_PIPELINE_SEPARATION.md` ссылаются на "Studio" как на живой `StudioConfig` + `studioOutputs` (freezed из `studio_config.dart`), **не** на `memory_studio_mode.dart`. Удаление мёртвых классов не ломает контракты этих планов.

- [ ] **1.1** `lib/core/llm/memory_studio_mode.dart`: оставить **только** `enum MemoryStudioOutputDisposition { ephemeral, proposed, canonical }` (строка 11). Удалить `enum MemoryStudioStage` (1-9), `class MemoryStudioSettings` (13-25), `class MemoryStudioStagePlan` (27-37), `class MemoryStudioPolicy` (39-95), `_defaultPipeline` (73-94). Проверить `grep -r "MemoryStudioPolicy\|MemoryStudioSettings\|MemoryStudioStage\|experimentalEnabled" lib/` — должен быть 0 ссылок вне файла.
- [ ] **1.2** Удалить `memory_mode_studio` и `memory_mode_studio_desc` i18n-ключи из `lib/i18n/en.json` и `lib/i18n/ru.json`.
- [ ] **1.3** Починить `memory_book_controller.dart:139` — `settingsSummary` должен репортить `agentic` корректно (сейчас falls through к "Fast").
- [ ] **1.4** Решить судьбу tool-schemas в `memory_agentic_tools.dart:10-134`: либо прикрепить к реальным LLM-вызовам (если переходим на OpenAI tool-calling в трекерах), либо удалить декоративные schema-definitions и оставить только `MemoryAgenticToolHandler.searchMemory` (handler используется, schema — нет). **Решение отложить до Phase 5** (батчинг vs tool-calling — альтернативные пути).
- [ ] **1.5** `flutter analyze` + `flutter test` — убедиться что ничего не сломалось. `MemoryStudioOutputDisposition.ephemeral` references в `memory_studio_service.dart` и `stream_generation_service.dart` должны компилиться (enum остался).

**Файлы:** `memory_studio_mode.dart` (trim, не delete), `en.json`/`ru.json` (edit), `memory_book_controller.dart` (edit).
**Оценка:** 0.5-1 день.
**Риск:** минимальный — мёртвый код. `MemoryStudioOutputDisposition` остаётся живым до Phase 2.

### Phase 2 — Удаление дорогой оркестрации (high impact, medium risk)

**Цель:** снести 8-контроллерный pipeline, оставить один генератор + трекеры.

- [ ] **2.1** SPLIT из `memory_studio_service.dart` транспорт-запрос-сборку + streaming scaffold → новый `lib/core/llm/agent_runner.dart` (тонкий orchestrator: build request → call LLM → stream → accumulate → return). ~150-200 строк. Используется и генератором, и трекерами.
- [ ] **2.2** SPLIT из `studio_decomposition_service.dart` `_synthesizeRoutedShard` → `lib/core/llm/verbatim_shard_assembler.dart` (~20 строк, standalone util).
- [ ] **2.3** DELETE `studio_decomposition_service.dart` (остаток после split) — 8-slot `_ControllerSpec` ontology. Проверить `grep -r "studio_decomposition\|StudioDecomposition\|_ControllerSpec" lib/` — обновить вызовы.
- [ ] **2.4** DELETE `AgentSwipe` / `agentSwipes` / `agentSwipeId` из `ChatMessage` freezed-модели + `_syncAgentSwipesToMeta` из `chat_repo.dart` + `studioFinalOnly` re-run branch из `stream_generation_service.dart:207-226`.
  - **Перед удалением freezed:** `dart run build_runner build` регенерит `.freezed.dart`. Сначала отредактировать `chat_message.dart` (убрать поля), потом `build_runner`.
  - **Не забыть:** DB-миграция `ChatMessages` если `agent_swipes_json` колонка существует. Проверить `tables.dart` `ChatMessages` схему + migration log.
- [ ] **2.5** REPURPOSE `studioOutputs` на `ChatMessage` → `trackerProvenanceJson` (или оставить имя `studioOutputs` во избежание миграции, но переименовать в коде через alias). Хранит `{trackerId, value, contributedAt}` для дебага.
- [ ] **2.5b** После удаления `StudioStageBrief` (в 2.6) — consumers `MemoryStudioOutputDisposition` в `memory_studio_service.dart:444,482,503,544,2253` и `stream_generation_service.dart:644` пропадают. Удалить `MemoryStudioOutputDisposition` enum из `memory_studio_mode.dart` → файл становится пустым → удалить `memory_studio_mode.dart` целиком. Обновить imports в `memory_studio_service.dart:19` и `stream_generation_service.dart:11`.
- [ ] **2.6** Переписать `memory_studio_service.dart` `runPipeline` → `runTrackerCycle`:
  - Убрать `intermediateAgents`/`finalAgent`-сплит.
  - Одна фаза: pre_generation трекеры (батч) → main gen (использует `agent_runner`) → parallel трекеры (батч, fire alongside) → post_processing трекеры (батч).
  - `_buildAgentMessages` больше не дублирует фулл static_context на каждый агент — shared-часть один раз, agent-specific `promptShard` в `<agent_task>`-блоке.
- [ ] **2.7** Починить дубль `buildPromptInIsolate` в `stream_generation_service.dart:89,170` — вызывать один раз.
- [ ] **2.8** `flutter analyze` + `flutter test` + мануальный smoke-тест генерации с одним трекером.

**Файлы:** `memory_studio_service.dart` (rewrite), `studio_decomposition_service.dart` (delete), `memory_studio_mode.dart` (delete — после 2.6), `agent_runner.dart` (new), `verbatim_shard_assembler.dart` (new), `chat_message.dart`+`.freezed.dart` (edit), `chat_repo.dart` (edit), `stream_generation_service.dart` (edit), `tables.dart` (если миграция).
**Оценка:** 3-5 дней.
**Риск:** средний — трогаем core-generation path. Тесты обязательны. `memory_studio_mode.dart` удаляется **только после** 2.6 (когда `StudioStageBrief` и `MemoryStudioOutputDisposition` consumers пропадут).

### Phase 3 — Контекст-трим для трекеров + явный MemoryBook-инжект (high impact, low risk)

**Цель:** трекеры получают last-N историю + явный MemoryBook-контекст, не фулл-транскрипт.

> **Важно — MemoryBook-инжект НЕ пропадает при включении студии.** Сейчас:
> - `prompt_payload_builder.dart` собирает MemoryBook injection в `payload.memoryContent` **до** studio-перехвата (`stream_generation_service.dart:89`).
> - Studio-перехват (`:165`) получает тот же `payload` и передаёт в `runPipeline`.
> - В `_buildAgentMessages` (`memory_studio_service.dart:954`) блок `dynamic_context` добавляет `context.dynamicContext`, куда входит `memory` (`:1678`: `'memory'` в `dynamicIds`).
> - Макрос `{{memory}}` в `promptShard`-ах агентов раскрывается через `promptPayload.memoryContent` (`:1643`).
>
> То есть **каждый агент сейчас получает MemoryBook-записи** через `dynamic_context`. После трима истории — MemoryBook-записи **остаются** (они не история, а статичный injection). Трим касается только `chat_history` блока (`:948-952`).
>
> **Это значит:** пользователь, играющий только с MemoryBook (без rolling summary), **не теряет долгосрочную память** при триме. Куртка, потерянная на ходу 30, найдётся через MemoryBook-запись (созданную agentic-write-loop или вручную), инъектируется в трекер-контекст через `dynamic_context` блок, как и сейчас. Трим last-N касается только сырого чата — MemoryBook, lorebooks, char card, tracker state остаются в промпте трекера.

- [ ] **3.1** Добавить в `StudioAgent` поле `contextSize` (default = `DEFAULT_AGENT_CONTEXT_SIZE` = **5**, hard-cap = `MAX_AGENT_CONTEXT_MESSAGES` = **200**). Это две разные константы: дефолт на трекер vs верхний предел при нормализации (`normalizeAgentContextSize` клампит в `[1, 200]`). Если имя `StudioAgent` сохраняется, поле `contextSize` добавляется в freezed-модель + `StudioConfigRows` schema (Drift migration +1 колонка).
- [ ] **3.2** В `agent_runner.dart` (или в новой `_buildTrackerMessages`) срезать `context.history` → `context.recentMessages = history.slice(-contextSize)` + per-message `truncateAgentText(content, 2000)` + `stripHtmlTags`.
  - **`truncateAgentText` портировать точно:** если `length > maxChars` → `head(40%) + "\n\n[Trimmed to keep this agent request compact]\n\n" + tail(60%)`, считая по символам (`Array.from` для корректной обработки юникода/эмодзи). Простая обрезка с конца теряет начало сообщения — не годится.
  - `stripHtmlTags`: `<\/?[a-zA-Z][^>]*>` → "", схлопнуть `\n{3,}` → `\n\n`, trim.
  - **Трим применяется ТОЛЬКО к `chat_history` блоку** (`memory_studio_service.dart:948-952`).
  - `static_context` (char_card, persona, scenario, lorebooks) и `dynamic_context` (memory, summary, worldInfoBefore/After, guided_generation) **остаются как есть** — они не история.
- [ ] **3.3** У генератора оставить `maxFinalHistoryMessages=15` (поле уже есть в `StudioConfig`).
- [ ] **3.4** Если есть `chatSummary` (rolling summary из MemoryBook) — инъектить в трекер-контекст как замену удалённой истории (как Marinara's `AgentContext.chatSummary`). Для пользователей без summary — этот слой пустой, MemoryBook покрывает долгую память через `dynamic_context`.
- [ ] **3.5** Тест: на 100-сообщ-сессии с включённой студией, input-tokens/turn должен упасть с ~290k до ~15-25k (1 генератор + 2-3 трекера × small-context). Проверить что MemoryBook-записи всё ещё видны в трекер-контексте через `dynamic_context`.
- [ ] **3.6** `flutter analyze` + `flutter test`.

**Файлы:** `studio_config.dart` (edit), `tables.dart` (migration), `agent_runner.dart` (edit), `memory_studio_service.dart` (edit — только `:948-952` трим chat_history).
**Оценка:** 1-2 дня.
**Риск:** низкий — трим только `chat_history` блока; `static_context` и `dynamic_context` (включая memory) не трогаем. MemoryBook-инжект продолжает работать as-is.

### Phase 4 — Вырезать `agentic` из MemoryBook modes (medium impact, medium risk)

**Цель:** MemoryBook перестаёт иметь режим `agentic`. MemoryBook отвечает за retrieval/data policy (`legacy`/`fast`/`balanced`/`deep`), а LLM-agent слой становится отдельным pre-generation memory tracker / pipeline toggle.

**Почему:** `agentic` сейчас смешивает две разные оси:
- `fast`/`balanced`/`deep` = насколько глубоко и дорого искать/ранжировать MemoryBook entries.
- `agentic` = LLM sidecar/query-gen поверх retrieval (`MemoryAgenticService.runAgentic`). Это не retrieval depth, а отдельный агентный слой.

**Целевая модель:**

```text
MemoryBook retrieval mode: legacy / fast / balanced / deep
Memory agent / tracker: off / on
Agentic write-loop: отдельный pipeline toggle (уже есть agenticWriteEnabled)
```

- [ ] **4.1** `MemoryBookSettings.memoryMode`: допустимые значения нормализовать до `legacy`/`fast`/`balanced`/`deep`. `agentic` больше не показывать и не сохранять из UI.
- [ ] **4.2** JSON migration при чтении старых MemoryBook settings: если `memoryMode == 'agentic'`, маппить в `deep` (лучший backward-compatible выбор, потому что старый agentic требовал sidecar и был дорогим) и отдельно включать новый memory-agent слой, если он уже доступен в этой фазе. Если нового флага ещё нет — только `deep`, без silent LLM calls.
- [ ] **4.3** `memory_generation_settings_sheet.dart`: убрать `ButtonSegment(value: 'agentic')`, убрать `memory_mode_agentic_desc`, `_normalizeMode('agentic')` → `deep`, `_needsSidecar` должен зависеть только от `deep` (или от нового memory-agent toggle, когда он появится), не от `agentic`.
- [ ] **4.4** `post_building_menu_dialog.dart`: убрать `_memoryMode == 'agentic'` из `_sidecarLocked` и auto-enable sidecar условия. Sidecar lock остаётся для `deep` только до тех пор, пока deep действительно требует sidecar rerank.
- [ ] **4.5** `memory_book_controller.dart:settingsSummary`: убрать special-case/bug вокруг `agentic`; после migration неизвестные значения не должны падать в "Fast" молча — использовать `normalizeMemoryMode` helper или явный fallback `fast`.
- [ ] **4.6** `memory_injection_service.dart`: убрать условие `book.settings.memoryMode == 'agentic'` как trigger для `MemoryAgenticService`. Agentic read должен запускаться только через новый pre-generation `memory` tracker / pipeline flag, не через MemoryBook mode.
- [ ] **4.7** `memory_agentic_service.dart`: обновить комментарии и API. Сервис больше не говорит "When `memoryMode == 'agentic'`"; он становится implementation detail для memory tracker / agentic read. `MemoryAgenticPolicy.enabled` получать из явного флага, а не из settings.memoryMode.
- [ ] **4.8** i18n: удалить/пометить obsolete `memory_mode_agentic`, `memory_mode_agentic_desc` из `en.json`/`ru.json`, если больше нет ссылок.
- [ ] **4.9** Tests/smoke:
  - Старый MemoryBook JSON с `memoryMode: "agentic"` читается как `deep` и не крашит UI.
  - В MemoryBook selector видны только `legacy`/`fast`/`balanced`/`deep`.
  - Agentic write-loop (`agenticWriteEnabled`) продолжает работать независимо от retrieval mode.
  - `flutter analyze` + `flutter test`.

**Файлы:** `memory_book.dart` (+ generated), `memory_generation_settings_sheet.dart`, `post_building_menu_dialog.dart`, `memory_book_controller.dart`, `memory_injection_service.dart`, `memory_agentic_service.dart`, i18n JSON. Возможно `pipeline_settings.dart` / `studio_config.dart`, если explicit memory-agent toggle вводится уже здесь.
**Оценка:** 1-2 дня.
**Риск:** средний — меняется persisted setting semantics. Митигировать JSON migration и отсутствием silent agentic calls.

### Phase 5 — Батчинг трекеров в один LLM-запрос (high impact, medium risk)

**Цель:** трекеры с одинаковым provider+model → один запрос через `<agent_task>`-XML.

- [ ] **5.1** Реализовать `executeTrackerBatch` в `agent_runner.dart` (порт `agent-executor.ts:executeAgentBatch`):
  - `buildBatchSystemPrompt`: `<role>` + `<lore>` (shared) + `<agents>` с `<agent_task id="..." name="...">template</agent_task>` (значения макросов **escape-XML**!) + extras + `─── REQUIRED OUTPUT FORMAT ───` с `<result agent="...">` блоками + CRITICAL-инструкция перечислить все agent IDs.
  - **Batch budget:** `batchMaxTokens` = СУММА `maxTokens` всех агентов группы, затем cap провайдером (`maxTokensOverrideValue`) и моделью (`maxOutputTokens`). `temperature` = MIN по группе. Если не суммировать — длинный батч обрежется на полпути и половина `<result>` блоков пропадёт.
  - `parseBatchResponse`: extract `<result agent="type">...</result>` (вложенные/несбалансированные теги — брать до следующего `<result>` или `</result>`, как `extractResultBlocks`). Fallback на остатке текста: `matchLegacyResultTag` для `<result_TYPE>...</result_TYPE>` где `TYPE` = тип агента.
  - **Слой 1 — invalid-JSON retry** (порт `shouldRetryInvalidJsonAgent`): если JSON-агент вернул невалидный JSON внутри батча → пометить как failed.
  - **Слой 2 — individual fallback:** все failed → переиграть по одному через concurrency-limited gather (порт `settleAgentJobsWithConcurrencyLimit`, лимит `AGENT_BATCH_FALLBACK_MAX_CONCURRENT=4`).
- [ ] **5.2** Изоляция "тяжёлых" трекеров от батча (порт `shouldRunAgentIndividually`): `expression`/`illustrator`/`lorebook-keeper` (+ music-JSON, у нас не актуально) идут отдельно — большие приватные extras не должны попадать в чужие батч-запросы. Если в группе только изолированные → все individual; если смесь → изолированные параллельно с батчем остальных.
- [ ] **5.3** Per-tracker `connectionId` + `model` override (уже есть в `StudioAgent.modelOverride`/`endpoint` — убедиться что wired в `agent_runner`).
- [ ] **5.4** `runInterval` для части трекеров (например director — раз в 3 хода). Добавить поле `runInterval` в `StudioAgent` (default 1 = каждый ход). В `runTrackerCycle` пропускать трекеры где `turnCount % runInterval != 0`. Marinara держит дефолты per-type в `BUILT_IN_AGENT_RUN_INTERVAL_DEFAULTS` (из манифеста) + override в `settings.runInterval` — повторить ту же двухуровневую схему (дефолт трекера + пер-чат override).
- [ ] **5.5** Тест: 4 трекера с одним provider+model → 1 батч-вызов вместо 4. Токен-экономия на static-context: 1× вместо 4×.
- [ ] **5.6** `flutter analyze` + `flutter test`.

#### 5.7 Concurrency & batch grouping (порт деталей Marinara, без которых батч ломается)

Эти механизмы есть в `agent-pipeline.ts`/`agent-executor.ts` и должны быть портированы вместе с батчингом — иначе либо лишние одновременные SSE-стримы, либо неправильная группировка.

- [ ] **5.7.1 Группировка батча — не только provider+model.** Ключ группы = `(provider, model, postProcessingDataKey)`. Для `post_processing`-трекеров `postProcessingDataKey` учитывает `includePreGenInjections`/`includeParallelResults` — трекеры с разными требованиями к контексту НЕ попадают в один батч (иначе кто-то получит лишний/недостающий контекст). Для pre_generation/parallel ключ = `"default"`.
- [ ] **5.7.2 Конкурренси-лимиты (адаптировать под Dio/SSE на десктопе).** Marinara держит:
  - `AGENT_PHASE_MAX_CONCURRENT_GROUPS = 8` — макс. одновременных групп в фазе.
  - `AGENT_BATCH_FALLBACK_MAX_CONCURRENT = 4` — макс. одновременных individual-ретраев.
  - `AGENT_GROUP_MAX_CONCURRENT_TOOL_CALLS = 4` — если прикрутим tool-calling (Phase 5 open question).
  - Портировать как `settleAgentJobsWithConcurrencyLimit`-аналог (Dart: `Pool`/семафор или ручной chunked `Future.wait`). **На десктопе 8 одновременных SSE-стримов — реальный риск** rate-limit/таймаутов; начать с консервативных лимитов (4/2).
- [ ] **5.7.3 `maxParallelJobs` / `splitGroupForParallelJobs`** — внутри одной группы агенты могут дробиться на N параллельных джобов (`normalizeAgentMaxParallelJobs` клампит в `[1,16]`). Для MVP можно `maxParallelJobs=1` (одна группа = один запрос), но оставить поле, чтобы не ломать модель позже.
- [ ] **5.7.4 Safe `onResult` wrapper** — колбэк результата трекера оборачивать в try/catch: ошибка в колбэке (например запись в закрытый стрим при abort) НЕ должна ронять всю группу и молча терять результаты остальных. Порт `safeOnResult` из `executeGroup`.
- [ ] **5.7.5 Per-agent failure isolation** — `executeAgent` ловит rethrow внутри себя и возвращает failed `AgentResult` для ЭТОГО агента, а не reject промиса (иначе `Future.wait` группы упадёт целиком и заберёт со-групповые результаты). При порте на Dart: каждый трекер-вызов в свой try/catch → failed-result, не throw наружу.

- [ ] **5.8** `flutter analyze` + `flutter test`.

**Файлы:** `agent_runner.dart` (major edit), `studio_config.dart` (`runInterval` + `maxParallelJobs` fields), `tables.dart` (migration), `memory_studio_service.dart` (wire batching + concurrency pool).
**Оценка:** 2-3 дня.
**Риск:** средний — батч-парсинг может ломаться на плохих моделях. Многослойный fallback (invalid-JSON retry → individual retry → error-result) уже в дизайне. Конкурренси-лимиты консервативные на старте.

### Phase 6 — Prompt-cache reorder (low effort, medium impact)

**Цель:** кросс-трекерный кэш на Anthropic/OpenRouter.

- [ ] **5.1** В `_buildTrackerMessages` / `buildBatchSystemPrompt`: shared static content (char card, persona, lorebooks, memory) **первым**, agent-specific `promptShard` **последним**.
- [ ] **5.2** Включить `cacheControlTtl` на shared-блоке (уже проходит через `_ResolvedAgentConfig`, проверить что wired).
- [ ] **5.3** Тест: второй ход с тем же character → cache-hit на static prefix.
- [ ] **5.4** `flutter analyze` + `flutter test`.

**Файлы:** `agent_runner.dart` (edit), `memory_studio_service.dart` (edit).
**Оценка:** 0.5-1 день.
**Риск:** низкий.

### Phase 7 — Lightweight Studio UI + разделение agent outputs от memory records (parallel to 2-6)

**Цель:** вернуть урезанную UI-конфигурацию, упростить поверхность, разделить смешанные в UI agent-записи и memory-записи.

> **Контекст проблемы:** пользователь сообщает "в UI мелкие записи от агентов появлялись вперемешку с большими memory записями". Сейчас:
> - `ChatMessage.studioOutputs` (`memory_studio_service.dart:608 _studioOutputsToJson`) — брифы агентов, сохраняются в каждое сообщение, отображаются в `chat_screen.dart:1224`.
> - `AgentOperationRecord` (`agent_operations_log_provider.dart`) — лог sidecar-операций (memory sidecar, agenticSearch, agenticWrite, postCleaner, classifier, consolidation), отдельный ring buffer, отображается в `agentic_operations_log_dialog.dart`.
> - Memory entries из MemoryBook — отдельная сущность, но в восприятии пользователя смешивается с agent outputs, потому что оба "что-то от агентов" в окрестности чата.
>
> **После рефактора** (Phase 2): `studioOutputs` репурпозится в `trackerProvenance` — компактная JSON-запись `{trackerId, value, contributedAt}` для дебага. Это **не текстовые брифы**, а структурированные значения трекеров. Они:
> - Не должны смешиваться с MemoryBook-записями в UI — это разные сущности (трекер-state vs long-term facts).
> - Должны отображаться в отдельной "Agent Activity" панели (как `agentic_operations_log_dialog.dart`), не в основном чате.
> - MemoryBook-записи — в MemoryBook UI (`memory_books_sheet.dart`), не в agent-панели.

**Agent-generated memory batches:** мелкие memory-записи, которые создаются агентами/write-loop после хода, не должны попадать вперемешку с большими scan-generated drafts. Они должны жить в отдельной вкладке MemoryBook UI и автоаппрувиться, потому что это уже post-turn agent output, а не ручной bulk scan.

- [ ] **6.1** Оставить `studio_menu_dialog.dart`, но переписать его в **lightweight tracker dialog** вместо полного 8-контроллерного редактора. Он должен показывать: Studio/tracker enable switch, список активных трекеров, краткие статусы (`contextSize`, `runInterval`, model override), ссылку "Advanced / POST-building config →". Полные LLM/pipeline настройки остаются в `post_building_menu_dialog.dart`.
- [ ] **6.2** Не re-inline full advanced settings в Studio dialog. Вместо этого показать compact agentic/write-loop summary (`enabled`, selected sidecar/model label, timeout if non-default) + "Configure →" в `post_building_menu_dialog.dart`. Старые `_buildStandaloneAgenticCard` / `_buildAgenticAdvancedSection` из `9579d7e` использовать только как reference для того, какие поля суммаризировать.
- [ ] **6.3** В `memory_generation_settings_sheet.dart`: рядом с `memoryMode` SegmentedButton показать короткую ссылку "LLM config →" ведущую в post-building (вместо убранных полей). Сохранить retrieval-only характер листа.
- [ ] **6.4** Очистить `post_building_menu_dialog.dart` от дублей. `studio_menu_dialog.dart` не должен заново дублировать POST-cleaner temp/maxTokens/timeout и sidecar model selectors — только summary + link.
- [ ] **6.5** **Разделить UI agent-записей и memory-записей:**
  - `studioOutputs` (→ `trackerProvenance` после Phase 2) — отображать **только** в `agentic_operations_log_dialog.dart` (Agent Activity panel), не в основном чате (`chat_screen.dart:1224` убрать inline-отображение брифов).
  - MemoryBook entries — отображать в `memory_books_sheet.dart`, не в Agent Activity.
  - В `memory_books_sheet.dart` разделить крупные scan/manual memory drafts и мелкие agent-generated memory batches. Рекомендуемая структура вкладок: `Approved`, `Scan drafts`, `Agent memories`. `Agent memories` показывает записи, созданные write-loop / memory tracker, отдельно от bulk scan drafts.
  - Agent-generated memory batches **auto-approve by default**: write-loop/memory tracker пишет их сразу в approved `entries` (или переводит draft в approved в той же транзакции), с source/kind маркером (`source: agentic_write` / `kind: agent_memory`) для фильтрации во вкладке. Они не должны требовать ручного approve-прохода как большие scan drafts.
  - Если агентная запись невалидна/слишком длинная/дублирует existing entry — не автоаппрувить, а отправить в `Agent memories` как flagged item с error/status, без смешивания со `Scan drafts`.
  - В `agentic_operations_log_dialog.dart` добавить отдельную вкладку/секцию "Tracker values" для `trackerProvenance` — чтобы пользователь видел, какие трекеры обновились на этом ходе и их значения. Это разделит "что сделали агенты" (tracker provenance) от "что запомнилось надолго" (MemoryBook).
- [ ] **6.6** Data-path для agent-generated memory batches: проверить `memory_agentic_write_service.dart` / `memory_book_repo.dart append` path. Нужен атомарный метод repo для auto-approved agent entries, чтобы не делать read-modify-write MemoryBook вне dedicated repo methods. Сохранить source/kind/status достаточно явно для UI-фильтра.
- [ ] **6.7** `flutter analyze` + мануальный UI-смоук.

**Файлы:** `studio_menu_dialog.dart` (rewrite to lightweight dialog), `memory_generation_settings_sheet.dart` (edit), `post_building_menu_dialog.dart` (edit), `chat_screen.dart` (edit — убрать inline studioOutputs), `agentic_operations_log_dialog.dart` (edit — добавить tracker provenance секцию), `memory_books_sheet.dart` (edit — вкладки Approved/Scan drafts/Agent memories), `memory_agentic_write_service.dart` / `memory_book_repo.dart` (auto-approved agent memory write path).
**Оценка:** 1-2 дня.
**Риск:** низкий — чисто UI.

### Phase 8 — Документация + инварианты

- [ ] **8.1** Обновить `docs/ARCHITECTURE.md` § "Studio Mode Pipeline" — описать tracker-around-generator модель, фазы, батчинг.
- [ ] **8.2** Добавить инварианты в `docs/INVARIANTS.md`:
  - `INV-ST1`: Трекеры получают `≤ contextSize` (default 5) последних сообщений, не фулл-историю.
  - `INV-ST2`: `maxFinalHistoryMessages` (default 15) применяется к генератору.
  - `INV-ST3`: Трекеры с одинаковым `(provider, model, postProcessingDataKey)` батчатся в один LLM-запрос.
  - `INV-ST4`: `AgentSwipe` / nested-swipe ре-ран удалён — нет второго измерения swipe-ов.
  - `INV-ST5`: Сбой одного трекера (исключение/невалидный JSON) НЕ роняет остальных — возвращается failed-result, генератор продолжает. Многослойный fallback: invalid-JSON retry → individual retry → error-result.
  - `INV-ST6`: Batch `maxTokens` = сумма per-tracker budgets (capped провайдером/моделью); одновременных LLM-вызовов трекеров ≤ конкурренси-лимита (старт 4).
- [ ] **8.3** Обновить `docs/rules/generation.md` § Studio Mode.
- [ ] **8.4** Обновить `docs/rules/database.md` § `StudioConfigRows` + `TrackerRows`.
- [ ] **8.5** Обновить MemoryBook docs/rules: `docs/rules/database.md` и релевантные architecture sections должны описывать, что agent-generated memory batches auto-approved, маркируются source/kind, и отображаются отдельно от scan drafts.
- [ ] **8.6** Обновить/закрыть связанные планы: `docs/PLAN_PIPELINE_SEPARATION.md`, `docs/PLAN_CONTINUITY_POST_CLEANER.md` и другие `PLAN_*.md`, если они всё ещё описывают `memoryMode=agentic`, старый Studio pipeline, `AgentSwipe` или смешивание agent outputs с MemoryBook drafts.
- [ ] **8.7** Этот файл (`PLAN_AGENTIC_STUDIO.md`) — отметить выполненные фазы.

**Final docs gate:** последний PR не считается готовым, пока обновлены все затронутые `.md` файлы (`ARCHITECTURE.md`, `INVARIANTS.md`, `docs/rules/*.md`, связанные `PLAN_*.md`) и в них нет устаревших утверждений про `memoryMode=agentic`, 8-controller Studio pipeline, hold-mode POST-processing или inline Studio outputs.

**Оценка:** 0.5 дня.

---

## 8. UI Surface Map — что выкидывается, что остаётся

> Источник: детальное исследование всех UI-файлов (см. `task` от этой сессии). Линии approximate — сверять с кодом при рефакторе.

### 8.1 DELETE — целиком или секциями (~2400-2600 строк)

| Файл | Что | Строк | Причина |
|---|---|---|---|
| `lib/features/chat/widgets/studio_menu_dialog.dart` | **Большинство содержимого** | ~2000+ | Удалить 8-контроллерный конфиг: preset editor, bulk agent settings, per-agent promptShard/refresh-policy/model/temp/maxTokens, final history limit, routing mode, builder prompt. Сам файл остаётся как lightweight tracker dialog: enable, active trackers summary, quick toggles, links to advanced config. |
| `lib/features/chat/chat_screen.dart` `_StudioRuntimeCard` | 403-462 | ~60 | Card со спинером + "Studio N/M: agentName" + "Finish agent" button — оверлей над чатом во время pipeline. |
| `lib/features/chat/chat_screen.dart` studioRuntime watch | 876 | 1 | `ref.watch(studioRuntimeStateProvider)` — состояние pipeline. |
| `lib/features/chat/chat_screen.dart` `onAgentSwipe` callback | 1112-1121 | ~10 | Навигация синих sub-swipe-ов (AgentSwipe). |
| `lib/features/chat/chat_screen.dart` `'studio-final'` regen mode | 1131-1140 | ~10 | `regenerateLastAssistant(studioFinalOnly: mode == 'studio-final')` — regen одного intermediate. |
| `lib/features/chat/chat_screen.dart` `onStudioOutputEdit` | 1219-1239 | ~20 | Inline-правка брифа агента в чате через `ExtBlockDialogs.promptEdit`. |
| `lib/features/chat/chat_screen.dart` `onStudioOutputRegen` | 1240-1248 | ~9 | Regen одного studioOutput (intermediate agent). |
| `lib/features/chat/chat_screen.dart` Studio runtime card overlay | 1355-1366 | ~12 | `Positioned(... _StudioRuntimeCard ...)` — оверлей карточки. |
| `lib/features/chat/chat_screen.dart` `onFinishAgent` в input bar | 1652-1660 | ~9 | "Finish agent" button в input bar. |
| `lib/features/chat/widgets/magic_drawer.dart` old Studio copy | 131-135, 521-524, 536-547 | ~25 | Старую карточку/копирайт 8-controller Studio заменить на lightweight tracker entry. Tap-handler `_showStudioMenu()` остаётся, но открывает новый lightweight dialog. |
| `lib/features/chat/controllers/chat_swipe_controller.dart` AgentSwipe | 34-41, 67-96 | ~35 | `setAgentSwipe` + `changeAgentSwipe` — синие sub-swipe-ы целиком. Зелёные swipe-ы (`setSwipe`, `changeSwipe`, `setGreeting`) остаються. |
| `lib/features/chat/controllers/chat_message_ops_controller.dart` studioOutput ops | 60-76, 78-146 | ~90 | `editStudioOutput` + `regenerateStudioOutput` — правка/regen одного intermediate. `editMessage`, `moveMessage`, `deleteMessage`, `toggleMessageHidden`, `clearChat` остаються. |
| `lib/features/chat/bridge/chat_webview_callbacks.dart` | 54-55, 86-91 | ~6 | JS→Flutter bridge: `onAgentSwipe`, `onStudioOutputEdit`, `onStudioOutputRegen`. |
| `lib/features/chat/bridge/chat_webview_surface.dart` | 209, 218-219 | ~3 | Bridge wiring для AgentSwipe + studioOutput. |
| `lib/features/chat/bridge/chat_webview_widget.dart` | 456, 464-465 | ~3 | Bridge wiring (дубль). |
| `lib/features/chat/bridge/chat_webview_build_listeners.dart` | 132-187 | ~55 | `studioOutputs` + `studioOutputsExpanded` передаються в webview payload. |
| `lib/features/chat/services/chat_message_sync.dart` | 144-165, 214-216 | ~25 | Sync-логика для `agentSwipeId`/`agentSwipes`/`studioOutputs` + `_studioOutputsDiffer`. |
| `lib/features/chat/screens/prompt_preview_screen.dart` Studio request preview | 9, 44, 76-89, 200-201, 342, 386-388, 513-514 | ~40 | `StudioRequestPreview` — preview LLM-запроса intermediate-агента. Обычный preview остаётся. |

**Итого на удаление: ~2400-2600 строк.** `studio_menu_dialog.dart` больше не удаляется целиком, но большая часть старого 8-контроллерного UI вырезается.

### 8.2 KEEP — целиком (~4743 строки)

| Файл | Что | Строк | Причина |
|---|---|---|---|
| `lib/features/chat/widgets/post_building_menu_dialog.dart` | **Целиком** | 1548 | POST-cleaner (enable/continuity/audit/temp/maxTokens/timeout/history), WriteLoop + sidecar, generation LLM, classifier, consolidation — весь advanced pipeline-конфиг. Lightweight Studio dialog только ссылается сюда. |
| `lib/features/chat/widgets/agentic_operations_log_dialog.dart` | **Целиком** | 383 | Лог sidecar/postCleaner/agenticSearch/agenticWrite/classifier/consolidation операций. Сюда переедет отображение tracker provenance. |
| `lib/features/chat/widgets/memory_generation_settings_sheet.dart` | **Целиком** | 1096 | memoryMode selector (5 режимов), selector settings, budget, vector search — все MemoryBook settings. |
| `lib/features/chat/widgets/memory_books_sheet.dart` | **Целиком** | 791 | Список MemoryBook записей (drafts + approved) + actions (scan/generate/reindex/delete). |
| `lib/features/chat/widgets/memory_activity_card.dart` | **Целиком** | 566 | Live-диагностика memory (sidecar/classifier/candidates) во время генерации. |
| `lib/features/chat/widgets/memory_graph_panel.dart` | **Целиком** | 250 | Memory graph (entities/arcs/errors). |
| `lib/features/chat/widgets/memory_entry_editor_sheet.dart` | **Целиком** | 109 | Memory entry/draft editor. |
| `lib/features/chat/widgets/magic_drawer.dart` | memory-books/post-building/agent-ops/studio items + openers | ~осталось | Drawer-карточки для memory, post-building, agent-ops и lightweight Studio. |
| `lib/features/chat/chat_screen.dart` | PostCleanerStatusCard, sidecar prewarm, green swipe, normal regen | ~осталось | Пост-cleaner статус-карта (1367-1377), зелёные swipe-ы, обычный regen. |
| `lib/features/chat/controllers/chat_swipe_controller.dart` | setSwipe, changeSwipe, setGreeting | ~90 | Зелёные swipe-ы. |
| `lib/features/chat/controllers/chat_message_ops_controller.dart` | editMessage, move/delete/hide/clear | ~160 | Обычные операции с сообщениями. |

**Итого остаётся: ~4743 строки.**

### 8.3 REPURPOSE (~200 строк)

| Файл | Что | Причина |
|---|---|---|
| `lib/features/chat/widgets/post_cleaner_diff_dialog.dart` (50-136) | Заменить `AgentSwipe` type на простой `({String content, ...})` record / `CleanerDiffPayload` | Diff-диалог пост-cleaner **выживает** (пост-cleaner = KEEP), но зависит от `AgentSwipe` для хранения original/cleaned. После удаления `AgentSwipe` — заменить тип, диалог остаётся. |
| `lib/features/chat/widgets/post_cleaner_status_card.dart` (9) | Обновить комментарий "Mirrors the visual style of `_StudioRuntimeCard`" | Косметика — `_StudioRuntimeCard` удаляется. |
| `lib/features/chat/screens/prompt_preview_screen.dart` | Удалить `StudioRequestPreview` mode, оставить обычный preview | После удаления pipeline preview-режима остаётся обычный. |
| `lib/features/chat/widgets/studio_menu_dialog.dart` | Старый 8-controller editor → lightweight tracker dialog | Файл остаётся, но перестаёт быть полноэкранным редактором pipeline. Показывает enabled state, active trackers, compact settings и ссылки на advanced config. |

### 8.4 RELOCATE (~30 строк)

| Откуда | Куда | Что |
|---|---|---|
| `chat_screen.dart` 1219-1248 `onStudioOutputEdit`/`onStudioOutputRegen` (inline в чате) | `agentic_operations_log_dialog.dart` (Agent Activity panel) | После рефактора: `studioOutputs` → `trackerProvenance` (compact JSON `{trackerId, value, contributedAt}`). Отображать **не inline в чате**, а в Agent Activity панели — отдельно от MemoryBook записей. Это решает "записи вперемешку". |

### 8.5 Ключевые архитектурные замечания

1. **`memory_agent_providers.dart` нужно разделить.** Сейчас экспортирует `studioRuntimeStateProvider` (DELETE) + `lastMemoryActivityProvider` (KEEP) + `memorySidecarPrewarmCacheProvider` (KEEP). Разделить на удалённый studio-provider и оставшийся memory-provider.

2. **`AgentSwipe` модель** (`chat_message.dart`): удаляется из `ChatMessage` (поля `agentSwipes`/`agentSwipeId`). Но `post_cleaner_diff_dialog.dart` использует `AgentSwipe` для diff-payload — заменить на простой record. Сама модель `AgentSwipe` может быть удалена после замены.

3. **`studioOutputs` поле на `ChatMessage`**: DELETE из модели, из WebView build listeners, из sync-логики. После Phase 2 — репурпосить в `trackerProvenanceJson` (или оставить имя, переименовать в коде через alias).

4. **WebView JS bridge** (`glaze.onAgentSwipe`, `glaze.onStudioOutputEdit`, `glaze.onStudioOutputRegen`): удалить из bridge-определений в `chat_webview_surface.dart` + `chat_webview_widget.dart`. **JS-side handlers в `assets/chat_webview/` тоже удалить** — юзер должен hot restart (press `R`) после изменений assets.

5. **`studio_menu_dialog.dart` — крупнейший rewrite.** Весь 8-контроллерный конфиг удаляется, но файл остаётся как lightweight tracker dialog. Advanced конфиг остаётся в `post_building_menu_dialog.dart` (который уже 1548 строк и выживает); Studio dialog показывает только summary/quick toggles/links.

### 8.6 Net effect

| Метрика | Значение |
|---|---|
| Удаляем строк UI | ~2400-2600 |
| Остаётся строк UI | ~4743 |
| Репурпосим строк UI | ~200 |
| Релокируем строк UI | ~30 |
| Файлов целиком удаляется | 0 из крупных UI-файлов; `studio_menu_dialog.dart` переписывается в lightweight dialog |
| Файлов целиком выживает | 7 (memory_*, agentic_operations_log, post_building) |
| Файлов с секционной правкой | ~10 (chat_screen, magic_drawer, controllers, webview bridge, prompt_preview) |

---

## 3. Ожидаемая экономия

| Сценарий | Сейчас | После |
|---|---|---|
| 100 сообщ., 8 контроллеров, большая карта | ~290k input/turn | ~15-25k (1 gen + 2-3 батч-трекера × small-context) |
| 50 сообщ., 4 трекера, средняя карта | ~80k | ~10-15k |
| 200 сообщ. (rolling summary on) | ~580k | ~20-30k |

**Мультипликатор экономии: ×10-15 на большом контексте.**

UI-эффект: ~2400-2600 строк удаляется, ~4743 остаётся, ~200 репурпосится. См. §8.

---

## 4. Риски и митигации

| Риск | Митигация |
|---|---|
| Батч-парсинг ломается на слабых моделях | Fallback на individual-вызовы (порт `agent-executor.ts` `failed → retry individually`). |
| Удаление `AgentSwipe` ломает существующие чаты с сохранёнными swipe-ами | DB-миграция: при чтении старого сообщения с `agent_swipes_json` — ignore поле, не крашить. Схему можно оставить (не удалять колонку), просто перестать писать. |
| `contextSize=5` слишком мало для continuity-трекера | Трекер-specific override: continuity может иметь `contextSize=20` в дефолтном preset. Поле per-tracker, не global. |
| Prompt-cache reorder ломает кэш для существующих юзеров | Кэш инвалидируется на первый ход после апдейта — это разовая стоимость, не перманентная. |
| `runInterval` > 1 ломает continuity (трекер не видел промежуточных ходов) | `runInterval` трекеров, где важен каждый ход (continuity, guard), остаётся = 1. Применять только к director/illustrator. |

---

## 5. Порядок выполнения и PR-стратегия

Каждая фаза — отдельный PR в `hydall/GlazeFlutter:master`:

| PR | Фазы | Зависимости |
|---|---|---|
| PR 1 | Phase 1 (cleanup) | — |
| PR 2 | Phase 2 (orchestration removal) | PR 1 |
| PR 3 | Phase 3 (context trim) | PR 2 |
| PR 4 | Phase 4 (remove agentic MemoryBook mode) | PR 3 |
| PR 5 | Phase 5 (batching) | PR 4 |
| PR 6 | Phase 6 (cache reorder) | PR 5 |
| PR 7 | Phase 7 (UI) | PR 2 (parallel to 3-6) |
| PR 8 | Phase 8 (docs) | PR 2-7 |

Бранчевание: `feat/studio-marinara-cleanup` → `feat/studio-tracker-model` → `feat/studio-context-trim` → `feat/memory-agentic-mode-removal` → `feat/studio-batching` → `feat/studio-cache-reorder`. UI-бранч `feat/studio-ui-restor` офф `feat/studio-tracker-model`.

---

## 6. Trello

Создать карты в листе **features** → двигать в **In Progress** по старту каждой фазы:

- "Studio: Marinara-style refactor — dead code cleanup (Phase 1)"
- "Studio: Remove 8-controller orchestration (Phase 2)"
- "Studio: Tracker context trim (Phase 3)"
- "MemoryBook: Remove agentic retrieval mode (Phase 4)"
- "Studio: Tracker batching (Phase 5)"
- "Studio: Prompt-cache reorder (Phase 6)"
- "Studio: UI restoration (Phase 7)"
- "Studio: Docs + invariants (Phase 8)"

---

## 7. Открытые вопросы

- [ ] **Tool-calling vs prompt-JSON для трекеров:** Marinara использует OpenAI tool-calling для трекеров с tools (Spotify) — реальная функция `executeAgentWithTools` (executor.ts): цикл call→tool_calls→feed back→repeat до `getMaxToolRounds()`, затем финальный вызов без tools для JSON. Tool-агенты **исключаются из батча** (`shouldUseToolsDuringAgentExecution`) и идут с лимитом `AGENT_GROUP_MAX_CONCURRENT_TOOL_CALLS=4`. У нас tool-schemas уже определены (`memory_agentic_tools.dart`), но не wired. Решить в Phase 5: прикрутить ли `executeAgentWithTools`-порт или остаться на prompt-embedded JSON (текущий подход agentic write-loop). Рекомендация: для MVP — prompt-JSON (проще, дешевле), tool-calling отложить, т.к. наши трекеры (continuity/world-state/expression) детерминированы и tools им не нужны — tools нужны были Marinara только для Spotify/внешних API.
- [ ] **Consolidation:** wiring consolidation (ранее описано в удалённом `PLAN_PIPELINE_SEPARATION.md:252-277` как "scaffolded but not wired"). Решить, входит ли wiring consolidation в этот план или отдельным.

---

## Final Documentation Gate

Последний PR по этому плану нельзя считать готовым, пока обновлены все затронутые Markdown-документы:

- `docs/ARCHITECTURE.md`
- `docs/INVARIANTS.md`
- `docs/rules/generation.md`
- `docs/rules/database.md`
- связанные `docs/PLAN_*.md`

В документах не должно остаться устаревших утверждений про `memoryMode=agentic`, 8-controller Studio pipeline, `AgentSwipe`, hold-mode POST-processing как целевой UX, inline Studio outputs или смешивание scan drafts с agent-generated memory batches.
