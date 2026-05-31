import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/id_generator.dart';
import '../../features/character_list/character_detail_screen.dart';
import '../../features/character_list/character_editor_screen.dart';
import '../../features/character_list/character_list_screen.dart';
import '../../features/character_gallery/gallery_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat_history/chat_history_screen.dart';
import '../../features/lorebooks/lorebook_list_screen.dart';
import '../../features/lorebooks/embedding_settings_screen.dart';
import '../../features/menu/about_screen.dart';
import '../../features/menu/menu_screen.dart';
import '../../features/personas/persona_list_screen.dart';
import '../../features/presets/preset_list_screen.dart';
import '../../features/regex/regex_list_screen.dart';
import '../../features/settings/api_settings_screen.dart';
import '../../features/cloud_sync/widgets/sync_sheet.dart';
import '../../features/settings/app_settings_screen.dart';
import '../../features/settings/theme_preset_screen.dart';
import '../../features/tools/tools_screen.dart';
import '../../features/glossary/glossary_sheet.dart';
import '../../shared/shell/shell_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    navigatorKey: rootNavigatorKey,
    onException: (_, state, router) {
      final uri = state.uri;
      if (uri.scheme.isNotEmpty && uri.scheme != 'http' && uri.scheme != 'https') {
        return;
      }
      router.go('/');
    },
    routes: [
      StatefulShellRoute(
        builder: (_, __, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        navigatorContainerBuilder: (_, navigationShell, children) =>
            FadeBranchContainer(
          currentIndex: navigationShell.currentIndex,
          children: children,
        ),
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
                    builder: (_, __) => const ApiSettingsScreen(startExpanded: true),
                  ),
                  GoRoute(
                    path: 'personas',
                    builder: (_, __) =>
                        const PersonaListScreen(startExpanded: true),
                  ),
                  GoRoute(
                    path: 'presets',
                    builder: (_, __) =>
                        const PresetListScreen(startExpanded: true),
                  ),
                  GoRoute(
                    path: 'regex',
                    builder: (_, __) =>
                        const RegexListScreen(startExpanded: true),
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
              GoRoute(
                path: '/menu',
                builder: (_, __) => const MenuScreen(),
                routes: [
                  GoRoute(
                    path: 'glossary',
                    builder: (_, __) => const GlossarySheet(startExpanded: true),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chat',
                builder: (_, __) => const SizedBox.shrink(),
                routes: [
                  GoRoute(
                    path: ':charId',
                    builder: (_, state) {
                      final charId = state.pathParameters['charId']!;
                      final sessionIdx = int.tryParse(
                          state.uri.queryParameters['session'] ?? '');
                      final isNew = state.uri.queryParameters['new'] == '1';
                      return ChatScreen(
                        charId: charId,
                        initialSessionIndex: sessionIdx,
                        forceNewSession: isNew,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/character/create',
        builder: (_, _) => CharacterEditorScreen(
          charId: generateId(),
          isNew: true,
        ),
      ),
      GoRoute(
        path: '/character/:charId',
        builder: (_, state) => CharacterDetailSheetLauncher(
            charId: state.pathParameters['charId']!),
      ),
      GoRoute(
        path: '/character/:charId/edit',
        builder: (_, state) =>
            CharacterEditorScreen(charId: state.pathParameters['charId']!),
      ),
      GoRoute(
        path: '/character/:charId/gallery',
        builder: (_, state) =>
            GalleryScreen(charId: state.pathParameters['charId']!),
      ),

      GoRoute(path: '/settings', builder: (_, __) => const AppSettingsScreen()),
      GoRoute(path: '/themes', builder: (_, __) => const ThemePresetScreen()),
      GoRoute(path: '/sync', builder: (_, __) => const SyncSheet()),
      GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
    ],
  ),
);
