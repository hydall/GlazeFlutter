import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/image_storage_service.dart';
import '../../../core/models/character.dart';
import '../../../core/models/persona.dart';
import 'naistera_image_provider.dart';
import 'openai_image_provider.dart';
import 'gemini_image_provider.dart';
import 'routmy_image_provider.dart';
import '../image_gen_models.dart';

class ImageGenService {
  final ImageStorageService _imageStorage;

  ImageGenService(this._imageStorage);

  static final _imgGenRegex = RegExp(r'\[IMG:GEN:(.*?)\]');
  static final _imgResultRegex = RegExp(r'\[IMG:RESULT:(.*?)\]');

  bool hasImageGenTags(String text) => _imgGenRegex.hasMatch(text);

  List<Map<String, dynamic>> extractImageGenInstructions(String text) {
    return _imgGenRegex
        .allMatches(text)
        .map((m) {
          try {
            return jsonDecode(m.group(1)!) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{'prompt': m.group(1) ?? ''};
          }
        })
        .toList();
  }

  String replaceTagWithResult(String text, int index, String imagePath) {
    int count = 0;
    return text.replaceAllMapped(_imgGenRegex, (m) {
      if (count++ == index) return '[IMG:RESULT:$imagePath]';
      return m.group(0)!;
    });
  }

  String replaceTagWithError(String text, int index, String error) {
    final encoded = jsonEncode({'error': error});
    int count = 0;
    return text.replaceAllMapped(_imgGenRegex, (m) {
      if (count++ == index) return '[IMG:ERROR:$encoded]';
      return m.group(0)!;
    });
  }

  String resetLoadingTags(String text) {
    return text;
  }

  Future<String> processMessageImages({
    required String text,
    required ImageGenSettings settings,
    required String llmEndpoint,
    required String llmApiKey,
    required String llmModel,
    Character? character,
    Persona? persona,
    List<String>? recentImageContexts,
    void Function(String updatedText)? onUpdate,
  }) async {
    if (!settings.enabled) return text;

    final instructions = extractImageGenInstructions(text);
    if (instructions.isEmpty) return text;

    String currentText = text;

    for (int i = 0; i < instructions.length; i++) {
      final instruction = instructions[i];
      final prompt = instruction['prompt'] as String? ?? '';

      if (prompt.isEmpty) continue;

      try {
        final imageBytes = await generateImage(
          settings: settings,
          prompt: prompt,
          llmEndpoint: llmEndpoint,
          llmApiKey: llmApiKey,
          llmModel: llmModel,
          character: character,
          persona: persona,
          recentImageContexts: recentImageContexts,
        );

        final filename = 'imggen_${DateTime.now().millisecondsSinceEpoch}.png';
        final savedPath = await _saveGeneratedImage(filename, imageBytes);

        currentText = replaceTagWithResult(currentText, i, savedPath);
        onUpdate?.call(currentText);
      } catch (e) {
        debugPrint('IMAGE GEN: failed for prompt "$prompt": $e');
        currentText = replaceTagWithError(currentText, i, e.toString());
        onUpdate?.call(currentText);
      }
    }

    return currentText;
  }

  Future<Uint8List> generateImage({
    required ImageGenSettings settings,
    required String prompt,
    required String llmEndpoint,
    required String llmApiKey,
    required String llmModel,
    Character? character,
    Persona? persona,
    List<String>? recentImageContexts,
  }) async {
    final refs = _buildReferences(
      settings: settings,
      prompt: prompt,
      character: character,
      persona: persona,
      recentImageContexts: recentImageContexts,
    );

    switch (settings.apiType) {
      case ImageGenApiType.openai:
        return _generateOpenai(settings, prompt, llmEndpoint, llmApiKey);
      case ImageGenApiType.gemini:
        return _generateGemini(settings, prompt, llmEndpoint, llmApiKey);
      case ImageGenApiType.naistera:
        return _generateNaistera(settings, prompt, refs);
      case ImageGenApiType.routmy:
        return _generateRoutmy(settings, prompt, llmEndpoint, llmApiKey, llmModel, refs);
    }
  }

  Future<Uint8List> _generateOpenai(
    ImageGenSettings settings, String prompt, String llmEndpoint, String llmApiKey,
  ) async {
    final endpoint = settings.useSameEndpoint ? llmEndpoint : settings.customEndpoint;
    final apiKey = settings.useSameEndpoint ? llmApiKey : settings.customApiKey;
    final model = settings.useSameEndpoint ? 'dall-e-3' : (settings.customModel.isEmpty ? 'dall-e-3' : settings.customModel);

    return OpenaiImageProvider().generate(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      prompt: prompt,
      size: settings.openaiSize,
      quality: settings.openaiQuality,
    );
  }

