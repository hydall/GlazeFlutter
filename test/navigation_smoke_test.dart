import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glaze_flutter/app.dart';
import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';

import 'package:glaze_flutter/features/chat_history/chat_history_screen.dart';
import 'package:glaze_flutter/features/character_list/character_list_screen.dart';
import 'package:glaze_flutter/features/tools/tools_screen.dart';
import 'package:glaze_flutter/features/menu/menu_screen.dart';
import 'package:glaze_flutter/features/settings/app_settings_screen.dart';
import 'package:glaze_flutter/features/settings/theme_preset_screen.dart';
import 'package:glaze_flutter/features/menu/about_screen.dart';
import 'package:glaze_flutter/features/lorebooks/lorebook_list_screen.dart';
import 'package:glaze_flutter/features/lorebooks/embedding_settings_screen.dart';
import 'package:glaze_flutter/features/settings/api_settings_screen.dart';
import 'package:glaze_flutter/features/personas/persona_list_screen.dart';
import 'package:glaze_flutter/features/presets/preset_list_screen.dart';
import 'package:glaze_flutter/features/regex/regex_list_screen.dart';

class ScreenEntry {
  final String path;
  final Type screenType;
  final String parentPath;
  final String description;

  const ScreenEntry({
    required this.path,
    required this.screenType,
    required this.parentPath,
    required this.description,
  });
}

const screenRegistry = <ScreenEntry>[
  ScreenEntry(
    path: '/',
    screenType: ChatHistoryScreen,
    parentPath: '/',
    description: 'Chat history (shell tab 0)',
  ),
  ScreenEntry(
    path: '/characters',
    screenType: CharacterListScreen,
    parentPath: '/characters',
    description: 'Character list (shell tab 1)',
  ),
  ScreenEntry(
    path: '/tools',
    screenType: ToolsScreen,
    parentPath: '/tools',
    description: 'Tools (shell tab 2)',
  ),
  ScreenEntry(
    path: '/menu',
    screenType: MenuScreen,
    parentPath: '/menu',
    description: 'Menu (shell tab 3)',
  ),
  ScreenEntry(
    path: '/settings',
    screenType: AppSettingsScreen,
    parentPath: '/menu',
    description: 'App settings',
  ),
  ScreenEntry(
    path: '/themes',
    screenType: ThemePresetScreen,
    parentPath: '/settings',
    description: 'Theme presets',
  ),
  ScreenEntry(
    path: '/about',
    screenType: AboutScreen,
    parentPath: '/menu',
    description: 'About screen',
  ),
  ScreenEntry(
    path: '/tools/api',
    screenType: ApiSettingsScreen,
    parentPath: '/tools',
    description: 'API settings',
  ),
  ScreenEntry(
    path: '/tools/personas',
    screenType: PersonaListScreen,
    parentPath: '/tools',
    description: 'Persona list',
  ),
  ScreenEntry(
    path: '/tools/presets',
    screenType: PresetListScreen,
    parentPath: '/tools',
    description: 'Preset list',
  ),
  ScreenEntry(
    path: '/tools/regex',
    screenType: RegexListScreen,
    parentPath: '/tools',
    description: 'Regex list',
  ),
  ScreenEntry(
    path: '/tools/lorebooks',
    screenType: LorebookListScreen,
    parentPath: '/tools',
    description: 'Lorebook list',
  ),
  ScreenEntry(
    path: '/tools/embeddings',
    screenType: EmbeddingSettingsScreen,
    parentPath: '/tools',
    description: 'Embedding settings',
  ),
];

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  GoRouter router() => container.read(routerProvider);

  testWidgets('App starts without black/red screen', (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const GlazeApp(),
    ));

    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  group('Screen navigation coverage', () {
    for (final entry in screenRegistry) {
      testWidgets('Navigate to ${entry.description} (${entry.path})',
          (tester) async {
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const GlazeApp(),
        ));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        router().go(entry.path);
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(
          find.byType(entry.screenType),
          findsWidgets,
          reason:
              'Expected to find ${entry.screenType} at ${entry.path}, '
              'but it was not found. If you added a new screen, '
              'update screenRegistry in navigation_smoke_test.dart.',
        );
      });
    }
  });

  testWidgets('Shell tabs are all reachable', (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const GlazeApp(),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final shellTabs = [
      ('/', 'Chat history', ChatHistoryScreen),
      ('/characters', 'Characters', CharacterListScreen),
      ('/tools', 'Tools', ToolsScreen),
      ('/menu', 'Menu', MenuScreen),
    ];

    for (final (path, label, screenType) in shellTabs) {
      router().go(path);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(
        find.byType(screenType),
        findsWidgets,
        reason: 'Shell tab "$label" at $path did not render $screenType',
      );
    }
  });

  testWidgets('Sub-screen back navigation returns to parent',
      (tester) async {
    final subScreens = [
      ('/settings', '/menu', AppSettingsScreen, MenuScreen, 'App settings → Menu'),
      ('/tools/api', '/tools', ApiSettingsScreen, ToolsScreen, 'API settings → Tools'),
      ('/tools/personas', '/tools', PersonaListScreen, ToolsScreen, 'Persona list → Tools'),
      ('/about', '/menu', AboutScreen, MenuScreen, 'About → Menu'),
    ];

    for (final (subPath, parentPath, subType, parentType, label) in subScreens) {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const GlazeApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      router().go(subPath);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(
        find.byType(subType),
        findsWidgets,
        reason: 'Failed to navigate to $subPath for $label test',
      );

      router().go(parentPath);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(
        find.byType(parentType),
        findsWidgets,
        reason: 'Back navigation for "$label" failed: '
            'expected $parentType at $parentPath after going back',
      );
    }
  });
}