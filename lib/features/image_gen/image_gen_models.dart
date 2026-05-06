import 'package:freezed_annotation/freezed_annotation.dart';

part 'image_gen_models.freezed.dart';

enum ImageGenApiType { openai, gemini, naistera, routmy }

@freezed
class ReferenceImage with _$ReferenceImage {
  const factory ReferenceImage({
    required String name,
    required String imageData,
    @Default('match') String matchMode,
  }) = _ReferenceImage;
}

@freezed
class ImageGenSettings with _$ImageGenSettings {
  const factory ImageGenSettings({
    @Default(false) bool enabled,
    @Default(ImageGenApiType.openai) ImageGenApiType apiType,
    @Default(true) bool useSameEndpoint,
    @Default('') String customEndpoint,
    @Default('') String customApiKey,
    @Default('') String customModel,
    @Default('1024x1024') String openaiSize,
    @Default('standard') String openaiQuality,
    @Default('1:1') String geminiAspectRatio,
    @Default('1K') String geminiImageSize,
    @Default('') String naisteraApiKey,
    @Default('grok') String naisteraModel,
    @Default('1:1') String naisteraAspectRatio,
    @Default(false) bool naisteraSendCharAvatar,
    @Default(false) bool naisteraSendUserAvatar,
    @Default('') String routmyApiKey,
    @Default('flux-1.1-pro') String routmyModel,
    @Default('1:1') String routmyAspectRatio,
    @Default('1K') String routmyImageSize,
    @Default('standard') String routmyQuality,
    @Default(false) bool routmySendCharAvatar,
    @Default(false) bool routmySendUserAvatar,
    @Default([]) List<ReferenceImage> additionalReferences,
    @Default([]) List<ReferenceImage> routmyAdditionalRefs,
    @Default(false) bool imageContextEnabled,
    @Default(1) int imageContextCount,
  }) = _ImageGenSettings;
}

class RoutMyConstants {
  static const models = [
    ('flux-1.1-pro', 'Flux 1.1 Pro'),
    ('flux-1.1-pro-ultra', 'Flux 1.1 Pro Ultra'),
    ('flux-1-schnell', 'Flux 1 Schnell'),
    ('flux-1-dev', 'Flux 1 Dev'),
    ('ideogram-2', 'Ideogram 2'),
    ('recraft-v3', 'Recraft V3'),
    ('recraft-v3-svg', 'Recraft V3 SVG'),
    ('sdxl', 'SDXL'),
    ('stable-diffusion-3', 'Stable Diffusion 3'),
    ('playground-v2.5', 'Playground V2.5'),
  ];

  static const aspectRatios = [
    '1:1', '16:9', '9:16', '4:3', '3:4', '3:2', '2:3', '21:9', '9:21',
  ];

  static const imageSizes = ['1K', '2K', '4K'];
}

class NaisteraConstants {
  static const models = [
    ('grok', 'Grok'),
    ('grok-pro', 'Grok Pro'),
    ('nano banana', 'Nano Banana'),
    ('novelai', 'NovelAI'),
  ];

  static const aspectRatios = ['1:1', '16:9', '9:16', '3:2', '2:3'];

  static const noRefModels = {'grok-pro', 'novelai'};
}

class OpenAIConstants {
  static const sizes = ['1024x1024', '1792x1024', '1024x1792', '512x512'];
  static const qualities = ['standard', 'hd'];
}

class GeminiConstants {
  static const aspectRatios = [
    '1:1', '9:16', '16:9', '3:4', '4:3', '2:3', '3:2',
  ];
  static const imageSizes = ['1K', '2K', '4K'];
}
