import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/shared_prefs_provider.dart';

final appSettingsProvider = AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
    AppSettingsNotifier.new);

class AppSettings {
  final bool enterToSend;
  final bool hideMessageId;
  final bool hideGenerationTime;
  final bool hideTokenCount;
  final bool groupDialogs;
  final bool batterySaver;
  final bool hideTooltips;
  final bool disableSwipeRegeneration;
  final String language;
  final bool virtualKeyboardSend;
  final double tokenizerHidePercent;
  final double tokenizerHistoryFillThreshold;
  final bool showOurPicks;

  const AppSettings({
    this.enterToSend = true,
    this.hideMessageId = false,
    this.hideGenerationTime = false,
    this.hideTokenCount = false,
    this.groupDialogs = false,
    this.batterySaver = false,
    this.hideTooltips = false,
    this.disableSwipeRegeneration = false,
    this.language = 'en',
    this.virtualKeyboardSend = false,
    this.tokenizerHidePercent = 30,
    this.tokenizerHistoryFillThreshold = 85,
    this.showOurPicks = true,
  });

  AppSettings copyWith({
    bool? enterToSend,
    bool? hideMessageId,
    bool? hideGenerationTime,
    bool? hideTokenCount,
    bool? groupDialogs,
    bool? batterySaver,
    bool? hideTooltips,
    bool? disableSwipeRegeneration,
    String? language,
    bool? virtualKeyboardSend,
    double? tokenizerHidePercent,
    double? tokenizerHistoryFillThreshold,
    bool? showOurPicks,
  }) {
    return AppSettings(
      enterToSend: enterToSend ?? this.enterToSend,
      hideMessageId: hideMessageId ?? this.hideMessageId,
      hideGenerationTime: hideGenerationTime ?? this.hideGenerationTime,
      hideTokenCount: hideTokenCount ?? this.hideTokenCount,
      groupDialogs: groupDialogs ?? this.groupDialogs,
      batterySaver: batterySaver ?? this.batterySaver,
      hideTooltips: hideTooltips ?? this.hideTooltips,
      disableSwipeRegeneration:
          disableSwipeRegeneration ?? this.disableSwipeRegeneration,
      language: language ?? this.language,
      virtualKeyboardSend: virtualKeyboardSend ?? this.virtualKeyboardSend,
      tokenizerHidePercent: tokenizerHidePercent ?? this.tokenizerHidePercent,
      tokenizerHistoryFillThreshold:
          tokenizerHistoryFillThreshold ?? this.tokenizerHistoryFillThreshold,
      showOurPicks: showOurPicks ?? this.showOurPicks,
    );
  }
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    return AppSettings(
      enterToSend: prefs.getBool('enterToSend') ?? true,
      hideMessageId: prefs.getBool('hideMessageId') ?? false,
      hideGenerationTime: prefs.getBool('hideGenerationTime') ?? false,
      hideTokenCount: prefs.getBool('hideTokenCount') ?? false,
      groupDialogs: prefs.getBool('dialogGrouping') ?? false,
      batterySaver: prefs.getBool('batterySaver') ?? false,
      hideTooltips: prefs.getBool('hideTooltips') ?? false,
      disableSwipeRegeneration:
          prefs.getBool('disableSwipeRegeneration') ?? false,
      language: prefs.getString('language') ?? 'en',
      virtualKeyboardSend: prefs.getBool('virtualKeyboardSend') ?? false,
      tokenizerHidePercent: prefs.getDouble('tokenizerHidePercent') ?? 30,
      tokenizerHistoryFillThreshold: prefs.getDouble('tokenizerHistoryFillThreshold') ?? 85,
      showOurPicks: prefs.getBool('showOurPicks') ?? true,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool('enterToSend', settings.enterToSend);
    await prefs.setBool('hideMessageId', settings.hideMessageId);
    await prefs.setBool('hideGenerationTime', settings.hideGenerationTime);
    await prefs.setBool('hideTokenCount', settings.hideTokenCount);
    await prefs.setBool('dialogGrouping', settings.groupDialogs);
    await prefs.setBool('batterySaver', settings.batterySaver);
    await prefs.setBool('hideTooltips', settings.hideTooltips);
    await prefs.setBool('disableSwipeRegeneration', settings.disableSwipeRegeneration);
    await prefs.setString('language', settings.language);
    await prefs.setBool('virtualKeyboardSend', settings.virtualKeyboardSend);
    await prefs.setDouble('tokenizerHidePercent', settings.tokenizerHidePercent);
    await prefs.setDouble('tokenizerHistoryFillThreshold', settings.tokenizerHistoryFillThreshold);
    await prefs.setBool('showOurPicks', settings.showOurPicks);
    state = AsyncData(settings);
  }
}
