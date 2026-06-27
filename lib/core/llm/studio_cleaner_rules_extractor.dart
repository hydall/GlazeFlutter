import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/api_config.dart';
import '../models/preset.dart';
import 'json_repair.dart';
import 'studio_build_llm_client.dart';

/// Signature of the LLM call the extractor delegates to. Matches
/// [StudioBuildLlmClient.call] so a real client can be supplied in production
/// and a closure in tests (no `Ref` required). See [RouterLlmCall] for the
/// same pattern in [StudioBlockRouter].
typedef CleanerRulesLlmCall =
    Future<String?> Function(
      String prompt, {
      ApiConfig? apiConfig,
      CancelToken? cancelToken,
    });

/// Build-time result of the second LLM call in `StudioMenuController.buildStudio`:
/// prose-guardian style rules extracted from the preset for the POST-cleaner.
/// Written to the three `postCleaner*` string fields of `PipelineSettings`.
///
/// A pure immutable record. Constructed from an LLM JSON response (see
/// [StudioCleanerRulesExtractor.extract]) or directly in tests.
@immutable
class StudioCleanerRules {
  final String bannedWords;
  final String avoidInstructions;
  final String styleInstructions;

  const StudioCleanerRules({
    required this.bannedWords,
    required this.avoidInstructions,
    required this.styleInstructions,
  });

  /// True when the LLM found no enforceable rules in the preset. The caller
  /// surfaces a toast and leaves `PipelineSettings` untouched.
  bool get isEmpty =>
      bannedWords.isEmpty && avoidInstructions.isEmpty && styleInstructions.isEmpty;

  @override
  String toString() =>
      'StudioCleanerRules(banned: "$bannedWords", avoid: "$avoidInstructions", style: "$styleInstructions")';
}

/// Exception raised when the LLM explicitly reports that the preset contains
/// no enforceable cleaner rules (distinct from a transport/parse failure).
class NoCleanerRulesFoundException implements Exception {
  final String message;
  NoCleanerRulesFoundException([this.message = 'No cleaner rules found in preset']);
  @override
  String toString() => message;
}

/// Build-time specialist extracted from the Studio decomposition flow (plan
/// §7.4). One LLM call asks the build model to read the enabled preset blocks
/// and return a JSON object with three string fields (`bannedWords`,
/// `avoidInstructions`, `styleInstructions`) that flow into the POST-cleaner's
/// `PipelineSettings` overrides.
///
/// The extractor owns prompt construction + JSON parsing; it does NOT touch
/// `Ref` or `PipelineSettings` — the caller decides what to do with the result.
/// `StudioBuildLlmClient` is injected so the call reuses the same transport +
/// config resolution as the pre-tracker decomposition LLM call.
class StudioCleanerRulesExtractor {
  final CleanerRulesLlmCall _callLlm;

  /// Construct with a [StudioBuildLlmClient] in production; tests pass a
  /// closure matching [CleanerRulesLlmCall].
  StudioCleanerRulesExtractor(StudioBuildLlmClient llm) : _callLlm = llm.call;

  /// Test-only constructor accepting a raw [CleanerRulesLlmCall] closure.
  @visibleForTesting
  StudioCleanerRulesExtractor.forTest(this._callLlm);

  /// Extract cleaner rules from [preset]'s enabled blocks via one LLM call.
  ///
  /// Throws [NoCleanerRulesFoundException] when the LLM reports that the preset
  /// has no enforceable rules. Throws [Exception] on transport/parse failure
  /// (the caller surfaces a toast and keeps `PipelineSettings` unchanged).
  Future<StudioCleanerRules> extract({
    required Preset preset,
    ApiConfig? apiConfig,
    CancelToken? cancelToken,
  }) async {
    final blocks = preset.blocks.where((b) => b.enabled).toList();
    if (blocks.isEmpty) {
      throw NoCleanerRulesFoundException('Preset has no enabled blocks');
    }
    final prompt = _buildPrompt(blocks);
    final raw = await _callLlm(prompt, apiConfig: apiConfig, cancelToken: cancelToken);
    if (raw == null || raw.trim().isEmpty) {
      throw Exception('Cleaner rules extraction returned empty response');
    }
    return _parseResponse(raw);
  }

  String _buildPrompt(List<PresetBlock> blocks) {
    final blocksText = blocks.map((b) {
      final name = b.name.isNotEmpty ? b.name : b.id;
      return '### ${'Block: $name'}\n${b.content.trim()}';
    }).join('\n\n');

    return '''You are a build-time Studio compiler. You are not roleplaying and you are not writing the next chat reply.

Read the roleplay preset blocks below and extract prose-guardian rules that a POST-generation cleaner LLM should enforce. Output ONLY a JSON object with three string fields and nothing else:

{
  "bannedWords": "comma-separated list of words/phrases the cleaner must remove or never emit; empty string if none",
  "avoidInstructions": "imperative instructions for what the cleaner should avoid or minimize (e.g. cliches, repetition patterns, tell-not-show); empty string if none",
  "styleInstructions": "imperative instructions for preferred style (e.g. sensory budget, POV, paragraph budget, tone); empty string if none"
}

Rules:
- Read anti-loop / anti-echo / anti-cliche / anti-slop / banlist / forbidden-words blocks → bannedWords.
- Read prose-quality / no-tells / repetition-repair blocks → avoidInstructions.
- Read narrative / style / pacing / length / tone / genre / sensory blocks → styleInstructions.
- If a rule fits more than one field, place it in the most specific one.
- Compress duplicates. Output the rules as concise imperatives, not verbatim block text.
- If the preset contains NO enforceable cleaner rules at all, output exactly: {"noRules": true}
- Do not invent rules the user did not write. Do not add commentary, markdown fences, or explanations.

Enabled preset blocks:
$blocksText''';
  }

  StudioCleanerRules _parseResponse(String raw) {
    final jsonStr = extractJsonObject(raw);
    if (jsonStr == null) {
      throw Exception('Cleaner rules extraction returned non-JSON response');
    }
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(repairJson(jsonStr)) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Cleaner rules extraction returned malformed JSON: $e');
    }
    if (parsed['noRules'] == true) {
      throw NoCleanerRulesFoundException();
    }
    return StudioCleanerRules(
      bannedWords: _asString(parsed, 'bannedWords'),
      avoidInstructions: _asString(parsed, 'avoidInstructions'),
      styleInstructions: _asString(parsed, 'styleInstructions'),
    );
  }

  String _asString(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).join(', ').trim();
    }
    return v.toString().trim();
  }
}
