import 'package:flutter/material.dart';

import '../../../core/models/api_config.dart';
import '../../../core/models/character.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/lorebook.dart';
import '../../../core/models/persona.dart';
import '../../../core/models/preset.dart';

class MagicDrawerItemDef {
  final String id;
  final String label;
  final IconData icon;

  const MagicDrawerItemDef({
    required this.id,
    required this.label,
    required this.icon,
  });
}

class MagicDrawerCardItem {
  final MagicDrawerItemDef def;
  final String? status;
  final bool isAddButton;

  const MagicDrawerCardItem({
    required this.def,
    this.status,
    this.isAddButton = false,
  });
}

class MagicDrawerStats {
  final Character? character;
  final Preset? activePreset;
  final Persona? activePersona;
  final ApiConfig? apiConfig;
  final ChatSession? session;
  final int sessionCount;
  final int messageCount;
  final int lorebookEntryCount;
  final int memoryEntryCount;
  final int regexCount;
  final int summaryChars;
  final int promptTokens;
  final int contextSize;
  final int characterTokens;
  final int presetTokens;
  final int personaTokens;
  final int summaryTokens;
  final bool imageGenEnabled;
  final List<Lorebook> lorebooks;
  final String? summaryContent;
  final String? memoryContent;
  final String memoryInjectionTarget;
  final Map<String, dynamic> memoryCoverage;

  const MagicDrawerStats({
    this.character,
    this.activePreset,
    this.activePersona,
    this.apiConfig,
    this.session,
    this.sessionCount = 0,
    this.messageCount = 0,
    this.lorebookEntryCount = 0,
    this.memoryEntryCount = 0,
    this.regexCount = 0,
    this.summaryChars = 0,
    this.promptTokens = 0,
    this.contextSize = 0,
    this.characterTokens = 0,
    this.presetTokens = 0,
    this.personaTokens = 0,
    this.summaryTokens = 0,
    this.imageGenEnabled = false,
    this.lorebooks = const [],
    this.summaryContent,
    this.memoryContent,
    this.memoryInjectionTarget = 'summary_block',
    this.memoryCoverage = const {},
  });

  MagicDrawerStats copyWith({
    int? promptTokens,
    int? contextSize,
    int? characterTokens,
    int? presetTokens,
    int? personaTokens,
    int? summaryTokens,
  }) {
    return MagicDrawerStats(
      character: character,
      activePreset: activePreset,
      activePersona: activePersona,
      apiConfig: apiConfig,
      session: session,
      sessionCount: sessionCount,
      messageCount: messageCount,
      lorebookEntryCount: lorebookEntryCount,
      memoryEntryCount: memoryEntryCount,
      regexCount: regexCount,
      summaryChars: summaryChars,
      promptTokens: promptTokens ?? this.promptTokens,
      contextSize: contextSize ?? this.contextSize,
      characterTokens: characterTokens ?? this.characterTokens,
      presetTokens: presetTokens ?? this.presetTokens,
      personaTokens: personaTokens ?? this.personaTokens,
      summaryTokens: summaryTokens ?? this.summaryTokens,
      imageGenEnabled: imageGenEnabled,
      lorebooks: lorebooks,
      summaryContent: summaryContent,
      memoryContent: memoryContent,
      memoryInjectionTarget: memoryInjectionTarget,
      memoryCoverage: memoryCoverage,
    );
  }
}
