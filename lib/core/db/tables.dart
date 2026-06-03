import 'package:drift/drift.dart';

@DataClassName('CharacterRow')
class Characters extends Table {
  @override
  String get tableName => 'characters';

  TextColumn get charId => text()();
  TextColumn get name => text()();
  TextColumn get avatarPath => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get personality => text().nullable()();
  TextColumn get scenario => text().nullable()();
  TextColumn get firstMes => text().nullable()();
  TextColumn get mesExample => text().nullable()();
  TextColumn get systemPrompt => text().nullable()();
  TextColumn get postHistoryInstructions => text().nullable()();
  TextColumn get creator => text().nullable()();
  TextColumn get creatorNotes => text().nullable()();
  TextColumn get color => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer().withDefault(const Constant(0))();
  TextColumn get tagsJson => text().nullable()();
  TextColumn get alternateGreetingsJson => text().nullable()();
  TextColumn get galleryJson => text().nullable()();
  IntColumn get currentSessionIndex => integer().withDefault(const Constant(0))();
  BoolColumn get fav => boolean().withDefault(const Constant(false))();
  TextColumn get extensionsJson => text().nullable()();
  TextColumn get characterVersion => text().withDefault(const Constant('1'))();
  TextColumn get macroName => text().nullable()();
  TextColumn get picksHash => text().nullable()();

  @override
  Set<Column> get primaryKey => {charId};
}

@DataClassName('ChatSessionRow')
@TableIndex(name: 'idx_chat_sessions_character_id', columns: {#characterId})
@TableIndex(name: 'idx_chat_sessions_updated_at', columns: {#updatedAt})
class ChatSessions extends Table {
  @override
  String get tableName => 'chat_sessions';

  TextColumn get sessionId => text()();
  TextColumn get characterId => text()();
  IntColumn get sessionIndex => integer()();
  TextColumn get messagesJson => text()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  TextColumn get sessionVarsJson => text().nullable()();
  TextColumn get authorsNoteJson => text().nullable()();
  TextColumn get draft => text().nullable()();
  TextColumn get lastScrollAnchorJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {sessionId};
}

@DataClassName('MemoryBookRow')
class MemoryBookRows extends Table {
  @override
  String get tableName => 'memory_book_rows';

  TextColumn get sessionId => text()();
  TextColumn get entriesJson => text().withDefault(const Constant('[]'))();
  TextColumn get pendingDraftsJson => text().withDefault(const Constant('[]'))();
  TextColumn get settingsJson => text().withDefault(const Constant('{}'))();
  IntColumn get lastProcessedMessageCount => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sessionId};
}
@DataClassName('PresetRow')
class Presets extends Table {
  @override
  String get tableName => 'presets';

  TextColumn get presetId => text()();
  TextColumn get name => text()();
  TextColumn get dataJson => text()();

  @override
  Set<Column> get primaryKey => {presetId};
}

@DataClassName('ApiConfigRow')
class ApiConfigs extends Table {
  @override
  String get tableName => 'api_configs';

  TextColumn get configId => text()();
  TextColumn get name => text()();
  TextColumn get providerId => text().withDefault(const Constant('openai_compatible'))();
  TextColumn get endpoint => text().nullable()();
  TextColumn get apiKey => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get mode => text().withDefault(const Constant('chat'))();
  IntColumn get maxTokens => integer().withDefault(const Constant(8000))();
  IntColumn get contextSize => integer().withDefault(const Constant(32000))();
  RealColumn get temperature => real().withDefault(const Constant(0.7))();
  RealColumn get topP => real().withDefault(const Constant(0.9))();
  BoolColumn get stream => boolean().withDefault(const Constant(true))();
  TextColumn get reasoningEffort => text().nullable()();
  BoolColumn get requestReasoning => boolean().withDefault(const Constant(false))();
  TextColumn get reasoningTagStart => text().nullable()();
  TextColumn get reasoningTagEnd => text().nullable()();
  BoolColumn get omitTemperature => boolean().withDefault(const Constant(false))();
  BoolColumn get omitTopP => boolean().withDefault(const Constant(false))();
  BoolColumn get omitReasoning => boolean().withDefault(const Constant(false))();
  BoolColumn get omitReasoningEffort => boolean().withDefault(const Constant(false))();
  BoolColumn get embeddingUseSame => boolean().withDefault(const Constant(true))();
  BoolColumn get embeddingEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get embeddingEndpoint => text().nullable()();
  TextColumn get embeddingApiKey => text().nullable()();
  TextColumn get embeddingModel => text().nullable()();
  IntColumn get embeddingMaxChunkTokens => integer().withDefault(const Constant(512))();
  TextColumn get cacheControlTtl => text().withDefault(const Constant('off'))();

  @override
  Set<Column> get primaryKey => {configId};
}

@DataClassName('PersonaRow')
class Personas extends Table {
  @override
  String get tableName => 'personas';

  TextColumn get personaId => text()();
  TextColumn get name => text()();
  TextColumn get prompt => text().nullable()();
  TextColumn get avatarPath => text().nullable()();
  IntColumn get createdAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {personaId};
}

@DataClassName('LorebookRow')
@TableIndex(name: 'idx_lorebooks_activation_scope', columns: {#activationScope})
@TableIndex(name: 'idx_lorebooks_activation_target_id', columns: {#activationTargetId})
class Lorebooks extends Table {
  @override
  String get tableName => 'lorebooks';

  TextColumn get lorebookId => text()();
  TextColumn get name => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get activationScope => text().withDefault(const Constant('global'))();
  TextColumn get activationTargetId => text().nullable()();
  TextColumn get entriesJson => text()();
  TextColumn get settingsJson => text().withDefault(const Constant(''))();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {lorebookId};
}

@DataClassName('EmbeddingRow')
@TableIndex(name: 'idx_embeddings_source_type', columns: {#sourceType})
@TableIndex(name: 'idx_embeddings_source_id', columns: {#sourceId})
class Embeddings extends Table {
  @override
  String get tableName => 'embeddings';

  TextColumn get entryId => text()();
  TextColumn get sourceType => text().withDefault(const Constant('lorebook_entry'))();
  TextColumn get sourceId => text().nullable()();
  BlobColumn get vectorsBlob => blob().nullable()();
  TextColumn get textHash => text().nullable()();
  TextColumn get retrievalHintsJson => text().nullable()();
  TextColumn get errorJson => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {entryId};
}

@DataClassName('ChatSummary')
class ChatSummaries extends Table {
  @override
  String get tableName => 'chat_summaries';

  TextColumn get sessionId => text()();
  TextColumn get content => text()();
  IntColumn get messageCount => integer().withDefault(const Constant(0))();
  TextColumn get prompt => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sessionId};
}

@DataClassName('ExtensionPresetRow')
class ExtensionPresets extends Table {
  @override
  String get tableName => 'extension_presets';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get configJson => text()();
  IntColumn get createdAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('InfoBlockRow')
@TableIndex(name: 'idx_info_blocks_session_id', columns: {#sessionId})
@TableIndex(name: 'idx_info_blocks_message_id', columns: {#messageId})
class InfoBlocks extends Table {
  @override
  String get tableName => 'info_blocks';

  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get messageId => text()();
  TextColumn get blockId => text()();
  TextColumn get blockName => text()();
  TextColumn get blockType => text()();
  TextColumn get content => text()();
  IntColumn get createdAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
