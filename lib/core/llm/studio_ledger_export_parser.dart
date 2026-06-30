import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'json_repair.dart';
import '../models/studio_ledger_export.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StudioLedgerExportParser
//
// Extracts and validates the <glaze_memory_export> JSON block from the raw
// Studio Ledger LLM response (which also contains a <studio_ledger> visible
// block). Returns null when the block is absent, malformed, or wholly invalid.
//
// Validation rules (from PLAN_STUDIO_LEDGER_MEMORY.md Validation section):
//   - Reject unknown op codes.
//   - Reject unknown namespace prefixes.
//   - Reject overlong values (exceeds kLedgerMaxValueChars).
//   - Reject malformed JSON.
//   - Skip locked fields (done at write-time by TrackerRepo).
//   - Ignore empty exports (no ops AND no durableFacts).
//   - Quarantine bad exports, return null.
// ─────────────────────────────────────────────────────────────────────────────

/// Maximum character length for a single op value.
const int kLedgerMaxValueChars = 2000;

/// Allowed namespace prefixes for op keys.
const Set<String> kAllowedNamespacePrefixes = {
  'npc:',
  'relationship:',
  'arc:',
  'world:',
  'scene.',
};

/// Allowed op codes.
const Set<String> kAllowedOpCodes = {'set', 'append_unique', 'delete'};

/// Allowed event-state tokens (empty string = unset, allowed).
const Set<String> kAllowedEventStates = {
  '',
  'planned',
  'suggested',
  'threatened',
  'attempted',
  'completed',
  'failed',
  'cancelled',
  'unknown',
};

/// Result of parsing a Studio Ledger LLM response.
class LedgerParseResult {
  /// The validated export. Null when absent or wholly invalid.
  final StudioLedgerExport? export;

  /// The raw visible `studio_ledger` block text (may be empty if absent).
  final String visibleLedger;

  /// Human-readable rejection reason, for diagnostics.
  final String? rejectionReason;

  const LedgerParseResult({
    this.export,
    required this.visibleLedger,
    this.rejectionReason,
  });

  bool get hasExport => export != null;
  bool get wasRejected => rejectionReason != null;
}

/// Parses and validates the Studio Ledger LLM output.
///
/// Stateless — all methods are pure functions over the raw LLM text.
class StudioLedgerExportParser {
  const StudioLedgerExportParser();

  /// Parse the full LLM [rawOutput] and return a [LedgerParseResult].
  ///
  /// - Extracts the `<studio_ledger>…</studio_ledger>` visible block.
  /// - Extracts the `<glaze_memory_export>…</glaze_memory_export>` JSON block.
  /// - Validates the export (see class-level docs).
  /// - Returns null export + rejectionReason when invalid.
  LedgerParseResult parse(String rawOutput) {
    final visibleLedger = _extractBlock(rawOutput, 'studio_ledger');
    final exportRaw = _extractBlock(rawOutput, 'glaze_memory_export');

    if (exportRaw.isEmpty) {
      return LedgerParseResult(
        visibleLedger: visibleLedger,
        rejectionReason: 'no <glaze_memory_export> block found',
      );
    }

    StudioLedgerExport export;
    try {
      final jsonRaw = extractJsonObject(exportRaw);
      if (jsonRaw == null) {
        return LedgerParseResult(
          visibleLedger: visibleLedger,
          rejectionReason: 'export block does not contain a JSON object',
        );
      }
      final decoded = jsonDecode(repairJson(jsonRaw));
      if (decoded is! Map<String, dynamic>) {
        return LedgerParseResult(
          visibleLedger: visibleLedger,
          rejectionReason: 'export root is not a JSON object',
        );
      }
      export = StudioLedgerExport.fromJson(decoded);
    } catch (e) {
      debugPrint('[StudioLedger] JSON parse error: $e');
      return LedgerParseResult(
        visibleLedger: visibleLedger,
        rejectionReason: 'malformed JSON: $e',
      );
    }

    // Validate ops.
    final validatedOps = <LedgerOp>[];
    final rejectedOps = <String>[];

    for (final op in export.ops) {
      final reason = _validateOp(op);
      if (reason != null) {
        rejectedOps.add('${op.key}: $reason');
        debugPrint('[StudioLedger] rejected op ${op.op} ${op.key}: $reason');
      } else {
        validatedOps.add(op);
      }
    }

    if (rejectedOps.isNotEmpty) {
      debugPrint(
        '[StudioLedger] ${rejectedOps.length} ops rejected out of '
        '${export.ops.length}',
      );
    }

    // Ignore completely empty exports.
    final isEmpty = validatedOps.isEmpty && export.durableFacts.isEmpty;
    if (isEmpty) {
      return LedgerParseResult(
        visibleLedger: visibleLedger,
        rejectionReason: rejectedOps.isNotEmpty
            ? 'all ops rejected, no durable facts'
            : 'empty export (no ops, no durable facts)',
      );
    }

    final validatedExport = export.copyWith(ops: validatedOps);
    return LedgerParseResult(
      export: validatedExport,
      visibleLedger: visibleLedger,
    );
  }

  // ── Extraction ─────────────────────────────────────────────────────────────

  /// Extract the inner text of `<[tag]>…</[tag]>` from [source].
  /// Returns an empty string when not found.
  String _extractBlock(String source, String tag) {
    final open = '<$tag>';
    final close = '</$tag>';
    final start = source.indexOf(open);
    if (start < 0) return '';
    final contentStart = start + open.length;
    final end = source.indexOf(close, contentStart);
    if (end < 0) return '';
    return source.substring(contentStart, end).trim();
  }

  // ── Validation ──────────────────────────────────────────────────────────────

  /// Returns a rejection reason string, or null when the op is valid.
  String? _validateOp(LedgerOp op) {
    // Unknown op code.
    if (!kAllowedOpCodes.contains(op.op)) {
      return 'unknown op code "${op.op}"';
    }

    // Unknown namespace.
    final hasValidNs = kAllowedNamespacePrefixes.any(
      (prefix) => op.key.startsWith(prefix),
    );
    if (!hasValidNs) {
      return 'unknown namespace in key "${op.key}"';
    }

    // Key must be non-empty and have a sub-key after the prefix.
    if (op.key.trim().isEmpty) {
      return 'empty key';
    }

    // For set / append_unique: value must not be empty.
    if (op.op != 'delete' && op.value.trim().isEmpty) {
      return 'empty value for op "${op.op}"';
    }

    // Overlong value.
    if (op.value.length > kLedgerMaxValueChars) {
      return 'value exceeds max length ($kLedgerMaxValueChars chars)';
    }

    // Unknown event state.
    if (!kAllowedEventStates.contains(op.eventState)) {
      return 'unknown eventState "${op.eventState}"';
    }

    return null;
  }
}