  Future<Uint8List> _generateGemini(
    ImageGenSettings settings, String prompt, String llmEndpoint, String llmApiKey,
  ) async {
    final endpoint = settings.useSameEndpoint ? llmEndpoint : settings.customEndpoint;
    final apiKey = settings.useSameEndpoint ? llmApiKey : settings.customApiKey;
    final model = settings.useSameEndpoint ? 'imagen-3.0-generate-002' : (settings.customModel.isEmpty ? 'imagen-3.0-generate-002' : settings.customModel);

    return GeminiImageProvider().generate(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      prompt: prompt,
      aspectRatio: settings.geminiAspectRatio,
      imageSize: settings.geminiImageSize,
    );
  }

  Future<Uint8List> _generateNaistera(
    ImageGenSettings settings, String prompt, List<Map<String, String>> refs,
  ) async {
    return NaisteraImageProvider().generate(
      apiKey: settings.naisteraApiKey,
      model: settings.naisteraModel,
      prompt: prompt,
      aspectRatio: settings.naisteraAspectRatio,
      references: refs.isNotEmpty ? refs : null,
    );
  }

  Future<Uint8List> _generateRoutmy(
    ImageGenSettings settings, String prompt,
    String llmEndpoint, String llmApiKey, String llmModel,
    List<Map<String, String>> refs,
  ) async {
    String finalPrompt = prompt;

    try {
      final bridgeDesc = await RoutmyImageProvider().runRuBridge(
        llmEndpoint: llmEndpoint,
        llmApiKey: llmApiKey,
        llmModel: llmModel,
        conversationContext: prompt,
      );
      if (bridgeDesc.isNotEmpty) finalPrompt = bridgeDesc;
    } catch (e) {
      debugPrint('IMAGE GEN: RU Bridge failed, using raw prompt: $e');
    }

    return RoutmyImageProvider().generate(
      apiKey: settings.routmyApiKey,
      model: settings.routmyModel,
      prompt: finalPrompt,
      aspectRatio: settings.routmyAspectRatio,
      imageSize: settings.routmyImageSize,
      quality: settings.routmyQuality,
      references: refs.isNotEmpty ? refs : null,
    );
  }

  List<Map<String, String>> _buildReferences({
    required ImageGenSettings settings,
    required String prompt,
    Character? character,
    Persona? persona,
    List<String>? recentImageContexts,
  }) {
    final refs = <Map<String, String>>[];
    final promptLower = prompt.toLowerCase();

    if (settings.apiType == ImageGenApiType.naistera) {
      if (settings.naisteraSendCharAvatar && character?.avatarPath != null) {
        refs.add({'name': character!.name, 'image': _fileToBase64(character.avatarPath!)});
      }
      if (settings.naisteraSendUserAvatar && persona?.avatarPath != null) {
        refs.add({'name': persona!.name, 'image': _fileToBase64(persona.avatarPath!)});
      }
      for (final ref in settings.additionalReferences) {
        if (ref.matchMode == 'always' || promptLower.contains(ref.name.toLowerCase())) {
          refs.add({'name': ref.name, 'image': _extractBase64FromDataUrl(ref.imageData)});
        }
      }
    }

    if (settings.apiType == ImageGenApiType.routmy) {
      if (settings.routmySendCharAvatar && character?.avatarPath != null) {
        refs.add({'name': character!.name, 'image': _fileToBase64(character.avatarPath!)});
      }
      if (settings.routmySendUserAvatar && persona?.avatarPath != null) {
        refs.add({'name': persona!.name, 'image': _fileToBase64(persona.avatarPath!)});
      }
      for (final ref in settings.routmyAdditionalRefs) {
        if (ref.matchMode == 'always' || promptLower.contains(ref.name.toLowerCase())) {
          refs.add({'name': ref.name, 'image': _extractBase64FromDataUrl(ref.imageData)});
        }
      }
    }

    if (settings.imageContextEnabled && recentImageContexts != null) {
      final count = settings.imageContextCount.clamp(1, 3);
      for (final ctx in recentImageContexts.take(count)) {
        refs.add({'name': 'context', 'image': ctx});
      }
    }

    return refs;
  }

  String _fileToBase64(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return '';
      return base64Encode(file.readAsBytesSync());
    } catch (_) {
      return '';
    }
  }

  String _extractBase64FromDataUrl(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    if (commaIndex == -1) return dataUrl;
    return dataUrl.substring(commaIndex + 1);
  }

  Future<String> _saveGeneratedImage(String filename, Uint8List bytes) async {
    final dir = Directory(p.join(_imageStorage.baseDir, 'generated'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final path = p.join(dir.path, filename);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  static List<String> extractImageResultPaths(String text) {
    return _imgResultRegex
        .allMatches(text)
        .map((m) => m.group(1) ?? '')
        .where((p) => p.isNotEmpty)
        .toList();
  }
}
