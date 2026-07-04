import 'dart:convert';

import '../../models/character.dart';
import '../../models/chat_message.dart';
import '../../models/persona.dart';
import '../shared/message_range_formatter.dart';

/// Builds the POST-cleaner character/world auditor prompt and parses its JSON
/// response.
///
/// The auditor is a diagnostic sidecar pass that checks the assistant response
/// against the full generation context and returns a compact JSON list of
/// contradictions. It does NOT rewrite text — the cleaner does that separately
/// using the audit issues as fix instructions.
class AuditPromptBuilder {
  /// Builds the auditor prompt. The auditor checks the assistant response
  /// against all provided context and returns a compact JSON list of
  /// contradictions.
  static String buildAuditPrompt({
    required String assistantText,
    required Character character,
    Persona? persona,
    String? lorebooksContent,
    String? memoryContent,
    String? summaryContent,
    String? arcContent,
    String? entitiesContent,
    List<ChatMessage> recentMessages = const [],
    int maxCharsPerMessage = kDefaultMaxMessageChars,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'You are a continuity auditor for a roleplay story. Your job is to '
        'find contradictions between the assistant response and the provided '
        'context.',
      )
      ..writeln();

    // Character profile.
    buffer.writeln('CHARACTER PROFILE:');
    buffer.writeln('Name: ${character.name}');
    final desc = character.description?.trim() ?? '';
    if (desc.isNotEmpty) buffer.writeln('Description: $desc');
    final pers = character.personality?.trim() ?? '';
    if (pers.isNotEmpty) buffer.writeln('Personality: $pers');
    final scen = character.scenario?.trim() ?? '';
    if (scen.isNotEmpty) buffer.writeln('Scenario: $scen');
    final phi = character.postHistoryInstructions?.trim() ?? '';
    if (phi.isNotEmpty) buffer.writeln('Post-history instructions: $phi');
    buffer.writeln();

    // User persona.
    if (persona != null) {
      buffer.writeln('USER PERSONA:');
      buffer.writeln('Name: ${persona.name}');
      final pp = persona.prompt?.trim() ?? '';
      if (pp.isNotEmpty) buffer.writeln('Description: $pp');
      buffer.writeln();
    }

    // Lorebooks / world context.
    final lore = lorebooksContent?.trim() ?? '';
    if (lore.isNotEmpty) {
      buffer
        ..writeln('INJECTED WORLD/LORE CONTEXT:')
        ..writeln(lore)
        ..writeln();
    }

    // Memory context.
    final mem = memoryContent?.trim() ?? '';
    if (mem.isNotEmpty) {
      buffer
        ..writeln('INJECTED MEMORY CONTEXT:')
        ..writeln(mem)
        ..writeln();
    }

    // Summary.
    final sum = summaryContent?.trim() ?? '';
    if (sum.isNotEmpty) {
      buffer
        ..writeln('SUMMARY:')
        ..writeln(sum)
        ..writeln();
    }

    // Arcs.
    final arcs = arcContent?.trim() ?? '';
    if (arcs.isNotEmpty) {
      buffer
        ..writeln('ARCS:')
        ..writeln(arcs)
        ..writeln();
    }

    // Entities.
    final ents = entitiesContent?.trim() ?? '';
    if (ents.isNotEmpty) {
      buffer
        ..writeln('ENTITIES:')
        ..writeln(ents)
        ..writeln();
    }

    // Recent chat history.
    if (recentMessages.isNotEmpty) {
      final history = formatRecentMessages(recentMessages, maxCharsPerMessage);
      if (history.isNotEmpty) {
        buffer
          ..writeln('RECENT CHAT HISTORY:')
          ..writeln(history)
          ..writeln();
      }
    }

    buffer
      ..writeln('ASSISTANT RESPONSE TO AUDIT:')
      ..writeln(assistantText)
      ..writeln()
      ..writeln('Instructions:')
      ..writeln('- Check the response against ALL provided context.')
      ..writeln(
        '- Report ONLY direct contradictions: wrong names, wrong '
        'relationships, wrong locations, personality conflicts, world-fact '
        'errors, persona identity errors.',
      )
      ..writeln('- Do NOT report style issues, cliches, or prose quality.')
      ..writeln(
        '- Do NOT suggest fixes or rewrites. Only describe the contradiction.',
      )
      ..writeln('- If no contradictions found, return: {"ok": true}')
      ..writeln(
        '- If contradictions found, return: {"ok": false, "issues": ["...", "..."]}',
      )
      ..writeln()
      ..writeln('Return ONLY the JSON, no other text.');

    return buffer.toString();
  }

  /// Parses the auditor JSON response.
  ///
  /// - `{"ok": true}` → `[]`
  /// - `{"ok": false, "issues": [...]}` → list of strings
  /// - malformed / unparseable → `null` (skip audit)
  static List<String>? parseAuditJson(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    // Some models wrap JSON in ``` fences or prose. Extract the first
    // balanced `{...}` block.
    final start = text.indexOf('{');
    if (start < 0) return null;
    final end = text.lastIndexOf('}');
    if (end <= start) return null;
    text = text.substring(start, end + 1);

    try {
      final parsed = jsonDecode(text);
      if (parsed is! Map<String, dynamic>) return null;
      final ok = parsed['ok'];
      if (ok == true) return const [];
      if (ok == false) {
        final issues = parsed['issues'];
        if (issues is List) {
          return issues
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .toList();
        }
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
