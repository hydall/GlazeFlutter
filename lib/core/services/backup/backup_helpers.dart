import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../db/app_db.dart';
import '../../models/lorebook.dart';
import '../../models/preset.dart';
import '../../utils/id_generator.dart';
import '../image_storage_service.dart';
import '../preset_defaults.dart';

mixin BackupHelpers {
  AppDatabase get db;
  ImageStorageService get imageStorage;

  int? toInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is double) return value.toInt();
    return null;
  }

  double? toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  List<int> toIntList(dynamic value) {
    if (value is List) {
      return value.map((e) {
        if (e is int) return e;
        if (e is num) return e.toInt();
        return int.tryParse(e.toString()) ?? 0;
      }).toList();
    }
    return [1, 2];
  }

  List<String> toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) {
      return value
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  String joinTrimStrings(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).join('\n');
    return '';
  }

  Uint8List? dataUrlToBytes(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    if (commaIndex == -1) return null;
    final base64Str = dataUrl.substring(commaIndex + 1);
    try {
      return Uint8List.fromList(
          Uri.parse('data:;base64,$base64Str').data!.contentAsBytes());
    } catch (_) {
      return null;
    }
  }

  String dataUrlMime(String dataUrl) {
    final end = dataUrl.indexOf(';');
    if (end == -1) return '';
    return dataUrl.substring(5, end);
  }

  String extFromEntry(Map<String, dynamic>? entry) {
    final path = entry?['imagePath'] as String?;
    if (path != null) {
      final ext = p.extension(path).replaceFirst('.', '');
      if (ext.isNotEmpty) return ext;
    }
    return 'png';
  }

  String? extractExtensionsJson(Map<String, dynamic> char) {
    final extensions = char['extensions'] ?? char['data']?['extensions'];
    if (extensions is Map<String, dynamic> && extensions.isNotEmpty) {
      extensions.remove('gallery');
      if (extensions.isNotEmpty) return jsonEncode(extensions);
    }
    return null;
  }

  String? encodeAuthorsNote(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      if (raw.isEmpty) return null;
      return jsonEncode({
        'content': raw,
        'role': 'system',
        'insertionMode': 'relative',
        'depth': 0,
        'enabled': true,
      });
    }
    if (raw is Map) {
      final content = raw['content'] is String ? raw['content'] as String : '';
      if (content.isEmpty) return null;
      return jsonEncode({
        'content': content,
        'role': raw['role'] is String ? raw['role'] as String : 'system',
        'insertionMode': (raw['insertion_mode'] is String
                    ? raw['insertion_mode'] as String
                    : null) ??
            (raw['insertionMode'] is String
                    ? raw['insertionMode'] as String
                    : null) ??
            'relative',
        'depth': toInt(raw['depth']) ?? 0,
        'enabled': raw['enabled'] is bool ? raw['enabled'] as bool : true,
      });
    }
    return null;
  }

  String mapLorebookPosition(dynamic pos) {
    if (pos is String) return pos;
    if (pos is int) {
      return switch (pos) {
        0 => 'worldInfoBefore',
        1 => 'worldInfoAfter',
        2 => 'worldInfoBefore',
        3 => 'worldInfoAfter',
        4 => 'at_depth',
        _ => 'worldInfoBefore',
      };
    }
    return 'worldInfoBefore';
  }

  Map<String, dynamic> mapJsLorebookEntry(Map<String, dynamic> e) {
    final keys = toStringList(e['keys'] ?? e['key']);
    final secondaryKeys = toStringList(
        e['secondaryKeys'] ?? e['secondary_keys'] ?? e['keysecondary']);

    var enabled = e['enabled'] as bool?;
    if (enabled == null) {
      final disabled = e['disable'] as bool? ?? false;
      enabled = !disabled;
    }

    final position = mapLorebookPosition(e['position']);

    final charFilter = e['characterFilter'] ?? e['character_filter'];
    LorebookCharacterFilter? filter;
    if (charFilter is Map) {
      final names = charFilter['names'];
      filter = LorebookCharacterFilter(
        names: names is List ? names.map((n) => n.toString()).toList() : [],
        isExclude: charFilter['isExclude'] as bool? ?? false,
      );
    } else if (charFilter is List) {
      filter = LorebookCharacterFilter(
        names: charFilter.map((n) => n.toString()).toList(),
      );
    }

    return {
      'id': (e['uid'] ?? e['id'] ?? DateTime.now().millisecondsSinceEpoch)
          .toString(),
      'comment': e['comment'] ?? e['name'] ?? '',
      'enabled': enabled,
      'constant': e['constant'] as bool? ?? false,
      'keys': keys,
      'secondaryKeys': secondaryKeys,
      'selectiveLogic': e['selectiveLogic'] ?? e['selective_logic'] ?? 5,
      'content': e['content'] ?? '',
      'position': position,
      'order': toInt(e['order'] ?? e['insertion_order']) ?? 100,
      'scanDepth': toInt(e['scanDepth'] ?? e['scan_depth']),
      'caseSensitive': e['caseSensitive'] ?? e['case_sensitive'] ?? false,
      'matchWholeWords':
          e['matchWholeWords'] ?? e['match_whole_words'] ?? false,
      'probability': toDouble(e['probability']) ?? 100.0,
      'preventRecursion':
          e['preventRecursion'] ?? e['prevent_recursion'] ?? false,
      'sticky': toInt(e['sticky']) ?? 0,
      'cooldown': toInt(e['cooldown']) ?? 0,
      'delay': toInt(e['delay']) ?? 0,
      'group': e['group'] ?? '',
      'groupProminence':
          toInt(e['groupProminence'] ?? e['group_prominence']) ?? 100,
      'characterFilter': filter?.toJson(),
      'ignoreBudget': e['ignoreBudget'] ?? false,
      'vectorSearch': e['vectorSearch'] ?? e['vector_search'] ?? false,
      'useKeywordSearch':
          e['useKeywordSearch'] ?? e['use_keyword_search'] ?? true,
      'delayUntilRecursion':
          e['delayUntilRecursion'] ?? e['delay_until_recursion'] ?? false,
      'useGroupScoring':
          e['useGroupScoring'] ?? e['use_group_scoring'] ?? false,
    };
  }

  void extractPresetsFromRaw(
      dynamic raw, List<Map<String, dynamic>> presets) {
    if (raw is List) {
      for (final p in raw) {
        if (p is Map<String, dynamic>) presets.add(p);
      }
    } else if (raw is Map<String, dynamic>) {
      if (raw.containsKey('id') && raw.containsKey('endpoint')) {
        presets.add(raw);
      } else {
        for (final p in raw.values) {
          if (p is Map<String, dynamic>) presets.add(p);
        }
      }
    } else if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        extractPresetsFromRaw(decoded, presets);
      } catch (_) {}
    }
  }

  Preset mapJsPreset(Map<String, dynamic> json) {
    final blocks = <PresetBlock>[];
    final rawBlocks = json['blocks'] ?? json['prompt_order'];
    if (rawBlocks is List) {
      for (final b in rawBlocks) {
        if (b is! Map<String, dynamic>) continue;
        blocks.add(PresetBlock(
          id: b['id'] as String? ?? generateBackupId(),
          name: b['name'] as String? ?? '',
          role: b['role'] as String? ?? 'system',
          content: b['content'] as String? ?? '',
          enabled: b['enabled'] as bool? ?? true,
          isStatic: b['isStatic'] as bool? ?? false,
          insertionMode: (b['insertion_mode'] as String?) ??
              (b['insertionMode'] as String?) ??
              'relative',
          depth: toInt(b['depth']),
          prefix: b['prefix'] as String?,
          isStashed: b['isStashed'] as bool? ?? false,
        ));
      }
    }

    final regexes = <PresetRegex>[];
    final rawRegexes = json['regexes'] ?? json['regex_scripts'];
    if (rawRegexes is List) {
      for (final r in rawRegexes) {
        if (r is! Map<String, dynamic>) continue;
        regexes.add(PresetRegex(
          id: r['id'] as String? ?? generateBackupId(),
          name: r['name'] as String? ?? r['scriptName'] as String? ?? '',
          regex: r['regex'] as String? ?? r['findRegex'] as String? ?? '',
          replacement: r['replacement'] as String? ??
              r['replaceString'] as String? ??
              '',
          trimOut:
              r['trimOut'] as String? ?? joinTrimStrings(r['trimStrings']),
          placement: toIntList(r['placement']),
          ephemerality: toIntList(r['ephemerality']),
          disabled: r['disabled'] as bool? ?? false,
          macroRules:
              (r['macroRules'] ?? r['substituteRegex'] ?? 0).toString(),
          minDepth: toInt(r['minDepth']),
          maxDepth: toInt(r['maxDepth']),
        ));
      }
    }

    return finalizeImportedPreset(Preset(
      id: json['id'] as String? ?? generateBackupId(),
      name: json['name'] as String? ?? 'Imported',
      author: json['author'] as String?,
      blocks: blocks,
      regexes: regexes,
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? false,
      reasoningStart: json['reasoningStart'] as String?,
      reasoningEnd: json['reasoningEnd'] as String?,
      guidedGenerationPrompt: json['guidedGenerationPrompt'] as String?,
      guidedImpersonationPrompt: json['guidedImpersonationPrompt'] as String?,
      summaryPrompt: json['summaryPrompt'] as String?,
      mergePrompts: json['mergePrompts'] as bool? ?? false,
      mergeRole: json['mergeRole'] as String? ?? 'system',
      createdAt: toInt(json['createdAt']) ?? 0,
    ));
  }

  String extractReasoningEffort(Map<String, dynamic> preset) {
    final tags = preset['reasoningTags'] as Map<String, dynamic>?;
    if (tags != null) {
      final effort = tags['effort'] as String?;
      if (effort != null) return effort;
    }
    return 'medium';
  }

  String generateBackupId() {
    return generateId() + Random().nextInt(9999).toRadixString(36);
  }
}
