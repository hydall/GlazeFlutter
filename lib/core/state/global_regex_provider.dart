import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/preset.dart';

const _globalRegexKey = 'gz_global_regex_scripts';

class GlobalRegexNotifier extends AsyncNotifier<List<PresetRegex>> {
  @override
  Future<List<PresetRegex>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_globalRegexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => PresetRegex.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist(List<PresetRegex> scripts) async {
    final prefs = await SharedPreferences.getInstance();
    final json = scripts.map((e) => e.toJson()).toList();
    await prefs.setString(_globalRegexKey, jsonEncode(json));
  }

  Future<void> addRegex(PresetRegex regex) async {
    final current = state.value ?? [];
    final updated = [...current, regex];
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> updateRegex(PresetRegex regex) async {
    final current = state.value ?? [];
    final updated = current.map((r) => r.id == regex.id ? regex : r).toList();
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> removeRegex(String id) async {
    final current = state.value ?? [];
    final updated = current.where((r) => r.id != id).toList();
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> importFromJsBackup(List<dynamic> rawList) async {
    final existing = state.value ?? [];
    final existingIds = existing.map((e) => e.id).toSet();
    final imported = <PresetRegex>[];
    for (final raw in rawList) {
      if (raw is! Map<String, dynamic>) continue;
      try {
        final regex = PresetRegex.fromJson(_normalizeJsRegex(raw));
        if (!existingIds.contains(regex.id)) {
          imported.add(regex);
          existingIds.add(regex.id);
        }
      } catch (_) {}
    }
    if (imported.isNotEmpty) {
      final updated = [...existing, ...imported];
      state = AsyncData(updated);
      await _persist(updated);
    }
  }

  Map<String, dynamic> _normalizeJsRegex(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    if (!map.containsKey('id')) map['id'] = '${DateTime.now().millisecondsSinceEpoch}';
    if (!map.containsKey('name')) map['name'] = map['scriptName'] ?? 'Imported';
    if (!map.containsKey('regex')) map['regex'] = map['findRegex'] ?? '';
    if (!map.containsKey('replacement')) map['replacement'] = map['replaceString'] ?? '';
    if (!map.containsKey('placement')) {
      final p = raw['placement'];
      if (p is List) {
        map['placement'] = p.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 1).toList();
      } else {
        map['placement'] = [1, 2];
      }
    }
    if (!map.containsKey('ephemerality')) {
      final e = raw['runOnEdit'];
      map['ephemerality'] = e == true ? [1, 2] : [2];
    }
    return map;
  }
}

final globalRegexProvider =
    AsyncNotifierProvider<GlobalRegexNotifier, List<PresetRegex>>(
  GlobalRegexNotifier.new,
);
