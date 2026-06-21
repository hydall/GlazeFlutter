import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/id_generator.dart';
import '../../shared/shell/desktop/desktop_layout_provider.dart';
import '../../features/character_list/character_detail_screen.dart';
import '../../features/character_list/character_editor_screen.dart';
import '../../features/character_list/character_list_screen.dart';
import '../../features/character_gallery/gallery_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat_history/chat_history_screen.dart';
import '../../features/lorebooks/lorebook_list_screen.dart';
import '../../features/lorebooks/lorebook_global_settings_screen.dart';
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
import '../../shared/shell/desktop/desktop_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

CustomTransitionPage<void> _overlayPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    child: child,
    transitionsBuilder: (_, _, _, child) => child,
  );
}

Page<void> _adaptivePage({
  required GoRouterState state,
  required Widget child,
}) {
  final isIosLikeTargetPlatform =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  if (isIosLikeTargetPlatform) {
    return CupertinoPage<void>(key: state.pageKey, child: child);
  }
  // On Android/other, use a real platform page transition (MaterialPage) so the
  // forward (open) navigation animates instead of snapping in. Previously this
  // fell back to `_overlayPage` (zero-duration), which made opening a route —
  // e.g. a chat — flicker into place while closing still animated (the
  // underlying MaterialPage shell reappears with its default transition),
  // leaving the open/close pair visibly asymmetric.
  return MaterialPage<void>(key: state.pageKey, child: child);
}

/// Constructs a [GoRouter] with the given [navigatorKey].
///
/// Extracted so tests can call `buildRouter(GlobalKey())` to get a fresh
/// router with a fresh key per test — sharing [rootNavigatorKey] across
/// tests causes GoRouter to silently skip navigation after the first test.
GoRouter buildRouter(
  GlobalKey<NavigatorState> navigatorKey, {
  bool Function()? isForceMobile,
}) => GoRouter(
  navigatorKey: navigatorKey,
  redirect: (context, state) {
    if (state.matchedLocation == '/') {
      final forceMobile = isForceMobile?.call() ?? false;
      if (!forceMobile && MediaQuery.sizeOf(context).width >= 768) {
        return '/characters';
      }
    }
    return null;
  },
  onException: (_, state, router) {
    final uri = state.uri;
    if (uri.scheme.isNotEmpty &&
        uri.scheme != 'http' &&
        uri.scheme != 'https') {
      return;
    }
    router.go('/');
  },
  routes: [
    ShellRoute(
      builder: (_, state, child) => DesktopShell(child: child),
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
              builder: (_, state) => CharacterListScreen(
                initialCharacterId: state.uri.queryParameters['open'],
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tools',
              pageBuilder: (_, state) =>
                  _overlayPage(state: state, child: const ToolsScreen()),
              routes: [
                GoRoute(
                  path: 'api',
                  pageBuilder: (_, state) => _adaptivePage(
                    state: state,
                    child: const ApiSettingsScreen(startExpanded: true),
                  ),
                ),
                GoRoute(
                  path: 'personas',
                  pageBuilder: (_, state) => _adaptivePage(
                    state: state,
                    child: const PersonaListScreen(startExpanded: true),
                  ),
                ),
                GoRoute(
                  path: 'presets',
                  pageBuilder: (_, state) => _adaptivePage(
                    state: state,
                    child: const PresetListScreen(startExpanded: true),
                  ),
                ),
                GoRoute(
                  path: 'regex',
                  pageBuilder: (_, state) => _adaptivePage(
                    state: state,
                    child: const RegexSheet(startExpanded: true),
                  ),
                ),
                GoRoute(
                  path: 'lorebooks',
                  pageBuilder: (_, state) => _adaptivePage(
                    state: state,
                    child: const LorebookListScreen(startExpanded: true),
                  ),
                  routes: [
                    GoRoute(
                      path: 'settings',
                      pageBuilder: (_, state) => _adaptivePage(
                        state: state,
                        child: const LorebookGlobalSettingsScreen(),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'embeddings',
                  pageBuilder: (_, state) => _adaptivePage(
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
              pageBuilder: (_, state) =>
                  _overlayPage(state: state, child: const MenuScreen()),
              routes: [
                GoRoute(
                  path: 'settings',
                  pageBuilder: (_, state) => _adaptivePage(
                    state: state,
                    child: const AppSettingsScreen(),
                  ),
                ),
                GoRoute(
                  path: 'themes',
                  pageBuilder: (_, state) => _adaptivePage(
                    state: state,
                    child: const ThemePresetScreen(),
                  ),
                ),
                GoRoute(
                  path: 'about',
                  pageBuilder: (_, state) =>
                      _adaptivePage(state: state, child: const AboutScreen()),
                ),
                GoRoute(
                  path: 'glossary',
                  pageBuilder: (_, state) => _adaptivePage(
                    state: state,
                    child: const GlossarySheet(startExpanded: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/chat/:charId',
      pageBuilder: (_, state) {
        final charId = state.pathParameters['charId']!;
        final sessionIdx = int.tryParse(
          state.uri.queryParameters['session'] ?? '',
        );
        final isNew = state.uri.queryParameters['new'] == '1';
        final targetMsgId = state.uri.queryParameters['msg'];
        return _adaptivePage(
          state: state,
          child: ChatScreen(
            charId: charId,
            initialSessionIndex: sessionIdx,
            forceNewSession: isNew,
            targetMessageId:
                (targetMsgId != null && targetMsgId.isNotEmpty)
                    ? targetMsgId
                    : null,
          ),
        );
      },
    ),
    GoRoute(
      path: '/character/create',
      pageBuilder: (_, state) => _adaptivePage(
        state: state,
        child: CharacterEditorScreen(charId: generateId(), isNew: true),
      ),
    ),
    GoRoute(
      path: '/character/:charId',
      pageBuilder: (_, state) => _adaptivePage(
        state: state,
        child: CharacterDetailSheetLauncher(
          charId: state.pathParameters['charId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/character/:charId/edit',
      pageBuilder: (_, state) => _adaptivePage(
        state: state,
        child: CharacterEditorScreen(charId: state.pathParameters['charId']!),
      ),
    ),
    GoRoute(
      path: '/character/:charId/gallery',
      pageBuilder: (_, state) => _adaptivePage(
        state: state,
        child: GalleryScreen(charId: state.pathParameters['charId']!),
      ),
    ),
    GoRoute(
      path: '/sync',
      pageBuilder: (_, state) =>
          _overlayPage(state: state, child: const SyncSheet()),
    ),
    GoRoute(
      path: '/extensions',
      pageBuilder: (_, state) =>
          _overlayPage(state: state, child: const ExtensionsScreen()),
      routes: [
        GoRoute(
          path: 'preset-editor/:presetId',
          pageBuilder: (_, state) => _adaptivePage(
            state: state,
            child: PresetEditorScreen(
              presetId: state.pathParameters['presetId']!,
            ),
          ),
        ),
      ],
    ),
      ],
    ),
  ],
);

final routerProvider = Provider<GoRouter>(
  (ref) => buildRouter(
    rootNavigatorKey,
    isForceMobile: () => ref.read(forceMobileLayoutProvider),
  ),
);
