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
import '../../features/regex/regex_sheet.dart';
import '../../features/settings/api_settings_screen.dart';
import '../../features/cloud_sync/widgets/sync_sheet.dart';
import '../../features/settings/app_settings_screen.dart';
import '../../features/settings/theme_preset_screen.dart';
import '../../features/tools/tools_screen.dart';
import '../../features/glossary/glossary_sheet.dart';
import '../../features/extensions/screens/extensions_screen.dart';
import '../../features/extensions/screens/preset_editor_screen.dart';
import '../../shared/shell/shell_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

CustomTransitionPage<void> _overlayPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final primary = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      );
      final secondary = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      );
      final incomingSlide = Tween<Offset>(
        begin: const Offset(0.06, 0),
        end: Offset.zero,
      ).animate(primary);
      final incomingFade = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(
        CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
          reverseCurve: Curves.easeOutCubic,
        ),
      );
      final outgoingSlide = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.03, 0),
      ).animate(secondary);
      final outgoingFade = Tween<double>(
        begin: 1.0,
        end: 0.0,
      ).animate(
        CurvedAnimation(
          parent: secondaryAnimation,
          curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          reverseCurve: Curves.easeOutCubic,
        ),
      );

      return SlideTransition(
        position: incomingSlide,
        child: FadeTransition(
          opacity: incomingFade,
          child: SlideTransition(
            position: outgoingSlide,
            child: FadeTransition(
              opacity: outgoingFade,
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// Constructs a [GoRouter] with the given [navigatorKey].
///
/// Extracted so tests can call `buildRouter(GlobalKey())` to get a fresh
/// router with a fresh key per test — sharing [rootNavigatorKey] across
/// tests causes GoRouter to silently skip navigation after the first test.
GoRouter buildRouter(GlobalKey<NavigatorState> navigatorKey) => GoRouter(
    navigatorKey: navigatorKey,
    onException: (_, state, router) {
      final uri = state.uri;
      if (uri.scheme.isNotEmpty && uri.scheme != 'http' && uri.scheme != 'https') {
        return;
      }
      router.go('/');
    },
    routes: [
      StatefulShellRoute(
        builder: (_, _, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        navigatorContainerBuilder: (_, navigationShell, children) =>
            FadeBranchContainer(
          currentIndex: navigationShell.currentIndex,
          children: children,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const ChatHistoryScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/characters',
                builder: (_, _) => const CharacterListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tools',
                pageBuilder: (_, state) => _overlayPage(
                  state: state,
                  child: const ToolsScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'api',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const ApiSettingsScreen(startExpanded: true),
                    ),
                  ),
                  GoRoute(
                    path: 'personas',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const PersonaListScreen(startExpanded: true),
                    ),
                  ),
                  GoRoute(
                    path: 'presets',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const PresetListScreen(startExpanded: true),
                    ),
                  ),
                  GoRoute(
                    path: 'regex',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const RegexSheet(startExpanded: true),
                    ),
                  ),
                  GoRoute(
                    path: 'lorebooks',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const LorebookListScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'embeddings',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const EmbeddingSettingsScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/menu',
                pageBuilder: (_, state) => _overlayPage(
                  state: state,
                  child: const MenuScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'settings',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const AppSettingsScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'themes',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const ThemePresetScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'about',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const AboutScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'glossary',
                    pageBuilder: (_, state) => _overlayPage(
                      state: state,
                      child: const GlossarySheet(startExpanded: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chat',
                builder: (_, _) => const SizedBox.shrink(),
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
      GoRoute(
        path: '/sync',
        pageBuilder: (_, state) => _overlayPage(
          state: state,
          child: const SyncSheet(),
        ),
      ),
      GoRoute(
        path: '/extensions',
        pageBuilder: (_, state) => _overlayPage(
          state: state,
          child: const ExtensionsScreen(),
        ),
        routes: [
          GoRoute(
            path: 'preset-editor/:presetId',
            pageBuilder: (_, state) => _overlayPage(
              state: state,
              child: PresetEditorScreen(
                presetId: state.pathParameters['presetId']!,
              ),
            ),
          ),
        ],
      ),
    ],
  );

final routerProvider = Provider<GoRouter>(
  (ref) => buildRouter(rootNavigatorKey),
);
