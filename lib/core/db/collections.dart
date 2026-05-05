import 'package:isar/isar.dart';

part 'collections.g.dart';

@collection
class CharacterCollection {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String charId;
  late String name;
  String? avatarPath;
  String? description;
  String? personality;
  String? scenario;
  String? firstMes;
  String? mesExample;
  String? systemPrompt;
  String? postHistoryInstructions;
  String? creator;
  String? creatorNotes;
  String? color;
  int updatedAt = 0;
  String? tagsJson;
  String? alternateGreetingsJson;
}

@collection
class ChatSessionCollection {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String sessionId;
  late String characterId;
  late int sessionIndex;
  late String messagesJson;
  int updatedAt = 0;
}

@collection
class PresetCollection {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String presetId;
  late String name;
  late String dataJson;
}

@collection
class ApiConfigCollection {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String configId;
  late String name;
  late String providerId;
  String? endpoint;
  String? apiKey;
  String? model;
  int maxTokens = 8000;
  int contextSize = 32000;
  double temperature = 0.7;
  double topP = 0.9;
  bool stream = true;
  String? reasoningEffort;
  bool requestReasoning = false;
  String? reasoningTagStart;
  String? reasoningTagEnd;
}

@collection
class PersonaCollection {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String personaId;
  late String name;
  String? prompt;
  String? avatarPath;
}
