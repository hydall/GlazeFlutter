import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/state/active_selection_provider.dart';
import 'core/services/preset_seeder.dart';
import 'core/services/crash_recovery_service.dart';
import 'features/character_list/character_detail_screen.dart';
import 'features/character_list/character_editor_screen.dart';
import 'features/character_list/character_list_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat_history/chat_history_screen.dart';
import 'features/lorebooks/lorebook_list_screen.dart';
import 'features/lorebooks/embedding_settings_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/personas/persona_list_screen.dart';
import 'features/presets/preset_list_screen.dart';
import 'features/regex/regex_list_screen.dart';
import 'features/settings/api_settings_screen.dart';
import 'features/settings/app_settings_screen.dart';
import 'features/tools/tools_screen.dart';
import 'shared/shell/shell_screen.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_provider.dart';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, __) => const ChatHistoryScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/characters',
                builder: (_, __) => const CharacterListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tools',
                builder: (_, __) => const ToolsScreen(),
                routes: [
                  GoRoute(
                    path: 'api',
                    builder: (_, __) => const ApiSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'personas',
                    builder: (_, __) => const PersonaListScreen(),
                  ),
                  GoRoute(
                    path: 'presets',
                    builder: (_, __) => const PresetListScreen(),
                  ),
                  GoRoute(
                    path: 'regex',
                    builder: (_, __) => const RegexListScreen(),
                  ),
                  GoRoute(
                    path: 'lorebooks',
                    builder: (_, __) => const LorebookListScreen(),
                  ),
                  GoRoute(
                    path: 'embeddings',
                    builder: (_, __) => const EmbeddingSettingsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/chat/:charId',
        builder: (_, state) =>
            ChatScreen(charId: state.pathParameters['charId']!),
      ),
      GoRoute(
        path: '/character/:charId',
        builder: (_, state) =>
            CharacterDetailScreen(charId: state.pathParameters['charId']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, state) =>
                CharacterEditorScreen(charId: state.pathParameters['charId']!),
          ),
        ],
      ),

      GoRoute(path: '/settings', builder: (_, __) => const AppSettingsScreen()),
    ],
  ),
);

class GlazeApp extends ConsumerStatefulWidget {
  const GlazeApp({super.key});

  @override
  ConsumerState<GlazeApp> createState() => _GlazeAppState();
}

class _GlazeAppState extends ConsumerState<GlazeApp> {
  @override
  void initState() {
    super.initState();
    loadActiveSelections(ref);
    seedDefaultPresets(ref);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkAndOfferCrashRecovery(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeSettings = ref.watch(themeProvider);
    return MaterialApp.router(
      title: 'Glaze',
      theme: AppTheme.light(accent: themeSettings.accentColor),
      darkTheme: AppTheme.dark(accent: themeSettings.accentColor),
      themeMode: themeSettings.mode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
