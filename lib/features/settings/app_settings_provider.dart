import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/state/shared_prefs_provider.dart';

part 'app_settings_provider.freezed.dart';

final appSettingsProvider = AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
    AppSettingsNotifier.new);

@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(true) bool enterToSend,
    @Default(false) bool hideMessageId,
    @Default(false) bool hideGenerationTime,
    @Default(false) bool hideTokenCount,
    @Default(false) bool groupDialogs,
    @Default(false) bool batterySaver,
    @Default(false) bool hideTooltips,
    @Default(false) bool disableSwipeRegeneration,
    @Default('en') String language,
    @Default(false) bool virtualKeyboardSend,
    @Default(30) double tokenizerHidePercent,
    @Default(85) double tokenizerHistoryFillThreshold,
    @Default(true) bool showOurPicks,
  }) = _AppSettings;
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
