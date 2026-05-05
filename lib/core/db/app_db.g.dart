// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $CharactersTable extends Characters
    with TableInfo<$CharactersTable, CharacterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharactersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _charIdMeta = const VerificationMeta('charId');
  @override
  late final GeneratedColumn<String> charId = GeneratedColumn<String>(
    'char_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarPathMeta = const VerificationMeta(
    'avatarPath',
  );
  @override
  late final GeneratedColumn<String> avatarPath = GeneratedColumn<String>(
    'avatar_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _personalityMeta = const VerificationMeta(
    'personality',
  );
  @override
  late final GeneratedColumn<String> personality = GeneratedColumn<String>(
    'personality',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scenarioMeta = const VerificationMeta(
    'scenario',
  );
  @override
  late final GeneratedColumn<String> scenario = GeneratedColumn<String>(
    'scenario',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstMesMeta = const VerificationMeta(
    'firstMes',
  );
  @override
  late final GeneratedColumn<String> firstMes = GeneratedColumn<String>(
    'first_mes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mesExampleMeta = const VerificationMeta(
    'mesExample',
  );
  @override
  late final GeneratedColumn<String> mesExample = GeneratedColumn<String>(
    'mes_example',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _systemPromptMeta = const VerificationMeta(
    'systemPrompt',
  );
  @override
  late final GeneratedColumn<String> systemPrompt = GeneratedColumn<String>(
    'system_prompt',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _postHistoryInstructionsMeta =
      const VerificationMeta('postHistoryInstructions');
  @override
  late final GeneratedColumn<String> postHistoryInstructions =
      GeneratedColumn<String>(
        'post_history_instructions',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _creatorMeta = const VerificationMeta(
    'creator',
  );
  @override
  late final GeneratedColumn<String> creator = GeneratedColumn<String>(
    'creator',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _creatorNotesMeta = const VerificationMeta(
    'creatorNotes',
  );
  @override
  late final GeneratedColumn<String> creatorNotes = GeneratedColumn<String>(
    'creator_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _alternateGreetingsJsonMeta =
      const VerificationMeta('alternateGreetingsJson');
  @override
  late final GeneratedColumn<String> alternateGreetingsJson =
      GeneratedColumn<String>(
        'alternate_greetings_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    charId,
    name,
    avatarPath,
    description,
    personality,
    scenario,
    firstMes,
    mesExample,
    systemPrompt,
    postHistoryInstructions,
    creator,
    creatorNotes,
    color,
    updatedAt,
    tagsJson,
    alternateGreetingsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'characters';
  @override
  VerificationContext validateIntegrity(
    Insertable<CharacterRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('char_id')) {
      context.handle(
        _charIdMeta,
        charId.isAcceptableOrUnknown(data['char_id']!, _charIdMeta),
      );
    } else if (isInserting) {
      context.missing(_charIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar_path')) {
      context.handle(
        _avatarPathMeta,
        avatarPath.isAcceptableOrUnknown(data['avatar_path']!, _avatarPathMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('personality')) {
      context.handle(
        _personalityMeta,
        personality.isAcceptableOrUnknown(
          data['personality']!,
          _personalityMeta,
        ),
      );
    }
    if (data.containsKey('scenario')) {
      context.handle(
        _scenarioMeta,
        scenario.isAcceptableOrUnknown(data['scenario']!, _scenarioMeta),
      );
    }
    if (data.containsKey('first_mes')) {
      context.handle(
        _firstMesMeta,
        firstMes.isAcceptableOrUnknown(data['first_mes']!, _firstMesMeta),
      );
    }
    if (data.containsKey('mes_example')) {
      context.handle(
        _mesExampleMeta,
        mesExample.isAcceptableOrUnknown(data['mes_example']!, _mesExampleMeta),
      );
    }
    if (data.containsKey('system_prompt')) {
      context.handle(
        _systemPromptMeta,
        systemPrompt.isAcceptableOrUnknown(
          data['system_prompt']!,
          _systemPromptMeta,
        ),
      );
    }
    if (data.containsKey('post_history_instructions')) {
      context.handle(
        _postHistoryInstructionsMeta,
        postHistoryInstructions.isAcceptableOrUnknown(
          data['post_history_instructions']!,
          _postHistoryInstructionsMeta,
        ),
      );
    }
    if (data.containsKey('creator')) {
      context.handle(
        _creatorMeta,
        creator.isAcceptableOrUnknown(data['creator']!, _creatorMeta),
      );
    }
    if (data.containsKey('creator_notes')) {
      context.handle(
        _creatorNotesMeta,
        creatorNotes.isAcceptableOrUnknown(
          data['creator_notes']!,
          _creatorNotesMeta,
        ),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('alternate_greetings_json')) {
      context.handle(
        _alternateGreetingsJsonMeta,
        alternateGreetingsJson.isAcceptableOrUnknown(
          data['alternate_greetings_json']!,
          _alternateGreetingsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {charId};
  @override
  CharacterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CharacterRow(
      charId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}char_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatarPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_path'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      personality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}personality'],
      ),
      scenario: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scenario'],
      ),
      firstMes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_mes'],
      ),
      mesExample: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mes_example'],
      ),
      systemPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}system_prompt'],
      ),
      postHistoryInstructions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_history_instructions'],
      ),
      creator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creator'],
      ),
      creatorNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creator_notes'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      ),
      alternateGreetingsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alternate_greetings_json'],
      ),
    );
  }

  @override
  $CharactersTable createAlias(String alias) {
    return $CharactersTable(attachedDatabase, alias);
  }
}

class CharacterRow extends DataClass implements Insertable<CharacterRow> {
  final String charId;
  final String name;
  final String? avatarPath;
  final String? description;
  final String? personality;
  final String? scenario;
  final String? firstMes;
  final String? mesExample;
  final String? systemPrompt;
  final String? postHistoryInstructions;
  final String? creator;
  final String? creatorNotes;
  final String? color;
  final int updatedAt;
  final String? tagsJson;
  final String? alternateGreetingsJson;
  const CharacterRow({
    required this.charId,
    required this.name,
    this.avatarPath,
    this.description,
    this.personality,
    this.scenario,
    this.firstMes,
    this.mesExample,
    this.systemPrompt,
    this.postHistoryInstructions,
    this.creator,
    this.creatorNotes,
    this.color,
    required this.updatedAt,
    this.tagsJson,
    this.alternateGreetingsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['char_id'] = Variable<String>(charId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || avatarPath != null) {
      map['avatar_path'] = Variable<String>(avatarPath);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || personality != null) {
      map['personality'] = Variable<String>(personality);
    }
    if (!nullToAbsent || scenario != null) {
      map['scenario'] = Variable<String>(scenario);
    }
    if (!nullToAbsent || firstMes != null) {
      map['first_mes'] = Variable<String>(firstMes);
    }
    if (!nullToAbsent || mesExample != null) {
      map['mes_example'] = Variable<String>(mesExample);
    }
    if (!nullToAbsent || systemPrompt != null) {
      map['system_prompt'] = Variable<String>(systemPrompt);
    }
    if (!nullToAbsent || postHistoryInstructions != null) {
      map['post_history_instructions'] = Variable<String>(
        postHistoryInstructions,
      );
    }
    if (!nullToAbsent || creator != null) {
      map['creator'] = Variable<String>(creator);
    }
    if (!nullToAbsent || creatorNotes != null) {
      map['creator_notes'] = Variable<String>(creatorNotes);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || tagsJson != null) {
      map['tags_json'] = Variable<String>(tagsJson);
    }
    if (!nullToAbsent || alternateGreetingsJson != null) {
      map['alternate_greetings_json'] = Variable<String>(
        alternateGreetingsJson,
      );
    }
    return map;
  }

  CharactersCompanion toCompanion(bool nullToAbsent) {
    return CharactersCompanion(
      charId: Value(charId),
      name: Value(name),
      avatarPath: avatarPath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarPath),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      personality: personality == null && nullToAbsent
          ? const Value.absent()
          : Value(personality),
      scenario: scenario == null && nullToAbsent
          ? const Value.absent()
          : Value(scenario),
      firstMes: firstMes == null && nullToAbsent
          ? const Value.absent()
          : Value(firstMes),
      mesExample: mesExample == null && nullToAbsent
          ? const Value.absent()
          : Value(mesExample),
      systemPrompt: systemPrompt == null && nullToAbsent
          ? const Value.absent()
          : Value(systemPrompt),
      postHistoryInstructions: postHistoryInstructions == null && nullToAbsent
          ? const Value.absent()
          : Value(postHistoryInstructions),
      creator: creator == null && nullToAbsent
          ? const Value.absent()
          : Value(creator),
      creatorNotes: creatorNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(creatorNotes),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      updatedAt: Value(updatedAt),
      tagsJson: tagsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(tagsJson),
      alternateGreetingsJson: alternateGreetingsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(alternateGreetingsJson),
    );
  }

  factory CharacterRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CharacterRow(
      charId: serializer.fromJson<String>(json['charId']),
      name: serializer.fromJson<String>(json['name']),
      avatarPath: serializer.fromJson<String?>(json['avatarPath']),
      description: serializer.fromJson<String?>(json['description']),
      personality: serializer.fromJson<String?>(json['personality']),
      scenario: serializer.fromJson<String?>(json['scenario']),
      firstMes: serializer.fromJson<String?>(json['firstMes']),
      mesExample: serializer.fromJson<String?>(json['mesExample']),
      systemPrompt: serializer.fromJson<String?>(json['systemPrompt']),
      postHistoryInstructions: serializer.fromJson<String?>(
        json['postHistoryInstructions'],
      ),
      creator: serializer.fromJson<String?>(json['creator']),
      creatorNotes: serializer.fromJson<String?>(json['creatorNotes']),
      color: serializer.fromJson<String?>(json['color']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      tagsJson: serializer.fromJson<String?>(json['tagsJson']),
      alternateGreetingsJson: serializer.fromJson<String?>(
        json['alternateGreetingsJson'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'charId': serializer.toJson<String>(charId),
      'name': serializer.toJson<String>(name),
      'avatarPath': serializer.toJson<String?>(avatarPath),
      'description': serializer.toJson<String?>(description),
      'personality': serializer.toJson<String?>(personality),
      'scenario': serializer.toJson<String?>(scenario),
      'firstMes': serializer.toJson<String?>(firstMes),
      'mesExample': serializer.toJson<String?>(mesExample),
      'systemPrompt': serializer.toJson<String?>(systemPrompt),
      'postHistoryInstructions': serializer.toJson<String?>(
        postHistoryInstructions,
      ),
      'creator': serializer.toJson<String?>(creator),
      'creatorNotes': serializer.toJson<String?>(creatorNotes),
      'color': serializer.toJson<String?>(color),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'tagsJson': serializer.toJson<String?>(tagsJson),
      'alternateGreetingsJson': serializer.toJson<String?>(
        alternateGreetingsJson,
      ),
    };
  }

  CharacterRow copyWith({
    String? charId,
    String? name,
    Value<String?> avatarPath = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> personality = const Value.absent(),
    Value<String?> scenario = const Value.absent(),
    Value<String?> firstMes = const Value.absent(),
    Value<String?> mesExample = const Value.absent(),
    Value<String?> systemPrompt = const Value.absent(),
    Value<String?> postHistoryInstructions = const Value.absent(),
    Value<String?> creator = const Value.absent(),
    Value<String?> creatorNotes = const Value.absent(),
    Value<String?> color = const Value.absent(),
    int? updatedAt,
    Value<String?> tagsJson = const Value.absent(),
    Value<String?> alternateGreetingsJson = const Value.absent(),
  }) => CharacterRow(
    charId: charId ?? this.charId,
    name: name ?? this.name,
    avatarPath: avatarPath.present ? avatarPath.value : this.avatarPath,
    description: description.present ? description.value : this.description,
    personality: personality.present ? personality.value : this.personality,
    scenario: scenario.present ? scenario.value : this.scenario,
    firstMes: firstMes.present ? firstMes.value : this.firstMes,
    mesExample: mesExample.present ? mesExample.value : this.mesExample,
    systemPrompt: systemPrompt.present ? systemPrompt.value : this.systemPrompt,
    postHistoryInstructions: postHistoryInstructions.present
        ? postHistoryInstructions.value
        : this.postHistoryInstructions,
    creator: creator.present ? creator.value : this.creator,
    creatorNotes: creatorNotes.present ? creatorNotes.value : this.creatorNotes,
    color: color.present ? color.value : this.color,
    updatedAt: updatedAt ?? this.updatedAt,
    tagsJson: tagsJson.present ? tagsJson.value : this.tagsJson,
    alternateGreetingsJson: alternateGreetingsJson.present
        ? alternateGreetingsJson.value
        : this.alternateGreetingsJson,
  );
  CharacterRow copyWithCompanion(CharactersCompanion data) {
    return CharacterRow(
      charId: data.charId.present ? data.charId.value : this.charId,
      name: data.name.present ? data.name.value : this.name,
      avatarPath: data.avatarPath.present
          ? data.avatarPath.value
          : this.avatarPath,
      description: data.description.present
          ? data.description.value
          : this.description,
      personality: data.personality.present
          ? data.personality.value
          : this.personality,
      scenario: data.scenario.present ? data.scenario.value : this.scenario,
      firstMes: data.firstMes.present ? data.firstMes.value : this.firstMes,
      mesExample: data.mesExample.present
          ? data.mesExample.value
          : this.mesExample,
      systemPrompt: data.systemPrompt.present
          ? data.systemPrompt.value
          : this.systemPrompt,
      postHistoryInstructions: data.postHistoryInstructions.present
          ? data.postHistoryInstructions.value
          : this.postHistoryInstructions,
      creator: data.creator.present ? data.creator.value : this.creator,
      creatorNotes: data.creatorNotes.present
          ? data.creatorNotes.value
          : this.creatorNotes,
      color: data.color.present ? data.color.value : this.color,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      alternateGreetingsJson: data.alternateGreetingsJson.present
          ? data.alternateGreetingsJson.value
          : this.alternateGreetingsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CharacterRow(')
          ..write('charId: $charId, ')
          ..write('name: $name, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('description: $description, ')
          ..write('personality: $personality, ')
          ..write('scenario: $scenario, ')
          ..write('firstMes: $firstMes, ')
          ..write('mesExample: $mesExample, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('postHistoryInstructions: $postHistoryInstructions, ')
          ..write('creator: $creator, ')
          ..write('creatorNotes: $creatorNotes, ')
          ..write('color: $color, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('alternateGreetingsJson: $alternateGreetingsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    charId,
    name,
    avatarPath,
    description,
    personality,
    scenario,
    firstMes,
    mesExample,
    systemPrompt,
    postHistoryInstructions,
    creator,
    creatorNotes,
    color,
    updatedAt,
    tagsJson,
    alternateGreetingsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CharacterRow &&
          other.charId == this.charId &&
          other.name == this.name &&
          other.avatarPath == this.avatarPath &&
          other.description == this.description &&
          other.personality == this.personality &&
          other.scenario == this.scenario &&
          other.firstMes == this.firstMes &&
          other.mesExample == this.mesExample &&
          other.systemPrompt == this.systemPrompt &&
          other.postHistoryInstructions == this.postHistoryInstructions &&
          other.creator == this.creator &&
          other.creatorNotes == this.creatorNotes &&
          other.color == this.color &&
          other.updatedAt == this.updatedAt &&
          other.tagsJson == this.tagsJson &&
          other.alternateGreetingsJson == this.alternateGreetingsJson);
}

class CharactersCompanion extends UpdateCompanion<CharacterRow> {
  final Value<String> charId;
  final Value<String> name;
  final Value<String?> avatarPath;
  final Value<String?> description;
  final Value<String?> personality;
  final Value<String?> scenario;
  final Value<String?> firstMes;
  final Value<String?> mesExample;
  final Value<String?> systemPrompt;
  final Value<String?> postHistoryInstructions;
  final Value<String?> creator;
  final Value<String?> creatorNotes;
  final Value<String?> color;
  final Value<int> updatedAt;
  final Value<String?> tagsJson;
  final Value<String?> alternateGreetingsJson;
  final Value<int> rowid;
  const CharactersCompanion({
    this.charId = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.description = const Value.absent(),
    this.personality = const Value.absent(),
    this.scenario = const Value.absent(),
    this.firstMes = const Value.absent(),
    this.mesExample = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.postHistoryInstructions = const Value.absent(),
    this.creator = const Value.absent(),
    this.creatorNotes = const Value.absent(),
    this.color = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.alternateGreetingsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CharactersCompanion.insert({
    required String charId,
    required String name,
    this.avatarPath = const Value.absent(),
    this.description = const Value.absent(),
    this.personality = const Value.absent(),
    this.scenario = const Value.absent(),
    this.firstMes = const Value.absent(),
    this.mesExample = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.postHistoryInstructions = const Value.absent(),
    this.creator = const Value.absent(),
    this.creatorNotes = const Value.absent(),
    this.color = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.alternateGreetingsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : charId = Value(charId),
       name = Value(name);
  static Insertable<CharacterRow> custom({
    Expression<String>? charId,
    Expression<String>? name,
    Expression<String>? avatarPath,
    Expression<String>? description,
    Expression<String>? personality,
    Expression<String>? scenario,
    Expression<String>? firstMes,
    Expression<String>? mesExample,
    Expression<String>? systemPrompt,
    Expression<String>? postHistoryInstructions,
    Expression<String>? creator,
    Expression<String>? creatorNotes,
    Expression<String>? color,
    Expression<int>? updatedAt,
    Expression<String>? tagsJson,
    Expression<String>? alternateGreetingsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (charId != null) 'char_id': charId,
      if (name != null) 'name': name,
      if (avatarPath != null) 'avatar_path': avatarPath,
      if (description != null) 'description': description,
      if (personality != null) 'personality': personality,
      if (scenario != null) 'scenario': scenario,
      if (firstMes != null) 'first_mes': firstMes,
      if (mesExample != null) 'mes_example': mesExample,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
      if (postHistoryInstructions != null)
        'post_history_instructions': postHistoryInstructions,
      if (creator != null) 'creator': creator,
      if (creatorNotes != null) 'creator_notes': creatorNotes,
      if (color != null) 'color': color,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (alternateGreetingsJson != null)
        'alternate_greetings_json': alternateGreetingsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CharactersCompanion copyWith({
    Value<String>? charId,
    Value<String>? name,
    Value<String?>? avatarPath,
    Value<String?>? description,
    Value<String?>? personality,
    Value<String?>? scenario,
    Value<String?>? firstMes,
    Value<String?>? mesExample,
    Value<String?>? systemPrompt,
    Value<String?>? postHistoryInstructions,
    Value<String?>? creator,
    Value<String?>? creatorNotes,
    Value<String?>? color,
    Value<int>? updatedAt,
    Value<String?>? tagsJson,
    Value<String?>? alternateGreetingsJson,
    Value<int>? rowid,
  }) {
    return CharactersCompanion(
      charId: charId ?? this.charId,
      name: name ?? this.name,
      avatarPath: avatarPath ?? this.avatarPath,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      scenario: scenario ?? this.scenario,
      firstMes: firstMes ?? this.firstMes,
      mesExample: mesExample ?? this.mesExample,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      postHistoryInstructions:
          postHistoryInstructions ?? this.postHistoryInstructions,
      creator: creator ?? this.creator,
      creatorNotes: creatorNotes ?? this.creatorNotes,
      color: color ?? this.color,
      updatedAt: updatedAt ?? this.updatedAt,
      tagsJson: tagsJson ?? this.tagsJson,
      alternateGreetingsJson:
          alternateGreetingsJson ?? this.alternateGreetingsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (charId.present) {
      map['char_id'] = Variable<String>(charId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatarPath.present) {
      map['avatar_path'] = Variable<String>(avatarPath.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (personality.present) {
      map['personality'] = Variable<String>(personality.value);
    }
    if (scenario.present) {
      map['scenario'] = Variable<String>(scenario.value);
    }
    if (firstMes.present) {
      map['first_mes'] = Variable<String>(firstMes.value);
    }
    if (mesExample.present) {
      map['mes_example'] = Variable<String>(mesExample.value);
    }
    if (systemPrompt.present) {
      map['system_prompt'] = Variable<String>(systemPrompt.value);
    }
    if (postHistoryInstructions.present) {
      map['post_history_instructions'] = Variable<String>(
        postHistoryInstructions.value,
      );
    }
    if (creator.present) {
      map['creator'] = Variable<String>(creator.value);
    }
    if (creatorNotes.present) {
      map['creator_notes'] = Variable<String>(creatorNotes.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (alternateGreetingsJson.present) {
      map['alternate_greetings_json'] = Variable<String>(
        alternateGreetingsJson.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CharactersCompanion(')
          ..write('charId: $charId, ')
          ..write('name: $name, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('description: $description, ')
          ..write('personality: $personality, ')
          ..write('scenario: $scenario, ')
          ..write('firstMes: $firstMes, ')
          ..write('mesExample: $mesExample, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('postHistoryInstructions: $postHistoryInstructions, ')
          ..write('creator: $creator, ')
          ..write('creatorNotes: $creatorNotes, ')
          ..write('color: $color, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('alternateGreetingsJson: $alternateGreetingsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatSessionsTable extends ChatSessions
    with TableInfo<$ChatSessionsTable, ChatSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIndexMeta = const VerificationMeta(
    'sessionIndex',
  );
  @override
  late final GeneratedColumn<int> sessionIndex = GeneratedColumn<int>(
    'session_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messagesJsonMeta = const VerificationMeta(
    'messagesJson',
  );
  @override
  late final GeneratedColumn<String> messagesJson = GeneratedColumn<String>(
    'messages_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sessionVarsJsonMeta = const VerificationMeta(
    'sessionVarsJson',
  );
  @override
  late final GeneratedColumn<String> sessionVarsJson = GeneratedColumn<String>(
    'session_vars_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    characterId,
    sessionIndex,
    messagesJson,
    updatedAt,
    sessionVarsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('session_index')) {
      context.handle(
        _sessionIndexMeta,
        sessionIndex.isAcceptableOrUnknown(
          data['session_index']!,
          _sessionIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionIndexMeta);
    }
    if (data.containsKey('messages_json')) {
      context.handle(
        _messagesJsonMeta,
        messagesJson.isAcceptableOrUnknown(
          data['messages_json']!,
          _messagesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messagesJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('session_vars_json')) {
      context.handle(
        _sessionVarsJsonMeta,
        sessionVarsJson.isAcceptableOrUnknown(
          data['session_vars_json']!,
          _sessionVarsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  ChatSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatSessionRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}character_id'],
      )!,
      sessionIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_index'],
      )!,
      messagesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}messages_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      sessionVarsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_vars_json'],
      ),
    );
  }

  @override
  $ChatSessionsTable createAlias(String alias) {
    return $ChatSessionsTable(attachedDatabase, alias);
  }
}

class ChatSessionRow extends DataClass implements Insertable<ChatSessionRow> {
  final String sessionId;
  final String characterId;
  final int sessionIndex;
  final String messagesJson;
  final int updatedAt;
  final String? sessionVarsJson;
  const ChatSessionRow({
    required this.sessionId,
    required this.characterId,
    required this.sessionIndex,
    required this.messagesJson,
    required this.updatedAt,
    this.sessionVarsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['character_id'] = Variable<String>(characterId);
    map['session_index'] = Variable<int>(sessionIndex);
    map['messages_json'] = Variable<String>(messagesJson);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || sessionVarsJson != null) {
      map['session_vars_json'] = Variable<String>(sessionVarsJson);
    }
    return map;
  }

  ChatSessionsCompanion toCompanion(bool nullToAbsent) {
    return ChatSessionsCompanion(
      sessionId: Value(sessionId),
      characterId: Value(characterId),
      sessionIndex: Value(sessionIndex),
      messagesJson: Value(messagesJson),
      updatedAt: Value(updatedAt),
      sessionVarsJson: sessionVarsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionVarsJson),
    );
  }

  factory ChatSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatSessionRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      characterId: serializer.fromJson<String>(json['characterId']),
      sessionIndex: serializer.fromJson<int>(json['sessionIndex']),
      messagesJson: serializer.fromJson<String>(json['messagesJson']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      sessionVarsJson: serializer.fromJson<String?>(json['sessionVarsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'characterId': serializer.toJson<String>(characterId),
      'sessionIndex': serializer.toJson<int>(sessionIndex),
      'messagesJson': serializer.toJson<String>(messagesJson),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'sessionVarsJson': serializer.toJson<String?>(sessionVarsJson),
    };
  }

  ChatSessionRow copyWith({
    String? sessionId,
    String? characterId,
    int? sessionIndex,
    String? messagesJson,
    int? updatedAt,
    Value<String?> sessionVarsJson = const Value.absent(),
  }) => ChatSessionRow(
    sessionId: sessionId ?? this.sessionId,
    characterId: characterId ?? this.characterId,
    sessionIndex: sessionIndex ?? this.sessionIndex,
    messagesJson: messagesJson ?? this.messagesJson,
    updatedAt: updatedAt ?? this.updatedAt,
    sessionVarsJson: sessionVarsJson.present
        ? sessionVarsJson.value
        : this.sessionVarsJson,
  );
  ChatSessionRow copyWithCompanion(ChatSessionsCompanion data) {
    return ChatSessionRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      sessionIndex: data.sessionIndex.present
          ? data.sessionIndex.value
          : this.sessionIndex,
      messagesJson: data.messagesJson.present
          ? data.messagesJson.value
          : this.messagesJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sessionVarsJson: data.sessionVarsJson.present
          ? data.sessionVarsJson.value
          : this.sessionVarsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionRow(')
          ..write('sessionId: $sessionId, ')
          ..write('characterId: $characterId, ')
          ..write('sessionIndex: $sessionIndex, ')
          ..write('messagesJson: $messagesJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sessionVarsJson: $sessionVarsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    characterId,
    sessionIndex,
    messagesJson,
    updatedAt,
    sessionVarsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSessionRow &&
          other.sessionId == this.sessionId &&
          other.characterId == this.characterId &&
          other.sessionIndex == this.sessionIndex &&
          other.messagesJson == this.messagesJson &&
          other.updatedAt == this.updatedAt &&
          other.sessionVarsJson == this.sessionVarsJson);
}

class ChatSessionsCompanion extends UpdateCompanion<ChatSessionRow> {
  final Value<String> sessionId;
  final Value<String> characterId;
  final Value<int> sessionIndex;
  final Value<String> messagesJson;
  final Value<int> updatedAt;
  final Value<String?> sessionVarsJson;
  final Value<int> rowid;
  const ChatSessionsCompanion({
    this.sessionId = const Value.absent(),
    this.characterId = const Value.absent(),
    this.sessionIndex = const Value.absent(),
    this.messagesJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sessionVarsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatSessionsCompanion.insert({
    required String sessionId,
    required String characterId,
    required int sessionIndex,
    required String messagesJson,
    this.updatedAt = const Value.absent(),
    this.sessionVarsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       characterId = Value(characterId),
       sessionIndex = Value(sessionIndex),
       messagesJson = Value(messagesJson);
  static Insertable<ChatSessionRow> custom({
    Expression<String>? sessionId,
    Expression<String>? characterId,
    Expression<int>? sessionIndex,
    Expression<String>? messagesJson,
    Expression<int>? updatedAt,
    Expression<String>? sessionVarsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (characterId != null) 'character_id': characterId,
      if (sessionIndex != null) 'session_index': sessionIndex,
      if (messagesJson != null) 'messages_json': messagesJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sessionVarsJson != null) 'session_vars_json': sessionVarsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatSessionsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? characterId,
    Value<int>? sessionIndex,
    Value<String>? messagesJson,
    Value<int>? updatedAt,
    Value<String?>? sessionVarsJson,
    Value<int>? rowid,
  }) {
    return ChatSessionsCompanion(
      sessionId: sessionId ?? this.sessionId,
      characterId: characterId ?? this.characterId,
      sessionIndex: sessionIndex ?? this.sessionIndex,
      messagesJson: messagesJson ?? this.messagesJson,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionVarsJson: sessionVarsJson ?? this.sessionVarsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (sessionIndex.present) {
      map['session_index'] = Variable<int>(sessionIndex.value);
    }
    if (messagesJson.present) {
      map['messages_json'] = Variable<String>(messagesJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (sessionVarsJson.present) {
      map['session_vars_json'] = Variable<String>(sessionVarsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('characterId: $characterId, ')
          ..write('sessionIndex: $sessionIndex, ')
          ..write('messagesJson: $messagesJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sessionVarsJson: $sessionVarsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PresetsTable extends Presets with TableInfo<$PresetsTable, PresetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _presetIdMeta = const VerificationMeta(
    'presetId',
  );
  @override
  late final GeneratedColumn<String> presetId = GeneratedColumn<String>(
    'preset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [presetId, name, dataJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'presets';
  @override
  VerificationContext validateIntegrity(
    Insertable<PresetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('preset_id')) {
      context.handle(
        _presetIdMeta,
        presetId.isAcceptableOrUnknown(data['preset_id']!, _presetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_presetIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {presetId};
  @override
  PresetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PresetRow(
      presetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preset_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
    );
  }

  @override
  $PresetsTable createAlias(String alias) {
    return $PresetsTable(attachedDatabase, alias);
  }
}

class PresetRow extends DataClass implements Insertable<PresetRow> {
  final String presetId;
  final String name;
  final String dataJson;
  const PresetRow({
    required this.presetId,
    required this.name,
    required this.dataJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['preset_id'] = Variable<String>(presetId);
    map['name'] = Variable<String>(name);
    map['data_json'] = Variable<String>(dataJson);
    return map;
  }

  PresetsCompanion toCompanion(bool nullToAbsent) {
    return PresetsCompanion(
      presetId: Value(presetId),
      name: Value(name),
      dataJson: Value(dataJson),
    );
  }

  factory PresetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PresetRow(
      presetId: serializer.fromJson<String>(json['presetId']),
      name: serializer.fromJson<String>(json['name']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'presetId': serializer.toJson<String>(presetId),
      'name': serializer.toJson<String>(name),
      'dataJson': serializer.toJson<String>(dataJson),
    };
  }

  PresetRow copyWith({String? presetId, String? name, String? dataJson}) =>
      PresetRow(
        presetId: presetId ?? this.presetId,
        name: name ?? this.name,
        dataJson: dataJson ?? this.dataJson,
      );
  PresetRow copyWithCompanion(PresetsCompanion data) {
    return PresetRow(
      presetId: data.presetId.present ? data.presetId.value : this.presetId,
      name: data.name.present ? data.name.value : this.name,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PresetRow(')
          ..write('presetId: $presetId, ')
          ..write('name: $name, ')
          ..write('dataJson: $dataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(presetId, name, dataJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PresetRow &&
          other.presetId == this.presetId &&
          other.name == this.name &&
          other.dataJson == this.dataJson);
}

class PresetsCompanion extends UpdateCompanion<PresetRow> {
  final Value<String> presetId;
  final Value<String> name;
  final Value<String> dataJson;
  final Value<int> rowid;
  const PresetsCompanion({
    this.presetId = const Value.absent(),
    this.name = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PresetsCompanion.insert({
    required String presetId,
    required String name,
    required String dataJson,
    this.rowid = const Value.absent(),
  }) : presetId = Value(presetId),
       name = Value(name),
       dataJson = Value(dataJson);
  static Insertable<PresetRow> custom({
    Expression<String>? presetId,
    Expression<String>? name,
    Expression<String>? dataJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (presetId != null) 'preset_id': presetId,
      if (name != null) 'name': name,
      if (dataJson != null) 'data_json': dataJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PresetsCompanion copyWith({
    Value<String>? presetId,
    Value<String>? name,
    Value<String>? dataJson,
    Value<int>? rowid,
  }) {
    return PresetsCompanion(
      presetId: presetId ?? this.presetId,
      name: name ?? this.name,
      dataJson: dataJson ?? this.dataJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (presetId.present) {
      map['preset_id'] = Variable<String>(presetId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PresetsCompanion(')
          ..write('presetId: $presetId, ')
          ..write('name: $name, ')
          ..write('dataJson: $dataJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ApiConfigsTable extends ApiConfigs
    with TableInfo<$ApiConfigsTable, ApiConfigRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ApiConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _configIdMeta = const VerificationMeta(
    'configId',
  );
  @override
  late final GeneratedColumn<String> configId = GeneratedColumn<String>(
    'config_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('openai_compatible'),
  );
  static const VerificationMeta _endpointMeta = const VerificationMeta(
    'endpoint',
  );
  @override
  late final GeneratedColumn<String> endpoint = GeneratedColumn<String>(
    'endpoint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _apiKeyMeta = const VerificationMeta('apiKey');
  @override
  late final GeneratedColumn<String> apiKey = GeneratedColumn<String>(
    'api_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('chat'),
  );
  static const VerificationMeta _maxTokensMeta = const VerificationMeta(
    'maxTokens',
  );
  @override
  late final GeneratedColumn<int> maxTokens = GeneratedColumn<int>(
    'max_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(8000),
  );
  static const VerificationMeta _contextSizeMeta = const VerificationMeta(
    'contextSize',
  );
  @override
  late final GeneratedColumn<int> contextSize = GeneratedColumn<int>(
    'context_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(32000),
  );
  static const VerificationMeta _temperatureMeta = const VerificationMeta(
    'temperature',
  );
  @override
  late final GeneratedColumn<double> temperature = GeneratedColumn<double>(
    'temperature',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.7),
  );
  static const VerificationMeta _topPMeta = const VerificationMeta('topP');
  @override
  late final GeneratedColumn<double> topP = GeneratedColumn<double>(
    'top_p',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.9),
  );
  static const VerificationMeta _streamMeta = const VerificationMeta('stream');
  @override
  late final GeneratedColumn<bool> stream = GeneratedColumn<bool>(
    'stream',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stream" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _reasoningEffortMeta = const VerificationMeta(
    'reasoningEffort',
  );
  @override
  late final GeneratedColumn<String> reasoningEffort = GeneratedColumn<String>(
    'reasoning_effort',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requestReasoningMeta = const VerificationMeta(
    'requestReasoning',
  );
  @override
  late final GeneratedColumn<bool> requestReasoning = GeneratedColumn<bool>(
    'request_reasoning',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("request_reasoning" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _reasoningTagStartMeta = const VerificationMeta(
    'reasoningTagStart',
  );
  @override
  late final GeneratedColumn<String> reasoningTagStart =
      GeneratedColumn<String>(
        'reasoning_tag_start',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _reasoningTagEndMeta = const VerificationMeta(
    'reasoningTagEnd',
  );
  @override
  late final GeneratedColumn<String> reasoningTagEnd = GeneratedColumn<String>(
    'reasoning_tag_end',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    configId,
    name,
    providerId,
    endpoint,
    apiKey,
    model,
    mode,
    maxTokens,
    contextSize,
    temperature,
    topP,
    stream,
    reasoningEffort,
    requestReasoning,
    reasoningTagStart,
    reasoningTagEnd,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'api_configs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ApiConfigRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('config_id')) {
      context.handle(
        _configIdMeta,
        configId.isAcceptableOrUnknown(data['config_id']!, _configIdMeta),
      );
    } else if (isInserting) {
      context.missing(_configIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    }
    if (data.containsKey('endpoint')) {
      context.handle(
        _endpointMeta,
        endpoint.isAcceptableOrUnknown(data['endpoint']!, _endpointMeta),
      );
    }
    if (data.containsKey('api_key')) {
      context.handle(
        _apiKeyMeta,
        apiKey.isAcceptableOrUnknown(data['api_key']!, _apiKeyMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    if (data.containsKey('max_tokens')) {
      context.handle(
        _maxTokensMeta,
        maxTokens.isAcceptableOrUnknown(data['max_tokens']!, _maxTokensMeta),
      );
    }
    if (data.containsKey('context_size')) {
      context.handle(
        _contextSizeMeta,
        contextSize.isAcceptableOrUnknown(
          data['context_size']!,
          _contextSizeMeta,
        ),
      );
    }
    if (data.containsKey('temperature')) {
      context.handle(
        _temperatureMeta,
        temperature.isAcceptableOrUnknown(
          data['temperature']!,
          _temperatureMeta,
        ),
      );
    }
    if (data.containsKey('top_p')) {
      context.handle(
        _topPMeta,
        topP.isAcceptableOrUnknown(data['top_p']!, _topPMeta),
      );
    }
    if (data.containsKey('stream')) {
      context.handle(
        _streamMeta,
        stream.isAcceptableOrUnknown(data['stream']!, _streamMeta),
      );
    }
    if (data.containsKey('reasoning_effort')) {
      context.handle(
        _reasoningEffortMeta,
        reasoningEffort.isAcceptableOrUnknown(
          data['reasoning_effort']!,
          _reasoningEffortMeta,
        ),
      );
    }
    if (data.containsKey('request_reasoning')) {
      context.handle(
        _requestReasoningMeta,
        requestReasoning.isAcceptableOrUnknown(
          data['request_reasoning']!,
          _requestReasoningMeta,
        ),
      );
    }
    if (data.containsKey('reasoning_tag_start')) {
      context.handle(
        _reasoningTagStartMeta,
        reasoningTagStart.isAcceptableOrUnknown(
          data['reasoning_tag_start']!,
          _reasoningTagStartMeta,
        ),
      );
    }
    if (data.containsKey('reasoning_tag_end')) {
      context.handle(
        _reasoningTagEndMeta,
        reasoningTagEnd.isAcceptableOrUnknown(
          data['reasoning_tag_end']!,
          _reasoningTagEndMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {configId};
  @override
  ApiConfigRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ApiConfigRow(
      configId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      )!,
      endpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}endpoint'],
      ),
      apiKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}api_key'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      maxTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_tokens'],
      )!,
      contextSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}context_size'],
      )!,
      temperature: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}temperature'],
      )!,
      topP: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}top_p'],
      )!,
      stream: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stream'],
      )!,
      reasoningEffort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning_effort'],
      ),
      requestReasoning: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}request_reasoning'],
      )!,
      reasoningTagStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning_tag_start'],
      ),
      reasoningTagEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning_tag_end'],
      ),
    );
  }

  @override
  $ApiConfigsTable createAlias(String alias) {
    return $ApiConfigsTable(attachedDatabase, alias);
  }
}

class ApiConfigRow extends DataClass implements Insertable<ApiConfigRow> {
  final String configId;
  final String name;
  final String providerId;
  final String? endpoint;
  final String? apiKey;
  final String? model;
  final String mode;
  final int maxTokens;
  final int contextSize;
  final double temperature;
  final double topP;
  final bool stream;
  final String? reasoningEffort;
  final bool requestReasoning;
  final String? reasoningTagStart;
  final String? reasoningTagEnd;
  const ApiConfigRow({
    required this.configId,
    required this.name,
    required this.providerId,
    this.endpoint,
    this.apiKey,
    this.model,
    required this.mode,
    required this.maxTokens,
    required this.contextSize,
    required this.temperature,
    required this.topP,
    required this.stream,
    this.reasoningEffort,
    required this.requestReasoning,
    this.reasoningTagStart,
    this.reasoningTagEnd,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['config_id'] = Variable<String>(configId);
    map['name'] = Variable<String>(name);
    map['provider_id'] = Variable<String>(providerId);
    if (!nullToAbsent || endpoint != null) {
      map['endpoint'] = Variable<String>(endpoint);
    }
    if (!nullToAbsent || apiKey != null) {
      map['api_key'] = Variable<String>(apiKey);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    map['mode'] = Variable<String>(mode);
    map['max_tokens'] = Variable<int>(maxTokens);
    map['context_size'] = Variable<int>(contextSize);
    map['temperature'] = Variable<double>(temperature);
    map['top_p'] = Variable<double>(topP);
    map['stream'] = Variable<bool>(stream);
    if (!nullToAbsent || reasoningEffort != null) {
      map['reasoning_effort'] = Variable<String>(reasoningEffort);
    }
    map['request_reasoning'] = Variable<bool>(requestReasoning);
    if (!nullToAbsent || reasoningTagStart != null) {
      map['reasoning_tag_start'] = Variable<String>(reasoningTagStart);
    }
    if (!nullToAbsent || reasoningTagEnd != null) {
      map['reasoning_tag_end'] = Variable<String>(reasoningTagEnd);
    }
    return map;
  }

  ApiConfigsCompanion toCompanion(bool nullToAbsent) {
    return ApiConfigsCompanion(
      configId: Value(configId),
      name: Value(name),
      providerId: Value(providerId),
      endpoint: endpoint == null && nullToAbsent
          ? const Value.absent()
          : Value(endpoint),
      apiKey: apiKey == null && nullToAbsent
          ? const Value.absent()
          : Value(apiKey),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      mode: Value(mode),
      maxTokens: Value(maxTokens),
      contextSize: Value(contextSize),
      temperature: Value(temperature),
      topP: Value(topP),
      stream: Value(stream),
      reasoningEffort: reasoningEffort == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoningEffort),
      requestReasoning: Value(requestReasoning),
      reasoningTagStart: reasoningTagStart == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoningTagStart),
      reasoningTagEnd: reasoningTagEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoningTagEnd),
    );
  }

  factory ApiConfigRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ApiConfigRow(
      configId: serializer.fromJson<String>(json['configId']),
      name: serializer.fromJson<String>(json['name']),
      providerId: serializer.fromJson<String>(json['providerId']),
      endpoint: serializer.fromJson<String?>(json['endpoint']),
      apiKey: serializer.fromJson<String?>(json['apiKey']),
      model: serializer.fromJson<String?>(json['model']),
      mode: serializer.fromJson<String>(json['mode']),
      maxTokens: serializer.fromJson<int>(json['maxTokens']),
      contextSize: serializer.fromJson<int>(json['contextSize']),
      temperature: serializer.fromJson<double>(json['temperature']),
      topP: serializer.fromJson<double>(json['topP']),
      stream: serializer.fromJson<bool>(json['stream']),
      reasoningEffort: serializer.fromJson<String?>(json['reasoningEffort']),
      requestReasoning: serializer.fromJson<bool>(json['requestReasoning']),
      reasoningTagStart: serializer.fromJson<String?>(
        json['reasoningTagStart'],
      ),
      reasoningTagEnd: serializer.fromJson<String?>(json['reasoningTagEnd']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'configId': serializer.toJson<String>(configId),
      'name': serializer.toJson<String>(name),
      'providerId': serializer.toJson<String>(providerId),
      'endpoint': serializer.toJson<String?>(endpoint),
      'apiKey': serializer.toJson<String?>(apiKey),
      'model': serializer.toJson<String?>(model),
      'mode': serializer.toJson<String>(mode),
      'maxTokens': serializer.toJson<int>(maxTokens),
      'contextSize': serializer.toJson<int>(contextSize),
      'temperature': serializer.toJson<double>(temperature),
      'topP': serializer.toJson<double>(topP),
      'stream': serializer.toJson<bool>(stream),
      'reasoningEffort': serializer.toJson<String?>(reasoningEffort),
      'requestReasoning': serializer.toJson<bool>(requestReasoning),
      'reasoningTagStart': serializer.toJson<String?>(reasoningTagStart),
      'reasoningTagEnd': serializer.toJson<String?>(reasoningTagEnd),
    };
  }

  ApiConfigRow copyWith({
    String? configId,
    String? name,
    String? providerId,
    Value<String?> endpoint = const Value.absent(),
    Value<String?> apiKey = const Value.absent(),
    Value<String?> model = const Value.absent(),
    String? mode,
    int? maxTokens,
    int? contextSize,
    double? temperature,
    double? topP,
    bool? stream,
    Value<String?> reasoningEffort = const Value.absent(),
    bool? requestReasoning,
    Value<String?> reasoningTagStart = const Value.absent(),
    Value<String?> reasoningTagEnd = const Value.absent(),
  }) => ApiConfigRow(
    configId: configId ?? this.configId,
    name: name ?? this.name,
    providerId: providerId ?? this.providerId,
    endpoint: endpoint.present ? endpoint.value : this.endpoint,
    apiKey: apiKey.present ? apiKey.value : this.apiKey,
    model: model.present ? model.value : this.model,
    mode: mode ?? this.mode,
    maxTokens: maxTokens ?? this.maxTokens,
    contextSize: contextSize ?? this.contextSize,
    temperature: temperature ?? this.temperature,
    topP: topP ?? this.topP,
    stream: stream ?? this.stream,
    reasoningEffort: reasoningEffort.present
        ? reasoningEffort.value
        : this.reasoningEffort,
    requestReasoning: requestReasoning ?? this.requestReasoning,
    reasoningTagStart: reasoningTagStart.present
        ? reasoningTagStart.value
        : this.reasoningTagStart,
    reasoningTagEnd: reasoningTagEnd.present
        ? reasoningTagEnd.value
        : this.reasoningTagEnd,
  );
  ApiConfigRow copyWithCompanion(ApiConfigsCompanion data) {
    return ApiConfigRow(
      configId: data.configId.present ? data.configId.value : this.configId,
      name: data.name.present ? data.name.value : this.name,
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      endpoint: data.endpoint.present ? data.endpoint.value : this.endpoint,
      apiKey: data.apiKey.present ? data.apiKey.value : this.apiKey,
      model: data.model.present ? data.model.value : this.model,
      mode: data.mode.present ? data.mode.value : this.mode,
      maxTokens: data.maxTokens.present ? data.maxTokens.value : this.maxTokens,
      contextSize: data.contextSize.present
          ? data.contextSize.value
          : this.contextSize,
      temperature: data.temperature.present
          ? data.temperature.value
          : this.temperature,
      topP: data.topP.present ? data.topP.value : this.topP,
      stream: data.stream.present ? data.stream.value : this.stream,
      reasoningEffort: data.reasoningEffort.present
          ? data.reasoningEffort.value
          : this.reasoningEffort,
      requestReasoning: data.requestReasoning.present
          ? data.requestReasoning.value
          : this.requestReasoning,
      reasoningTagStart: data.reasoningTagStart.present
          ? data.reasoningTagStart.value
          : this.reasoningTagStart,
      reasoningTagEnd: data.reasoningTagEnd.present
          ? data.reasoningTagEnd.value
          : this.reasoningTagEnd,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ApiConfigRow(')
          ..write('configId: $configId, ')
          ..write('name: $name, ')
          ..write('providerId: $providerId, ')
          ..write('endpoint: $endpoint, ')
          ..write('apiKey: $apiKey, ')
          ..write('model: $model, ')
          ..write('mode: $mode, ')
          ..write('maxTokens: $maxTokens, ')
          ..write('contextSize: $contextSize, ')
          ..write('temperature: $temperature, ')
          ..write('topP: $topP, ')
          ..write('stream: $stream, ')
          ..write('reasoningEffort: $reasoningEffort, ')
          ..write('requestReasoning: $requestReasoning, ')
          ..write('reasoningTagStart: $reasoningTagStart, ')
          ..write('reasoningTagEnd: $reasoningTagEnd')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    configId,
    name,
    providerId,
    endpoint,
    apiKey,
    model,
    mode,
    maxTokens,
    contextSize,
    temperature,
    topP,
    stream,
    reasoningEffort,
    requestReasoning,
    reasoningTagStart,
    reasoningTagEnd,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ApiConfigRow &&
          other.configId == this.configId &&
          other.name == this.name &&
          other.providerId == this.providerId &&
          other.endpoint == this.endpoint &&
          other.apiKey == this.apiKey &&
          other.model == this.model &&
          other.mode == this.mode &&
          other.maxTokens == this.maxTokens &&
          other.contextSize == this.contextSize &&
          other.temperature == this.temperature &&
          other.topP == this.topP &&
          other.stream == this.stream &&
          other.reasoningEffort == this.reasoningEffort &&
          other.requestReasoning == this.requestReasoning &&
          other.reasoningTagStart == this.reasoningTagStart &&
          other.reasoningTagEnd == this.reasoningTagEnd);
}

class ApiConfigsCompanion extends UpdateCompanion<ApiConfigRow> {
  final Value<String> configId;
  final Value<String> name;
  final Value<String> providerId;
  final Value<String?> endpoint;
  final Value<String?> apiKey;
  final Value<String?> model;
  final Value<String> mode;
  final Value<int> maxTokens;
  final Value<int> contextSize;
  final Value<double> temperature;
  final Value<double> topP;
  final Value<bool> stream;
  final Value<String?> reasoningEffort;
  final Value<bool> requestReasoning;
  final Value<String?> reasoningTagStart;
  final Value<String?> reasoningTagEnd;
  final Value<int> rowid;
  const ApiConfigsCompanion({
    this.configId = const Value.absent(),
    this.name = const Value.absent(),
    this.providerId = const Value.absent(),
    this.endpoint = const Value.absent(),
    this.apiKey = const Value.absent(),
    this.model = const Value.absent(),
    this.mode = const Value.absent(),
    this.maxTokens = const Value.absent(),
    this.contextSize = const Value.absent(),
    this.temperature = const Value.absent(),
    this.topP = const Value.absent(),
    this.stream = const Value.absent(),
    this.reasoningEffort = const Value.absent(),
    this.requestReasoning = const Value.absent(),
    this.reasoningTagStart = const Value.absent(),
    this.reasoningTagEnd = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ApiConfigsCompanion.insert({
    required String configId,
    required String name,
    this.providerId = const Value.absent(),
    this.endpoint = const Value.absent(),
    this.apiKey = const Value.absent(),
    this.model = const Value.absent(),
    this.mode = const Value.absent(),
    this.maxTokens = const Value.absent(),
    this.contextSize = const Value.absent(),
    this.temperature = const Value.absent(),
    this.topP = const Value.absent(),
    this.stream = const Value.absent(),
    this.reasoningEffort = const Value.absent(),
    this.requestReasoning = const Value.absent(),
    this.reasoningTagStart = const Value.absent(),
    this.reasoningTagEnd = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : configId = Value(configId),
       name = Value(name);
  static Insertable<ApiConfigRow> custom({
    Expression<String>? configId,
    Expression<String>? name,
    Expression<String>? providerId,
    Expression<String>? endpoint,
    Expression<String>? apiKey,
    Expression<String>? model,
    Expression<String>? mode,
    Expression<int>? maxTokens,
    Expression<int>? contextSize,
    Expression<double>? temperature,
    Expression<double>? topP,
    Expression<bool>? stream,
    Expression<String>? reasoningEffort,
    Expression<bool>? requestReasoning,
    Expression<String>? reasoningTagStart,
    Expression<String>? reasoningTagEnd,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (configId != null) 'config_id': configId,
      if (name != null) 'name': name,
      if (providerId != null) 'provider_id': providerId,
      if (endpoint != null) 'endpoint': endpoint,
      if (apiKey != null) 'api_key': apiKey,
      if (model != null) 'model': model,
      if (mode != null) 'mode': mode,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (contextSize != null) 'context_size': contextSize,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'top_p': topP,
      if (stream != null) 'stream': stream,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
      if (requestReasoning != null) 'request_reasoning': requestReasoning,
      if (reasoningTagStart != null) 'reasoning_tag_start': reasoningTagStart,
      if (reasoningTagEnd != null) 'reasoning_tag_end': reasoningTagEnd,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ApiConfigsCompanion copyWith({
    Value<String>? configId,
    Value<String>? name,
    Value<String>? providerId,
    Value<String?>? endpoint,
    Value<String?>? apiKey,
    Value<String?>? model,
    Value<String>? mode,
    Value<int>? maxTokens,
    Value<int>? contextSize,
    Value<double>? temperature,
    Value<double>? topP,
    Value<bool>? stream,
    Value<String?>? reasoningEffort,
    Value<bool>? requestReasoning,
    Value<String?>? reasoningTagStart,
    Value<String?>? reasoningTagEnd,
    Value<int>? rowid,
  }) {
    return ApiConfigsCompanion(
      configId: configId ?? this.configId,
      name: name ?? this.name,
      providerId: providerId ?? this.providerId,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      mode: mode ?? this.mode,
      maxTokens: maxTokens ?? this.maxTokens,
      contextSize: contextSize ?? this.contextSize,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      stream: stream ?? this.stream,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      requestReasoning: requestReasoning ?? this.requestReasoning,
      reasoningTagStart: reasoningTagStart ?? this.reasoningTagStart,
      reasoningTagEnd: reasoningTagEnd ?? this.reasoningTagEnd,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (configId.present) {
      map['config_id'] = Variable<String>(configId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (endpoint.present) {
      map['endpoint'] = Variable<String>(endpoint.value);
    }
    if (apiKey.present) {
      map['api_key'] = Variable<String>(apiKey.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (maxTokens.present) {
      map['max_tokens'] = Variable<int>(maxTokens.value);
    }
    if (contextSize.present) {
      map['context_size'] = Variable<int>(contextSize.value);
    }
    if (temperature.present) {
      map['temperature'] = Variable<double>(temperature.value);
    }
    if (topP.present) {
      map['top_p'] = Variable<double>(topP.value);
    }
    if (stream.present) {
      map['stream'] = Variable<bool>(stream.value);
    }
    if (reasoningEffort.present) {
      map['reasoning_effort'] = Variable<String>(reasoningEffort.value);
    }
    if (requestReasoning.present) {
      map['request_reasoning'] = Variable<bool>(requestReasoning.value);
    }
    if (reasoningTagStart.present) {
      map['reasoning_tag_start'] = Variable<String>(reasoningTagStart.value);
    }
    if (reasoningTagEnd.present) {
      map['reasoning_tag_end'] = Variable<String>(reasoningTagEnd.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ApiConfigsCompanion(')
          ..write('configId: $configId, ')
          ..write('name: $name, ')
          ..write('providerId: $providerId, ')
          ..write('endpoint: $endpoint, ')
          ..write('apiKey: $apiKey, ')
          ..write('model: $model, ')
          ..write('mode: $mode, ')
          ..write('maxTokens: $maxTokens, ')
          ..write('contextSize: $contextSize, ')
          ..write('temperature: $temperature, ')
          ..write('topP: $topP, ')
          ..write('stream: $stream, ')
          ..write('reasoningEffort: $reasoningEffort, ')
          ..write('requestReasoning: $requestReasoning, ')
          ..write('reasoningTagStart: $reasoningTagStart, ')
          ..write('reasoningTagEnd: $reasoningTagEnd, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PersonasTable extends Personas
    with TableInfo<$PersonasTable, PersonaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _personaIdMeta = const VerificationMeta(
    'personaId',
  );
  @override
  late final GeneratedColumn<String> personaId = GeneratedColumn<String>(
    'persona_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promptMeta = const VerificationMeta('prompt');
  @override
  late final GeneratedColumn<String> prompt = GeneratedColumn<String>(
    'prompt',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarPathMeta = const VerificationMeta(
    'avatarPath',
  );
  @override
  late final GeneratedColumn<String> avatarPath = GeneratedColumn<String>(
    'avatar_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [personaId, name, prompt, avatarPath];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'personas';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('persona_id')) {
      context.handle(
        _personaIdMeta,
        personaId.isAcceptableOrUnknown(data['persona_id']!, _personaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personaIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('prompt')) {
      context.handle(
        _promptMeta,
        prompt.isAcceptableOrUnknown(data['prompt']!, _promptMeta),
      );
    }
    if (data.containsKey('avatar_path')) {
      context.handle(
        _avatarPathMeta,
        avatarPath.isAcceptableOrUnknown(data['avatar_path']!, _avatarPathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {personaId};
  @override
  PersonaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonaRow(
      personaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}persona_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      prompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt'],
      ),
      avatarPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_path'],
      ),
    );
  }

  @override
  $PersonasTable createAlias(String alias) {
    return $PersonasTable(attachedDatabase, alias);
  }
}

class PersonaRow extends DataClass implements Insertable<PersonaRow> {
  final String personaId;
  final String name;
  final String? prompt;
  final String? avatarPath;
  const PersonaRow({
    required this.personaId,
    required this.name,
    this.prompt,
    this.avatarPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['persona_id'] = Variable<String>(personaId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || prompt != null) {
      map['prompt'] = Variable<String>(prompt);
    }
    if (!nullToAbsent || avatarPath != null) {
      map['avatar_path'] = Variable<String>(avatarPath);
    }
    return map;
  }

  PersonasCompanion toCompanion(bool nullToAbsent) {
    return PersonasCompanion(
      personaId: Value(personaId),
      name: Value(name),
      prompt: prompt == null && nullToAbsent
          ? const Value.absent()
          : Value(prompt),
      avatarPath: avatarPath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarPath),
    );
  }

  factory PersonaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonaRow(
      personaId: serializer.fromJson<String>(json['personaId']),
      name: serializer.fromJson<String>(json['name']),
      prompt: serializer.fromJson<String?>(json['prompt']),
      avatarPath: serializer.fromJson<String?>(json['avatarPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'personaId': serializer.toJson<String>(personaId),
      'name': serializer.toJson<String>(name),
      'prompt': serializer.toJson<String?>(prompt),
      'avatarPath': serializer.toJson<String?>(avatarPath),
    };
  }

  PersonaRow copyWith({
    String? personaId,
    String? name,
    Value<String?> prompt = const Value.absent(),
    Value<String?> avatarPath = const Value.absent(),
  }) => PersonaRow(
    personaId: personaId ?? this.personaId,
    name: name ?? this.name,
    prompt: prompt.present ? prompt.value : this.prompt,
    avatarPath: avatarPath.present ? avatarPath.value : this.avatarPath,
  );
  PersonaRow copyWithCompanion(PersonasCompanion data) {
    return PersonaRow(
      personaId: data.personaId.present ? data.personaId.value : this.personaId,
      name: data.name.present ? data.name.value : this.name,
      prompt: data.prompt.present ? data.prompt.value : this.prompt,
      avatarPath: data.avatarPath.present
          ? data.avatarPath.value
          : this.avatarPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonaRow(')
          ..write('personaId: $personaId, ')
          ..write('name: $name, ')
          ..write('prompt: $prompt, ')
          ..write('avatarPath: $avatarPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(personaId, name, prompt, avatarPath);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonaRow &&
          other.personaId == this.personaId &&
          other.name == this.name &&
          other.prompt == this.prompt &&
          other.avatarPath == this.avatarPath);
}

class PersonasCompanion extends UpdateCompanion<PersonaRow> {
  final Value<String> personaId;
  final Value<String> name;
  final Value<String?> prompt;
  final Value<String?> avatarPath;
  final Value<int> rowid;
  const PersonasCompanion({
    this.personaId = const Value.absent(),
    this.name = const Value.absent(),
    this.prompt = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PersonasCompanion.insert({
    required String personaId,
    required String name,
    this.prompt = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : personaId = Value(personaId),
       name = Value(name);
  static Insertable<PersonaRow> custom({
    Expression<String>? personaId,
    Expression<String>? name,
    Expression<String>? prompt,
    Expression<String>? avatarPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (personaId != null) 'persona_id': personaId,
      if (name != null) 'name': name,
      if (prompt != null) 'prompt': prompt,
      if (avatarPath != null) 'avatar_path': avatarPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PersonasCompanion copyWith({
    Value<String>? personaId,
    Value<String>? name,
    Value<String?>? prompt,
    Value<String?>? avatarPath,
    Value<int>? rowid,
  }) {
    return PersonasCompanion(
      personaId: personaId ?? this.personaId,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      avatarPath: avatarPath ?? this.avatarPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (personaId.present) {
      map['persona_id'] = Variable<String>(personaId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (prompt.present) {
      map['prompt'] = Variable<String>(prompt.value);
    }
    if (avatarPath.present) {
      map['avatar_path'] = Variable<String>(avatarPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonasCompanion(')
          ..write('personaId: $personaId, ')
          ..write('name: $name, ')
          ..write('prompt: $prompt, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CharactersTable characters = $CharactersTable(this);
  late final $ChatSessionsTable chatSessions = $ChatSessionsTable(this);
  late final $PresetsTable presets = $PresetsTable(this);
  late final $ApiConfigsTable apiConfigs = $ApiConfigsTable(this);
  late final $PersonasTable personas = $PersonasTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    characters,
    chatSessions,
    presets,
    apiConfigs,
    personas,
  ];
}

typedef $$CharactersTableCreateCompanionBuilder =
    CharactersCompanion Function({
      required String charId,
      required String name,
      Value<String?> avatarPath,
      Value<String?> description,
      Value<String?> personality,
      Value<String?> scenario,
      Value<String?> firstMes,
      Value<String?> mesExample,
      Value<String?> systemPrompt,
      Value<String?> postHistoryInstructions,
      Value<String?> creator,
      Value<String?> creatorNotes,
      Value<String?> color,
      Value<int> updatedAt,
      Value<String?> tagsJson,
      Value<String?> alternateGreetingsJson,
      Value<int> rowid,
    });
typedef $$CharactersTableUpdateCompanionBuilder =
    CharactersCompanion Function({
      Value<String> charId,
      Value<String> name,
      Value<String?> avatarPath,
      Value<String?> description,
      Value<String?> personality,
      Value<String?> scenario,
      Value<String?> firstMes,
      Value<String?> mesExample,
      Value<String?> systemPrompt,
      Value<String?> postHistoryInstructions,
      Value<String?> creator,
      Value<String?> creatorNotes,
      Value<String?> color,
      Value<int> updatedAt,
      Value<String?> tagsJson,
      Value<String?> alternateGreetingsJson,
      Value<int> rowid,
    });

class $$CharactersTableFilterComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get charId => $composableBuilder(
    column: $table.charId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personality => $composableBuilder(
    column: $table.personality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scenario => $composableBuilder(
    column: $table.scenario,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstMes => $composableBuilder(
    column: $table.firstMes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mesExample => $composableBuilder(
    column: $table.mesExample,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postHistoryInstructions => $composableBuilder(
    column: $table.postHistoryInstructions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creator => $composableBuilder(
    column: $table.creator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creatorNotes => $composableBuilder(
    column: $table.creatorNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alternateGreetingsJson => $composableBuilder(
    column: $table.alternateGreetingsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CharactersTableOrderingComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get charId => $composableBuilder(
    column: $table.charId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personality => $composableBuilder(
    column: $table.personality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scenario => $composableBuilder(
    column: $table.scenario,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstMes => $composableBuilder(
    column: $table.firstMes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mesExample => $composableBuilder(
    column: $table.mesExample,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postHistoryInstructions => $composableBuilder(
    column: $table.postHistoryInstructions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creator => $composableBuilder(
    column: $table.creator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creatorNotes => $composableBuilder(
    column: $table.creatorNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alternateGreetingsJson => $composableBuilder(
    column: $table.alternateGreetingsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CharactersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get charId =>
      $composableBuilder(column: $table.charId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get personality => $composableBuilder(
    column: $table.personality,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scenario =>
      $composableBuilder(column: $table.scenario, builder: (column) => column);

  GeneratedColumn<String> get firstMes =>
      $composableBuilder(column: $table.firstMes, builder: (column) => column);

  GeneratedColumn<String> get mesExample => $composableBuilder(
    column: $table.mesExample,
    builder: (column) => column,
  );

  GeneratedColumn<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get postHistoryInstructions => $composableBuilder(
    column: $table.postHistoryInstructions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get creator =>
      $composableBuilder(column: $table.creator, builder: (column) => column);

  GeneratedColumn<String> get creatorNotes => $composableBuilder(
    column: $table.creatorNotes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get alternateGreetingsJson => $composableBuilder(
    column: $table.alternateGreetingsJson,
    builder: (column) => column,
  );
}

class $$CharactersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CharactersTable,
          CharacterRow,
          $$CharactersTableFilterComposer,
          $$CharactersTableOrderingComposer,
          $$CharactersTableAnnotationComposer,
          $$CharactersTableCreateCompanionBuilder,
          $$CharactersTableUpdateCompanionBuilder,
          (
            CharacterRow,
            BaseReferences<_$AppDatabase, $CharactersTable, CharacterRow>,
          ),
          CharacterRow,
          PrefetchHooks Function()
        > {
  $$CharactersTableTableManager(_$AppDatabase db, $CharactersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharactersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharactersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CharactersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> charId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> avatarPath = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> personality = const Value.absent(),
                Value<String?> scenario = const Value.absent(),
                Value<String?> firstMes = const Value.absent(),
                Value<String?> mesExample = const Value.absent(),
                Value<String?> systemPrompt = const Value.absent(),
                Value<String?> postHistoryInstructions = const Value.absent(),
                Value<String?> creator = const Value.absent(),
                Value<String?> creatorNotes = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> tagsJson = const Value.absent(),
                Value<String?> alternateGreetingsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CharactersCompanion(
                charId: charId,
                name: name,
                avatarPath: avatarPath,
                description: description,
                personality: personality,
                scenario: scenario,
                firstMes: firstMes,
                mesExample: mesExample,
                systemPrompt: systemPrompt,
                postHistoryInstructions: postHistoryInstructions,
                creator: creator,
                creatorNotes: creatorNotes,
                color: color,
                updatedAt: updatedAt,
                tagsJson: tagsJson,
                alternateGreetingsJson: alternateGreetingsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String charId,
                required String name,
                Value<String?> avatarPath = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> personality = const Value.absent(),
                Value<String?> scenario = const Value.absent(),
                Value<String?> firstMes = const Value.absent(),
                Value<String?> mesExample = const Value.absent(),
                Value<String?> systemPrompt = const Value.absent(),
                Value<String?> postHistoryInstructions = const Value.absent(),
                Value<String?> creator = const Value.absent(),
                Value<String?> creatorNotes = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> tagsJson = const Value.absent(),
                Value<String?> alternateGreetingsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CharactersCompanion.insert(
                charId: charId,
                name: name,
                avatarPath: avatarPath,
                description: description,
                personality: personality,
                scenario: scenario,
                firstMes: firstMes,
                mesExample: mesExample,
                systemPrompt: systemPrompt,
                postHistoryInstructions: postHistoryInstructions,
                creator: creator,
                creatorNotes: creatorNotes,
                color: color,
                updatedAt: updatedAt,
                tagsJson: tagsJson,
                alternateGreetingsJson: alternateGreetingsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CharactersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CharactersTable,
      CharacterRow,
      $$CharactersTableFilterComposer,
      $$CharactersTableOrderingComposer,
      $$CharactersTableAnnotationComposer,
      $$CharactersTableCreateCompanionBuilder,
      $$CharactersTableUpdateCompanionBuilder,
      (
        CharacterRow,
        BaseReferences<_$AppDatabase, $CharactersTable, CharacterRow>,
      ),
      CharacterRow,
      PrefetchHooks Function()
    >;
typedef $$ChatSessionsTableCreateCompanionBuilder =
    ChatSessionsCompanion Function({
      required String sessionId,
      required String characterId,
      required int sessionIndex,
      required String messagesJson,
      Value<int> updatedAt,
      Value<String?> sessionVarsJson,
      Value<int> rowid,
    });
typedef $$ChatSessionsTableUpdateCompanionBuilder =
    ChatSessionsCompanion Function({
      Value<String> sessionId,
      Value<String> characterId,
      Value<int> sessionIndex,
      Value<String> messagesJson,
      Value<int> updatedAt,
      Value<String?> sessionVarsJson,
      Value<int> rowid,
    });

class $$ChatSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionIndex => $composableBuilder(
    column: $table.sessionIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messagesJson => $composableBuilder(
    column: $table.messagesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionVarsJson => $composableBuilder(
    column: $table.sessionVarsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionIndex => $composableBuilder(
    column: $table.sessionIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messagesJson => $composableBuilder(
    column: $table.messagesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionVarsJson => $composableBuilder(
    column: $table.sessionVarsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sessionIndex => $composableBuilder(
    column: $table.sessionIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messagesJson => $composableBuilder(
    column: $table.messagesJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get sessionVarsJson => $composableBuilder(
    column: $table.sessionVarsJson,
    builder: (column) => column,
  );
}

class $$ChatSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatSessionsTable,
          ChatSessionRow,
          $$ChatSessionsTableFilterComposer,
          $$ChatSessionsTableOrderingComposer,
          $$ChatSessionsTableAnnotationComposer,
          $$ChatSessionsTableCreateCompanionBuilder,
          $$ChatSessionsTableUpdateCompanionBuilder,
          (
            ChatSessionRow,
            BaseReferences<_$AppDatabase, $ChatSessionsTable, ChatSessionRow>,
          ),
          ChatSessionRow,
          PrefetchHooks Function()
        > {
  $$ChatSessionsTableTableManager(_$AppDatabase db, $ChatSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> characterId = const Value.absent(),
                Value<int> sessionIndex = const Value.absent(),
                Value<String> messagesJson = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> sessionVarsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatSessionsCompanion(
                sessionId: sessionId,
                characterId: characterId,
                sessionIndex: sessionIndex,
                messagesJson: messagesJson,
                updatedAt: updatedAt,
                sessionVarsJson: sessionVarsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String characterId,
                required int sessionIndex,
                required String messagesJson,
                Value<int> updatedAt = const Value.absent(),
                Value<String?> sessionVarsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatSessionsCompanion.insert(
                sessionId: sessionId,
                characterId: characterId,
                sessionIndex: sessionIndex,
                messagesJson: messagesJson,
                updatedAt: updatedAt,
                sessionVarsJson: sessionVarsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatSessionsTable,
      ChatSessionRow,
      $$ChatSessionsTableFilterComposer,
      $$ChatSessionsTableOrderingComposer,
      $$ChatSessionsTableAnnotationComposer,
      $$ChatSessionsTableCreateCompanionBuilder,
      $$ChatSessionsTableUpdateCompanionBuilder,
      (
        ChatSessionRow,
        BaseReferences<_$AppDatabase, $ChatSessionsTable, ChatSessionRow>,
      ),
      ChatSessionRow,
      PrefetchHooks Function()
    >;
typedef $$PresetsTableCreateCompanionBuilder =
    PresetsCompanion Function({
      required String presetId,
      required String name,
      required String dataJson,
      Value<int> rowid,
    });
typedef $$PresetsTableUpdateCompanionBuilder =
    PresetsCompanion Function({
      Value<String> presetId,
      Value<String> name,
      Value<String> dataJson,
      Value<int> rowid,
    });

class $$PresetsTableFilterComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PresetsTableOrderingComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PresetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get presetId =>
      $composableBuilder(column: $table.presetId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);
}

class $$PresetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PresetsTable,
          PresetRow,
          $$PresetsTableFilterComposer,
          $$PresetsTableOrderingComposer,
          $$PresetsTableAnnotationComposer,
          $$PresetsTableCreateCompanionBuilder,
          $$PresetsTableUpdateCompanionBuilder,
          (PresetRow, BaseReferences<_$AppDatabase, $PresetsTable, PresetRow>),
          PresetRow,
          PrefetchHooks Function()
        > {
  $$PresetsTableTableManager(_$AppDatabase db, $PresetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PresetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PresetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PresetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> presetId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PresetsCompanion(
                presetId: presetId,
                name: name,
                dataJson: dataJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String presetId,
                required String name,
                required String dataJson,
                Value<int> rowid = const Value.absent(),
              }) => PresetsCompanion.insert(
                presetId: presetId,
                name: name,
                dataJson: dataJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PresetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PresetsTable,
      PresetRow,
      $$PresetsTableFilterComposer,
      $$PresetsTableOrderingComposer,
      $$PresetsTableAnnotationComposer,
      $$PresetsTableCreateCompanionBuilder,
      $$PresetsTableUpdateCompanionBuilder,
      (PresetRow, BaseReferences<_$AppDatabase, $PresetsTable, PresetRow>),
      PresetRow,
      PrefetchHooks Function()
    >;
typedef $$ApiConfigsTableCreateCompanionBuilder =
    ApiConfigsCompanion Function({
      required String configId,
      required String name,
      Value<String> providerId,
      Value<String?> endpoint,
      Value<String?> apiKey,
      Value<String?> model,
      Value<String> mode,
      Value<int> maxTokens,
      Value<int> contextSize,
      Value<double> temperature,
      Value<double> topP,
      Value<bool> stream,
      Value<String?> reasoningEffort,
      Value<bool> requestReasoning,
      Value<String?> reasoningTagStart,
      Value<String?> reasoningTagEnd,
      Value<int> rowid,
    });
typedef $$ApiConfigsTableUpdateCompanionBuilder =
    ApiConfigsCompanion Function({
      Value<String> configId,
      Value<String> name,
      Value<String> providerId,
      Value<String?> endpoint,
      Value<String?> apiKey,
      Value<String?> model,
      Value<String> mode,
      Value<int> maxTokens,
      Value<int> contextSize,
      Value<double> temperature,
      Value<double> topP,
      Value<bool> stream,
      Value<String?> reasoningEffort,
      Value<bool> requestReasoning,
      Value<String?> reasoningTagStart,
      Value<String?> reasoningTagEnd,
      Value<int> rowid,
    });

class $$ApiConfigsTableFilterComposer
    extends Composer<_$AppDatabase, $ApiConfigsTable> {
  $$ApiConfigsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get configId => $composableBuilder(
    column: $table.configId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get apiKey => $composableBuilder(
    column: $table.apiKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxTokens => $composableBuilder(
    column: $table.maxTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contextSize => $composableBuilder(
    column: $table.contextSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get topP => $composableBuilder(
    column: $table.topP,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stream => $composableBuilder(
    column: $table.stream,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasoningEffort => $composableBuilder(
    column: $table.reasoningEffort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requestReasoning => $composableBuilder(
    column: $table.requestReasoning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasoningTagStart => $composableBuilder(
    column: $table.reasoningTagStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasoningTagEnd => $composableBuilder(
    column: $table.reasoningTagEnd,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ApiConfigsTableOrderingComposer
    extends Composer<_$AppDatabase, $ApiConfigsTable> {
  $$ApiConfigsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get configId => $composableBuilder(
    column: $table.configId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get apiKey => $composableBuilder(
    column: $table.apiKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxTokens => $composableBuilder(
    column: $table.maxTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contextSize => $composableBuilder(
    column: $table.contextSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get topP => $composableBuilder(
    column: $table.topP,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stream => $composableBuilder(
    column: $table.stream,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasoningEffort => $composableBuilder(
    column: $table.reasoningEffort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requestReasoning => $composableBuilder(
    column: $table.requestReasoning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasoningTagStart => $composableBuilder(
    column: $table.reasoningTagStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasoningTagEnd => $composableBuilder(
    column: $table.reasoningTagEnd,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ApiConfigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ApiConfigsTable> {
  $$ApiConfigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get configId =>
      $composableBuilder(column: $table.configId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get endpoint =>
      $composableBuilder(column: $table.endpoint, builder: (column) => column);

  GeneratedColumn<String> get apiKey =>
      $composableBuilder(column: $table.apiKey, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get maxTokens =>
      $composableBuilder(column: $table.maxTokens, builder: (column) => column);

  GeneratedColumn<int> get contextSize => $composableBuilder(
    column: $table.contextSize,
    builder: (column) => column,
  );

  GeneratedColumn<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => column,
  );

  GeneratedColumn<double> get topP =>
      $composableBuilder(column: $table.topP, builder: (column) => column);

  GeneratedColumn<bool> get stream =>
      $composableBuilder(column: $table.stream, builder: (column) => column);

  GeneratedColumn<String> get reasoningEffort => $composableBuilder(
    column: $table.reasoningEffort,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requestReasoning => $composableBuilder(
    column: $table.requestReasoning,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reasoningTagStart => $composableBuilder(
    column: $table.reasoningTagStart,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reasoningTagEnd => $composableBuilder(
    column: $table.reasoningTagEnd,
    builder: (column) => column,
  );
}

class $$ApiConfigsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ApiConfigsTable,
          ApiConfigRow,
          $$ApiConfigsTableFilterComposer,
          $$ApiConfigsTableOrderingComposer,
          $$ApiConfigsTableAnnotationComposer,
          $$ApiConfigsTableCreateCompanionBuilder,
          $$ApiConfigsTableUpdateCompanionBuilder,
          (
            ApiConfigRow,
            BaseReferences<_$AppDatabase, $ApiConfigsTable, ApiConfigRow>,
          ),
          ApiConfigRow,
          PrefetchHooks Function()
        > {
  $$ApiConfigsTableTableManager(_$AppDatabase db, $ApiConfigsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ApiConfigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ApiConfigsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ApiConfigsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> configId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> providerId = const Value.absent(),
                Value<String?> endpoint = const Value.absent(),
                Value<String?> apiKey = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> maxTokens = const Value.absent(),
                Value<int> contextSize = const Value.absent(),
                Value<double> temperature = const Value.absent(),
                Value<double> topP = const Value.absent(),
                Value<bool> stream = const Value.absent(),
                Value<String?> reasoningEffort = const Value.absent(),
                Value<bool> requestReasoning = const Value.absent(),
                Value<String?> reasoningTagStart = const Value.absent(),
                Value<String?> reasoningTagEnd = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ApiConfigsCompanion(
                configId: configId,
                name: name,
                providerId: providerId,
                endpoint: endpoint,
                apiKey: apiKey,
                model: model,
                mode: mode,
                maxTokens: maxTokens,
                contextSize: contextSize,
                temperature: temperature,
                topP: topP,
                stream: stream,
                reasoningEffort: reasoningEffort,
                requestReasoning: requestReasoning,
                reasoningTagStart: reasoningTagStart,
                reasoningTagEnd: reasoningTagEnd,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String configId,
                required String name,
                Value<String> providerId = const Value.absent(),
                Value<String?> endpoint = const Value.absent(),
                Value<String?> apiKey = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> maxTokens = const Value.absent(),
                Value<int> contextSize = const Value.absent(),
                Value<double> temperature = const Value.absent(),
                Value<double> topP = const Value.absent(),
                Value<bool> stream = const Value.absent(),
                Value<String?> reasoningEffort = const Value.absent(),
                Value<bool> requestReasoning = const Value.absent(),
                Value<String?> reasoningTagStart = const Value.absent(),
                Value<String?> reasoningTagEnd = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ApiConfigsCompanion.insert(
                configId: configId,
                name: name,
                providerId: providerId,
                endpoint: endpoint,
                apiKey: apiKey,
                model: model,
                mode: mode,
                maxTokens: maxTokens,
                contextSize: contextSize,
                temperature: temperature,
                topP: topP,
                stream: stream,
                reasoningEffort: reasoningEffort,
                requestReasoning: requestReasoning,
                reasoningTagStart: reasoningTagStart,
                reasoningTagEnd: reasoningTagEnd,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ApiConfigsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ApiConfigsTable,
      ApiConfigRow,
      $$ApiConfigsTableFilterComposer,
      $$ApiConfigsTableOrderingComposer,
      $$ApiConfigsTableAnnotationComposer,
      $$ApiConfigsTableCreateCompanionBuilder,
      $$ApiConfigsTableUpdateCompanionBuilder,
      (
        ApiConfigRow,
        BaseReferences<_$AppDatabase, $ApiConfigsTable, ApiConfigRow>,
      ),
      ApiConfigRow,
      PrefetchHooks Function()
    >;
typedef $$PersonasTableCreateCompanionBuilder =
    PersonasCompanion Function({
      required String personaId,
      required String name,
      Value<String?> prompt,
      Value<String?> avatarPath,
      Value<int> rowid,
    });
typedef $$PersonasTableUpdateCompanionBuilder =
    PersonasCompanion Function({
      Value<String> personaId,
      Value<String> name,
      Value<String?> prompt,
      Value<String?> avatarPath,
      Value<int> rowid,
    });

class $$PersonasTableFilterComposer
    extends Composer<_$AppDatabase, $PersonasTable> {
  $$PersonasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get personaId => $composableBuilder(
    column: $table.personaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PersonasTableOrderingComposer
    extends Composer<_$AppDatabase, $PersonasTable> {
  $$PersonasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get personaId => $composableBuilder(
    column: $table.personaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PersonasTableAnnotationComposer
    extends Composer<_$AppDatabase, $PersonasTable> {
  $$PersonasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get personaId =>
      $composableBuilder(column: $table.personaId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get prompt =>
      $composableBuilder(column: $table.prompt, builder: (column) => column);

  GeneratedColumn<String> get avatarPath => $composableBuilder(
    column: $table.avatarPath,
    builder: (column) => column,
  );
}

class $$PersonasTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PersonasTable,
          PersonaRow,
          $$PersonasTableFilterComposer,
          $$PersonasTableOrderingComposer,
          $$PersonasTableAnnotationComposer,
          $$PersonasTableCreateCompanionBuilder,
          $$PersonasTableUpdateCompanionBuilder,
          (
            PersonaRow,
            BaseReferences<_$AppDatabase, $PersonasTable, PersonaRow>,
          ),
          PersonaRow,
          PrefetchHooks Function()
        > {
  $$PersonasTableTableManager(_$AppDatabase db, $PersonasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> personaId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> prompt = const Value.absent(),
                Value<String?> avatarPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PersonasCompanion(
                personaId: personaId,
                name: name,
                prompt: prompt,
                avatarPath: avatarPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String personaId,
                required String name,
                Value<String?> prompt = const Value.absent(),
                Value<String?> avatarPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PersonasCompanion.insert(
                personaId: personaId,
                name: name,
                prompt: prompt,
                avatarPath: avatarPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PersonasTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PersonasTable,
      PersonaRow,
      $$PersonasTableFilterComposer,
      $$PersonasTableOrderingComposer,
      $$PersonasTableAnnotationComposer,
      $$PersonasTableCreateCompanionBuilder,
      $$PersonasTableUpdateCompanionBuilder,
      (PersonaRow, BaseReferences<_$AppDatabase, $PersonasTable, PersonaRow>),
      PersonaRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CharactersTableTableManager get characters =>
      $$CharactersTableTableManager(_db, _db.characters);
  $$ChatSessionsTableTableManager get chatSessions =>
      $$ChatSessionsTableTableManager(_db, _db.chatSessions);
  $$PresetsTableTableManager get presets =>
      $$PresetsTableTableManager(_db, _db.presets);
  $$ApiConfigsTableTableManager get apiConfigs =>
      $$ApiConfigsTableTableManager(_db, _db.apiConfigs);
  $$PersonasTableTableManager get personas =>
      $$PersonasTableTableManager(_db, _db.personas);
}
