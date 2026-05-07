import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/state/db_provider.dart';
import 'image_gen_models.dart';
import 'services/image_gen_service.dart';

final imageGenSettingsProvider =
    AsyncNotifierProvider<ImageGenSettingsNotifier, ImageGenSettings>(
  ImageGenSettingsNotifier.new,
);

class ImageGenSettingsNotifier extends AsyncNotifier<ImageGenSettings> {
  static const _key = 'gz_imggen_settings';

  @override
  Future<ImageGenSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const ImageGenSettings();
    try {
      return _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ImageGenSettings();
    }
  }

  Future<void> save(ImageGenSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_toJson(settings)));
  }

  Future<void> updateEnabled(bool enabled) async {
    final s = state.value ?? const ImageGenSettings();
    await save(s.copyWith(enabled: enabled));
  }

  Future<void> updateApiType(ImageGenApiType apiType) async {
    final s = state.value ?? const ImageGenSettings();
    await save(s.copyWith(apiType: apiType));
  }

  ImageGenService? _service;
  ImageGenService getService() {
    if (_service != null) return _service!;
    final storage = ref.read(imageStorageProvider).value;
    if (storage == null) throw StateError('ImageStorageService not ready');
    _service = ImageGenService(storage);
    return _service!;
  }

  Map<String, dynamic> _toJson(ImageGenSettings s) => {
    'enabled': s.enabled,
    'apiType': s.apiType.name,
    'useSameEndpoint': s.useSameEndpoint,
    'customEndpoint': s.customEndpoint,
    'customApiKey': s.customApiKey,
    'customModel': s.customModel,
    'openaiSize': s.openaiSize,
    'openaiQuality': s.openaiQuality,
    'geminiAspectRatio': s.geminiAspectRatio,
    'geminiImageSize': s.geminiImageSize,
    'naisteraApiKey': s.naisteraApiKey,
    'naisteraModel': s.naisteraModel,
    'naisteraAspectRatio': s.naisteraAspectRatio,
    'naisteraSendCharAvatar': s.naisteraSendCharAvatar,
    'naisteraSendUserAvatar': s.naisteraSendUserAvatar,
    'routmyApiKey': s.routmyApiKey,
    'routmyModel': s.routmyModel,
    'routmyAspectRatio': s.routmyAspectRatio,
    'routmyImageSize': s.routmyImageSize,
    'routmyQuality': s.routmyQuality,
    'routmySendCharAvatar': s.routmySendCharAvatar,
    'routmySendUserAvatar': s.routmySendUserAvatar,
    'imageContextEnabled': s.imageContextEnabled,
    'imageContextCount': s.imageContextCount,
    'additionalReferences': s.additionalReferences.map((r) => {
      'name': r.name, 'imageData': r.imageData, 'matchMode': r.matchMode,
    }).toList(),
    'routmyAdditionalRefs': s.routmyAdditionalRefs.map((r) => {
      'name': r.name, 'imageData': r.imageData, 'matchMode': r.matchMode,
    }).toList(),
    'ruRoutmyApiKey': s.ruRoutmyApiKey,
    'ruRoutmyModel': s.ruRoutmyModel,
    'ruRoutmyAspectRatio': s.ruRoutmyAspectRatio,
    'ruRoutmyImageSize': s.ruRoutmyImageSize,
    'ruRoutmyQuality': s.ruRoutmyQuality,
    'ruRoutmySendCharAvatar': s.ruRoutmySendCharAvatar,
    'ruRoutmySendUserAvatar': s.ruRoutmySendUserAvatar,
  };

  ImageGenSettings _fromJson(Map<String, dynamic> m) => ImageGenSettings(
    enabled: m['enabled'] as bool? ?? false,
    apiType: _parseApiType(m['apiType'] as String?),
    useSameEndpoint: m['useSameEndpoint'] as bool? ?? true,
    customEndpoint: m['customEndpoint'] as String? ?? '',
    customApiKey: m['customApiKey'] as String? ?? '',
    customModel: m['customModel'] as String? ?? '',
    openaiSize: m['openaiSize'] as String? ?? '1024x1024',
    openaiQuality: m['openaiQuality'] as String? ?? 'standard',
    geminiAspectRatio: m['geminiAspectRatio'] as String? ?? '1:1',
    geminiImageSize: m['geminiImageSize'] as String? ?? '1K',
    naisteraApiKey: m['naisteraApiKey'] as String? ?? '',
    naisteraModel: m['naisteraModel'] as String? ?? 'grok',
    naisteraAspectRatio: m['naisteraAspectRatio'] as String? ?? '1:1',
    naisteraSendCharAvatar: m['naisteraSendCharAvatar'] as bool? ?? false,
    naisteraSendUserAvatar: m['naisteraSendUserAvatar'] as bool? ?? false,
    routmyApiKey: m['routmyApiKey'] as String? ?? '',
    routmyModel: m['routmyModel'] as String? ?? 'google/gemini-3.1-flash-image-preview',
    routmyAspectRatio: m['routmyAspectRatio'] as String? ?? '1:1',
    routmyImageSize: m['routmyImageSize'] as String? ?? '1K',
    routmyQuality: m['routmyQuality'] as String? ?? 'standard',
    routmySendCharAvatar: m['routmySendCharAvatar'] as bool? ?? false,
    routmySendUserAvatar: m['routmySendUserAvatar'] as bool? ?? false,
    imageContextEnabled: m['imageContextEnabled'] as bool? ?? false,
    imageContextCount: m['imageContextCount'] as int? ?? 1,
    additionalReferences: _parseRefs(m['additionalReferences']),
    routmyAdditionalRefs: _parseRefs(m['routmyAdditionalRefs']),
    ruRoutmyApiKey: m['ruRoutmyApiKey'] as String? ?? '',
    ruRoutmyModel: m['ruRoutmyModel'] as String? ?? 'google/gemini-3.1-flash-image-preview',
    ruRoutmyAspectRatio: m['ruRoutmyAspectRatio'] as String? ?? '1:1',
    ruRoutmyImageSize: m['ruRoutmyImageSize'] as String? ?? '1K',
    ruRoutmyQuality: m['ruRoutmyQuality'] as String? ?? 'standard',
    ruRoutmySendCharAvatar: m['ruRoutmySendCharAvatar'] as bool? ?? false,
    ruRoutmySendUserAvatar: m['ruRoutmySendUserAvatar'] as bool? ?? false,
  );

  static ImageGenApiType _parseApiType(String? v) {
    switch (v) {
      case 'gemini': return ImageGenApiType.gemini;
      case 'naistera': return ImageGenApiType.naistera;
      case 'routmy': return ImageGenApiType.routmy;
      case 'ruRoutmy': return ImageGenApiType.ruRoutmy;
      default: return ImageGenApiType.openai;
    }
  }

  static List<ReferenceImage> _parseRefs(dynamic v) {
    if (v is! List) return [];
    return v.map((e) {
      final m = e as Map<String, dynamic>;
      return ReferenceImage(
        name: m['name'] as String? ?? '',
        imageData: m['imageData'] as String? ?? '',
        matchMode: m['matchMode'] as String? ?? 'match',
      );
    }).toList();
  }
}
