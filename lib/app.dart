import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/character_list/character_detail_screen.dart';
import 'features/character_list/character_list_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat_history/chat_history_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/personas/persona_list_screen.dart';
import 'features/presets/preset_list_screen.dart';
import 'features/settings/api_settings_screen.dart';
import 'features/settings/app_settings_screen.dart';
import 'features/tools/tools_screen.dart';
import 'shared/shell/shell_screen.dart';
import 'shared/theme/app_theme.dart';

final routerProvider = Provider<GoRouter>((ref) => GoRouter(
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, navigationShell) =>
              ShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/',
                builder: (_, __) => const ChatHistoryScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/characters',
                builder: (_, __) => const CharacterListScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/menu',
                builder: (_, __) => const MenuScreen(),
              ),
            ]),
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
        ),
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
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const AppSettingsScreen(),
        ),
      ],
    ));

class GlazeApp extends ConsumerWidget {
  const GlazeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Glaze',
      theme: AppTheme.dark(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
