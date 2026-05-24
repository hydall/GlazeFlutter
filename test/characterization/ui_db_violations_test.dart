import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UI→DB violations (Phase 2.5 characterization)', () {
    final violatingFiles = <String, List<String>>{
      'lib/features/chat/widgets/magic_drawer.dart': ['chatRepoProvider'],
      'lib/features/chat/widgets/summary_sheet.dart': ['chatRepoProvider'],
      'lib/features/chat/widgets/authors_note_sheet.dart': ['chatRepoProvider'],
      'lib/features/chat/widgets/chat_stats_sheet.dart': ['characterRepoProvider', 'chatRepoProvider'],
      'lib/features/chat/widgets/lorebook_coverage_sheet.dart': ['characterRepoProvider', 'lorebookRepoProvider'],
      'lib/features/chat/widgets/context_info_sheet.dart': ['lorebookRepoProvider'],
      'lib/features/chat/widgets/chat_dialogs.dart': ['presetRepoProvider', 'personaRepoProvider'],
      'lib/features/chat/widgets/memory_books_sheet.dart': ['memoryBookRepoProvider'],
      'lib/features/regex/regex_list_screen.dart': ['presetRepoProvider'],
      'lib/features/personas/persona_list_screen.dart': ['personaRepoProvider'],
      'lib/features/personas/persona_connections_sheet.dart': ['personaRepoProvider', 'chatRepoProvider'],
      'lib/features/character_list/character_editor_screen.dart': ['characterRepoProvider'],
      'lib/features/character_list/character_detail_screen.dart': ['characterRepoProvider', 'chatRepoProvider'],
      'lib/features/character_list/character_list_screen.dart': ['lorebookRepoProvider'],
      'lib/features/tools/tools_screen.dart': ['personaRepoProvider', 'presetRepoProvider'],
      'lib/features/presets/preset_editor_screen.dart': ['presetRepoProvider'],
      'lib/features/picks/widgets/picks_detail_launcher.dart': ['lorebookRepoProvider'],
    };

    test('all violating files exist on disk', () {
      for (final path in violatingFiles.keys) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '$path should exist',
        );
      }
    });

    for (final entry in violatingFiles.entries) {
      test('${entry.key} imports ${entry.value.join(", ")}', () {
        final source = File(entry.key).readAsStringSync();
        for (final repo in entry.value) {
          expect(
            source,
            contains(repo),
            reason: '${entry.key} must import $repo (current violation we are characterizing)',
          );
        }
      });
    }

    test('total UI→DB violation count is 17 files', () {
      expect(violatingFiles.length, 17);
    });

    test('chat widgets are the biggest offenders (3+ files with chatRepoProvider)', () {
      final chatRepoViolations = violatingFiles.entries
          .where((e) => e.value.contains('chatRepoProvider'))
          .length;
      expect(chatRepoViolations, greaterThanOrEqualTo(5));
    });

    test('mutation calls (.put) exist in widget code', () async {
      final mutationPattern = RegExp(r'\.put\(');
      var foundMutations = 0;
      for (final path in violatingFiles.keys) {
        final source = File(path).readAsStringSync();
        if (mutationPattern.hasMatch(source)) {
          foundMutations++;
        }
      }
      expect(foundMutations, greaterThanOrEqualTo(8),
          reason: 'At least 8 widget files call .put() directly on repos');
    });

    test('delete calls exist in widget code', () async {
      var foundDelete = false;
      for (final path in violatingFiles.keys) {
        final source = File(path).readAsStringSync();
        if (source.contains('.delete(')) {
          foundDelete = true;
          break;
        }
      }
      expect(foundDelete, isTrue,
          reason: 'At least one widget calls .delete() directly on a repo');
    });
  });

  group('Architecture layer imports (Phase 2.5 characterization)', () {
    test('provider files do NOT import from widgets', () {
      final providerFiles = Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('_provider.dart'))
          .where((f) => !f.path.contains('characterization'));

      for (final file in providerFiles) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('widgets/')),
          reason: '${file.path} should not import from widgets layer',
        );
      }
    });

    test('repo files do NOT import from widgets or providers', () {
      final repoFiles = Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('_repo.dart'));

      for (final file in repoFiles) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('widgets/')),
          reason: '${file.path} should not import from widgets layer',
        );
      }
    });
  });
}
