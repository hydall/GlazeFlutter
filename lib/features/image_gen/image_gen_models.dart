import 'package:freezed_annotation/freezed_annotation.dart';

part 'image_gen_models.freezed.dart';

enum ImageGenApiType { openai, gemini, naistera, routmy, ruRoutmy }

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
    @Default('google/gemini-3.1-flash-image-preview') String routmyModel,
    @Default('1:1') String routmyAspectRatio,
    @Default('1K') String routmyImageSize,
    @Default('standard') String routmyQuality,
    @Default(false) bool routmySendCharAvatar,
    @Default(false) bool routmySendUserAvatar,
    @Default([]) List<ReferenceImage> additionalReferences,
    @Default([]) List<ReferenceImage> routmyAdditionalRefs,
    @Default(false) bool imageContextEnabled,
    @Default(1) int imageContextCount,
    @Default('') String ruRoutmyApiKey,
    @Default('google/gemini-3.1-flash-image-preview') String ruRoutmyModel,
    @Default('1:1') String ruRoutmyAspectRatio,
    @Default('1K') String ruRoutmyImageSize,
    @Default('standard') String ruRoutmyQuality,
    @Default(false) bool ruRoutmySendCharAvatar,
    @Default(false) bool ruRoutmySendUserAvatar,
  }) = _ImageGenSettings;
}

class RoutMyConstants {
  static const String baseUrl = 'https://api.rout.my';

  static const models = [
    ('google/gemini-3.1-flash-image-preview', 'Gemini 3.1 Flash Image'),
    ('openai/gpt-image-1.5', 'GPT Image 1.5'),
    ('openai/gpt-image-2', 'GPT Image 2'),
    ('x-ai/grok-imagine-image', 'Grok Imagine Image'),
    ('x-ai/grok-imagine-image-pro', 'Grok Imagine Image Pro'),
    ('recraft/recraft-v4.1', 'Recraft V4.1'),
    ('recraft/recraft-v4.1-utility', 'Recraft V4.1 Utility'),
  ];

  static const aspectRatios = [
    '1:1', '2:3', '3:2', '3:4', '4:3', '4:5', '5:4', '9:16', '16:9', '21:9',
  ];

  static const imageSizes = ['1K', '2K', '4K'];
}

class RuRoutMyConstants {
  static const String baseUrl = 'https://ru-api.rout.my';

  static const models = RoutMyConstants.models;
  static const aspectRatios = RoutMyConstants.aspectRatios;
  static const imageSizes = RoutMyConstants.imageSizes;
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
