import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/services/generation_notification_service.dart';
import 'core/state/active_selection_provider.dart';
import 'core/state/lorebook_provider.dart';
import 'core/services/preset_seeder.dart';
import 'shared/theme/theme_font_provider.dart';
import 'core/services/onboarding_service.dart';
import 'features/cloud_sync/sync_provider.dart';
import 'features/cloud_sync/sync_models.dart';
import 'features/character_list/character_detail_screen.dart';
import 'features/character_list/character_editor_screen.dart';
import 'core/utils/id_generator.dart';
import 'features/character_list/character_list_screen.dart';
import 'features/character_gallery/gallery_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat_history/chat_history_screen.dart';
import 'features/lorebooks/lorebook_list_screen.dart';
import 'features/lorebooks/embedding_settings_screen.dart';
import 'features/menu/about_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/personas/persona_list_screen.dart';
import 'features/presets/preset_list_screen.dart';
import 'features/regex/regex_list_screen.dart';
import 'features/settings/api_settings_screen.dart';
import 'features/cloud_sync/widgets/sync_sheet.dart';
import 'features/settings/app_settings_screen.dart';
import 'features/settings/theme_preset_screen.dart';
import 'features/tools/tools_screen.dart';
import 'shared/shell/shell_screen.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_provider.dart';

import 'shared/widgets/glaze_toast.dart' show toastOverlayKey;

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
              GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/chat/:charId',
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

class GlazeApp extends ConsumerStatefulWidget {
  final VoidCallback? restart;
  const GlazeApp({super.key, this.restart});

  static VoidCallback? _restart;

  static void restartApp() => _restart?.call();

  @override
  ConsumerState<GlazeApp> createState() => _GlazeAppState();
}

class _GlazeAppState extends ConsumerState<GlazeApp> with WidgetsBindingObserver {
  StreamSubscription<String>? _navSub;

  @override
  void initState() {
    super.initState();
    GlazeApp._restart = widget.restart;
    WidgetsBinding.instance.addObserver(this);
    loadActiveSelections(ref);
    loadLorebookActivations(ref);
    loadLorebookSettings(ref);
    seedDefaultPresets(ref);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkAndShowOnboarding(context);
      _listenNotificationNavigation();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    GenerationNotificationService.instance.updateLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      final service = ref.read(syncServiceProvider).valueOrNull;
      if (service != null && service.status != SyncStatus.syncing) {
        ref.read(syncStatusProvider.notifier).state = service.status;
      }
    }
  }

  void _listenNotificationNavigation() {
    _navSub = GenerationNotificationService.instance.navigationStream.listen(
      (charId) {
        if (mounted) context.push('/chat/$charId');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeSettings = ref.watch(themeProvider);
    final uiFont = ref.watch(uiFontFamilyProvider).valueOrNull;
    final preset = themeSettings.activePreset;
    final mode = preset.themeMode == 'light'
        ? ThemeMode.light
        : preset.themeMode == 'dark'
            ? ThemeMode.dark
            : themeSettings.mode;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Overlay(
        key: toastOverlayKey,
        initialEntries: [
          OverlayEntry(
            builder: (_) => MaterialApp.router(
              title: 'Glaze',
              theme: AppTheme.light(preset, fontFamily: uiFont),
              darkTheme: AppTheme.dark(preset, fontFamily: uiFont),
              themeMode: mode,
              routerConfig: router,
              debugShowCheckedModeBanner: false,
            ),
          ),
          ],
      ),
    );
  }
}
