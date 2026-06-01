import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/navigation/router.dart';
import 'core/services/generation_notification_service.dart';
import 'core/state/active_selection_provider.dart';
import 'core/state/lorebook_provider.dart';
import 'core/services/preset_seeder.dart';
import 'features/settings/app_settings_provider.dart';
import 'shared/theme/theme_font_provider.dart';
import 'core/services/onboarding_service.dart';
import 'features/cloud_sync/sync_provider.dart';
import 'features/cloud_sync/sync_models.dart';

import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_provider.dart';

import 'features/chat/widgets/chat_webview_preload.dart';
import 'shared/widgets/glaze_toast.dart' show toastOverlayKey;

class GlazeApp extends ConsumerStatefulWidget {
  final VoidCallback? restart;
  const GlazeApp({super.key, this.restart});

  static VoidCallback? _restart;

  static void restartApp() => _restart?.call();

  @override
  ConsumerState<GlazeApp> createState() => _GlazeAppState();
}

class _GlazeAppState extends ConsumerState<GlazeApp> with WidgetsBindingObserver {
  StreamSubscription<NotificationNavigationData>? _navSub;

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
      _handleColdStartNotification();
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
      (data) {
        if (mounted) context.push('/chat/${data.charId}');
      },
    );
  }

  void _handleColdStartNotification() {
    final data =
        GenerationNotificationService.instance.consumePendingNotificationData();
    if (data != null && mounted) {
      context.push('/chat/${data.charId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppSettings>>(appSettingsProvider, (prev, next) {
      final lang = next.valueOrNull?.language;
      if (lang != null && lang != prev?.valueOrNull?.language) {
        context.setLocale(Locale(lang));
      }
    });

    final router = ref.watch(routerProvider);
    final themeSettings = ref.watch(themeProvider);
    final uiFont = ref.watch(uiFontFamilyProvider).valueOrNull;
    final preset = themeSettings.activePreset;
    final mode = preset.themeMode == 'light'
        ? ThemeMode.light
        : preset.themeMode == 'dark'
            ? ThemeMode.dark
            : themeSettings.mode;
    return MaterialApp.router(
      title: 'Glaze',
      theme: AppTheme.light(preset, fontFamily: uiFont),
      darkTheme: AppTheme.dark(preset, fontFamily: uiFont),
      themeMode: mode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) => ChatWebViewPreloader(
        child: Overlay(
          key: toastOverlayKey,
          initialEntries: [OverlayEntry(builder: (_) => child!)],
        ),
      ),
    );
  }
}
