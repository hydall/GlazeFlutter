import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/image_gen_patterns.dart';
import '../../../core/services/image_storage_service.dart';
import '../../../core/utils/platform_paths.dart';
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

  bool hasImageGenTags(String text) {
    if (ImgGenPatterns.htmlIigTagRegex.hasMatch(text) || ImgGenPatterns.htmlIigTagDoubleRegex.hasMatch(text)) return true;
    final stripped = ImgGenPatterns.stripHtmlImgTags(text);
    return ImgGenPatterns.imgGenRegex.hasMatch(stripped);
  }

  List<Map<String, dynamic>> extractImageGenInstructions(String text) {
    final results = <Map<String, dynamic>>[];

    for (final m in ImgGenPatterns.htmlIigTagRegex.allMatches(text)) {
      final payload = m.group(1);
      if (payload == null || payload.isEmpty) continue;
      try {
        results.add(jsonDecode(payload) as Map<String, dynamic>);
      } catch (_) {
        results.add(<String, dynamic>{'prompt': payload});
      }
    }

    for (final m in ImgGenPatterns.htmlIigTagDoubleRegex.allMatches(text)) {
      final payload = m.group(1);
      if (payload == null || payload.isEmpty) continue;
      try {
        results.add(jsonDecode(payload) as Map<String, dynamic>);
      } catch (_) {
        results.add(<String, dynamic>{'prompt': payload});
      }
    }

    final stripped = ImgGenPatterns.stripHtmlImgTags(text);
    for (final m in ImgGenPatterns.imgGenRegex.allMatches(stripped)) {
      final payload = m.group(1);
      if (payload == null || payload.isEmpty) {
        results.add(<String, dynamic>{'prompt': ''});
        continue;
      }
      try {
        results.add(jsonDecode(payload) as Map<String, dynamic>);
      } catch (_) {
        results.add(<String, dynamic>{'prompt': payload});
      }
    }

    return results;
  }

  String replaceTagWithResult(String text, int index, String imagePath) {
    final instructions = extractImageGenInstructions(text);
    final instruction = index < instructions.length ? instructions[index] : null;
    final instrJson = instruction != null && instruction.isNotEmpty ? jsonEncode(instruction) : '';
    final payload = instrJson.isNotEmpty ? '$imagePath|$instrJson' : imagePath;
    int count = 0;
    var result = text.replaceAllMapped(ImgGenPatterns.htmlIigTagRegex, (m) {
      if (count++ == index) return '[IMG:RESULT:$payload]';
      return m.group(0)!;
    });
    result = result.replaceAllMapped(ImgGenPatterns.htmlIigTagDoubleRegex, (m) {
      if (count++ == index) return '[IMG:RESULT:$payload]';
      return m.group(0)!;
    });
    final stripped = ImgGenPatterns.stripHtmlImgTags(result);
    final needStrip = stripped != result;
    result = result.replaceAllMapped(ImgGenPatterns.imgGenRegex, (m) {
      if (count++ == index) return '[IMG:RESULT:$payload]';
      return m.group(0)!;
    });
    if (count <= index) return text;
    return needStrip ? ImgGenPatterns.stripHtmlImgTags(result) : result;
  }

  String replaceTagWithError(String text, int index, String error) {
    final instructions = extractImageGenInstructions(text);
    final instructionJson = index < instructions.length ? jsonEncode(instructions[index]) : '';
    final encoded = jsonEncode({'error': error, if (instructionJson.isNotEmpty) 'instruction': instructionJson});
    int count = 0;
    var result = text.replaceAllMapped(ImgGenPatterns.htmlIigTagRegex, (m) {
      if (count++ == index) return '[IMG:ERROR:$encoded]';
      return m.group(0)!;
    });
    result = result.replaceAllMapped(ImgGenPatterns.htmlIigTagDoubleRegex, (m) {
      if (count++ == index) return '[IMG:ERROR:$encoded]';
      return m.group(0)!;
    });
    final stripped = ImgGenPatterns.stripHtmlImgTags(result);
    final needStrip = stripped != result;
    result = result.replaceAllMapped(ImgGenPatterns.imgGenRegex, (m) {
      if (count++ == index) return '[IMG:ERROR:$encoded]';
      return m.group(0)!;
    });
    if (count <= index) return text;
    return needStrip ? ImgGenPatterns.stripHtmlImgTags(result) : result;
  }

  String resetErrorTags(String text) {
    var result = text.replaceAllMapped(ImgGenPatterns.imgErrorRegex, (m) {
      try {
        final json = jsonDecode(m.group(1)!) as Map<String, dynamic>;
        final instruction = json['instruction'] as String?;
        if (instruction != null && instruction.isNotEmpty) {
          return '[IMG:GEN:$instruction]';
        }
      } catch (_) {}
      return '[IMG:GEN]';
    });
    result = result.replaceAllMapped(ImgGenPatterns.imgResultRegex, (m) {
      final raw = m.group(1) ?? '';
      final pipeIdx = raw.indexOf('|');
      final instr = pipeIdx != -1 ? raw.substring(pipeIdx + 1) : null;
      if (instr != null && instr.isNotEmpty) {
        return '[IMG:GEN:$instr]';
      }
      return '[IMG:GEN]';
    });
    return result;
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
    CancelToken? cancelToken,
    void Function(String updatedText)? onUpdate,
    void Function(String error)? onError,
  }) async {
    if (!settings.enabled) return text;

    final instructions = extractImageGenInstructions(text);
    if (instructions.isEmpty) return text;

    String currentText = text;

    for (int i = 0; i < instructions.length; i++) {
      if (cancelToken?.isCancelled == true) break;

      final instruction = instructions[i];
      final rawPrompt = instruction['prompt'] as String? ?? '';

      if (rawPrompt.isEmpty) continue;

      final style = instruction['style'] as String? ?? '';
      var cleanPrompt = rawPrompt.replaceFirst(RegExp(r'^SCENE_PROMPT:\s*'), '');
      final prompt = style.isNotEmpty ? '$style, $cleanPrompt' : cleanPrompt;
      final instructionAspectRatio = instruction['aspect_ratio'] as String?;
      final instructionImageSize = instruction['image_size'] as String?;

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
          instructionAspectRatio: instructionAspectRatio,
          instructionImageSize: instructionImageSize,
          cancelToken: cancelToken,
        );

        final filename = 'imggen_${DateTime.now().millisecondsSinceEpoch}.png';
        final savedPath = await _saveGeneratedImage(filename, imageBytes);

        currentText = replaceTagWithResult(currentText, i, savedPath);
        onUpdate?.call(currentText);
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) break;
        debugPrint('IMAGE GEN: failed for prompt "$prompt": $e');
        final errorMsg = _formatError(e);
        currentText = replaceTagWithError(currentText, i, errorMsg);
        onUpdate?.call(currentText);
        onError?.call(errorMsg);
      } catch (e) {
        debugPrint('IMAGE GEN: failed for prompt "$prompt": $e');
        final errorMsg = _formatErrorString(e.toString());
        currentText = replaceTagWithError(currentText, i, errorMsg);
        onUpdate?.call(currentText);
        onError?.call(errorMsg);
      }
    }

    return currentText;
  }

  String _formatError(DioException e) {
    final msg = e.message ?? e.toString();
    return _formatErrorString(msg);
  }

  String _formatErrorString(String msg) {
    if (msg.length > 200) msg = '${msg.substring(0, 197)}...';
    return msg;
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
    String? instructionAspectRatio,
    String? instructionImageSize,
    CancelToken? cancelToken,
  }) async {
    final isRoutmy = settings.apiType == ImageGenApiType.routmy ||
        settings.apiType == ImageGenApiType.ruRoutmy;
    final refs = isRoutmy
        ? await _buildRoutmyRefs(
            settings: settings,
            prompt: prompt,
            character: character,
            persona: persona,
            recentImageContexts: recentImageContexts,
          )
        : _buildReferences(
            settings: settings,
            prompt: prompt,
            character: character,
            persona: persona,
            recentImageContexts: recentImageContexts,
          );

    switch (settings.apiType) {
      case ImageGenApiType.openai:
        return _generateOpenai(settings, prompt, llmEndpoint, llmApiKey, cancelToken);
      case ImageGenApiType.gemini:
        return _generateGemini(settings, prompt, llmEndpoint, llmApiKey, cancelToken);
      case ImageGenApiType.naistera:
        return _generateNaistera(settings, prompt, refs, cancelToken);
      case ImageGenApiType.routmy:
        return _generateRoutmy(settings, prompt, refs, cancelToken);
      case ImageGenApiType.ruRoutmy:
        return _generateRuRoutmy(settings, prompt, refs, cancelToken);
    }
  }

  Future<Uint8List> _generateOpenai(
    ImageGenSettings settings, String prompt, String llmEndpoint, String llmApiKey, CancelToken? cancelToken,
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
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> _generateGemini(
    ImageGenSettings settings, String prompt, String llmEndpoint, String llmApiKey, CancelToken? cancelToken,
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
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> _generateNaistera(
    ImageGenSettings settings, String prompt, List<Map<String, String>> refs, CancelToken? cancelToken,
  ) async {
    return NaisteraImageProvider().generate(
      apiKey: settings.naisteraApiKey,
      model: settings.naisteraModel,
      prompt: prompt,
      aspectRatio: settings.naisteraAspectRatio,
      references: refs.isNotEmpty ? refs : null,
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> _generateRoutmy(
    ImageGenSettings settings, String prompt,
    List<Map<String, String>> refs, CancelToken? cancelToken,
  ) async {
    return RoutmyImageProvider(baseUrl: RoutMyConstants.baseUrl).generate(
      apiKey: settings.routmyApiKey,
      model: settings.routmyModel,
      prompt: prompt,
      aspectRatio: settings.routmyAspectRatio,
      imageSize: settings.routmyImageSize,
      quality: settings.routmyQuality,
      referenceImages: refs.isNotEmpty ? refs.map((r) => r['image']!).where((s) => s.isNotEmpty).toList() : null,
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> _generateRuRoutmy(
    ImageGenSettings settings, String prompt,
    List<Map<String, String>> refs, CancelToken? cancelToken,
  ) async {
    return RoutmyImageProvider(baseUrl: RuRoutMyConstants.baseUrl).generate(
      apiKey: settings.ruRoutmyApiKey,
      model: settings.ruRoutmyModel,
      prompt: prompt,
      aspectRatio: settings.ruRoutmyAspectRatio,
      imageSize: settings.ruRoutmyImageSize,
      quality: settings.ruRoutmyQuality,
      referenceImages: refs.isNotEmpty ? refs.map((r) => r['image']!).where((s) => s.isNotEmpty).toList() : null,
      cancelToken: cancelToken,
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

    // routmy / ruRoutmy refs are built asynchronously (resized) — see _buildRoutmyRefs
    

    if (settings.imageContextEnabled && recentImageContexts != null) {
      final count = settings.imageContextCount.clamp(1, 3);
      for (final ctx in recentImageContexts.take(count)) {
        final path = normalizeImageResultPayload(ctx);
        final encoded = _fileToBase64(path);
        if (encoded.isNotEmpty) {
          refs.add({'name': 'context', 'image': encoded});
        }
      }
    }

    return refs;
  }

  /// Async variant of [_buildReferences] for routmy/ruRoutmy.
  /// Resizes avatar/context images to 512px before base64-encoding so that
  /// the JSON payload stays within provider limits.
  Future<List<Map<String, String>>> _buildRoutmyRefs({
    required ImageGenSettings settings,
    required String prompt,
    Character? character,
    Persona? persona,
    List<String>? recentImageContexts,
  }) async {
    final refs = <Map<String, String>>[];
    final promptLower = prompt.toLowerCase();
    final isRu = settings.apiType == ImageGenApiType.ruRoutmy;

    final sendChar = isRu ? settings.ruRoutmySendCharAvatar : settings.routmySendCharAvatar;
    final sendUser = isRu ? settings.ruRoutmySendUserAvatar : settings.routmySendUserAvatar;

    if (sendChar && character?.avatarPath != null) {
      final img = await _fileToBase64Resized(character!.avatarPath!);
      if (img.isNotEmpty) refs.add({'name': character.name, 'image': img});
    }
    if (sendUser && persona?.avatarPath != null) {
      final img = await _fileToBase64Resized(persona!.avatarPath!);
      if (img.isNotEmpty) refs.add({'name': persona.name, 'image': img});
    }
    for (final ref in settings.routmyAdditionalRefs) {
      if (ref.matchMode == 'always' || promptLower.contains(ref.name.toLowerCase())) {
        final raw = _extractBase64FromDataUrl(ref.imageData);
        if (raw.isNotEmpty) refs.add({'name': ref.name, 'image': raw});
      }
    }

    if (settings.imageContextEnabled && recentImageContexts != null) {
      final count = settings.imageContextCount.clamp(1, 3);
      for (final ctx in recentImageContexts.take(count)) {
        final path = normalizeImageResultPayload(ctx);
        final encoded = await _fileToBase64Resized(path);
        if (encoded.isNotEmpty) refs.add({'name': 'context', 'image': encoded});
      }
    }

    return refs;
  }

  String _fileToBase64(String path) {
    try {
      final resolved = resolveGlazeFilePath(path) ?? path;
      final file = File(resolved);
      if (!file.existsSync()) return '';
      return base64Encode(file.readAsBytesSync());
    } catch (_) {
      return '';
    }
  }

  /// Reads an image file, resizes it so the longest side is at most [maxSide]
  /// pixels, re-encodes as PNG, and returns base64. Falls back to the raw
  /// file bytes if decoding fails. Keeps refs small for API payloads.
  Future<String> _fileToBase64Resized(String path, {int maxSide = 512}) async {
    try {
      final resolved = resolveGlazeFilePath(path) ?? path;
      final file = File(resolved);
      if (!file.existsSync()) return '';
      final bytes = file.readAsBytesSync();

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: maxSide,
        targetHeight: maxSide,
      );
      final frame = await codec.getNextFrame();
      final pngData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();

      if (pngData == null) return base64Encode(bytes);
      final resizedBytes = pngData.buffer.asUint8List();
      debugPrint('ROUTMY ref resize: ${bytes.length} → ${resizedBytes.length} bytes');
      return base64Encode(resizedBytes);
    } catch (e) {
      debugPrint('ROUTMY ref resize failed: $e');
      return _fileToBase64(path);
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
    return ImgGenPatterns.imgResultRegex
        .allMatches(text)
        .map((m) => normalizeImageResultPayload(m.group(1) ?? ''))
        .where((p) => p.isNotEmpty)
        .toList();
  }

  /// Strips optional `|instructionJson` suffix from [IMG:RESULT:…] payloads.
  static String normalizeImageResultPayload(String payload) {
    final pipeIdx = payload.indexOf('|');
    return pipeIdx != -1 ? payload.substring(0, pipeIdx) : payload;
  }

  /// [contentsNewestFirst] — text blobs ordered newest → oldest (e.g. ext-block bodies).
  static List<String> collectRecentImageResultPaths(
    Iterable<String> contentsNewestFirst, {
    int maxPaths = 3,
  }) {
    final collected = <String>[];
    for (final content in contentsNewestFirst) {
      if (collected.length >= maxPaths) break;
      for (final path in extractImageResultPaths(content)) {
        if (collected.length >= maxPaths) break;
        collected.add(path);
      }
    }
    return collected.reversed.toList();
  }

  /// Reads image instructions from pending [IMG:GEN] tags or finished
  /// [IMG:RESULT:path|json] tokens inside ext-block HTML.
  List<Map<String, dynamic>> extractInstructionsFromImageContent(String text) {
    final fromGen = extractImageGenInstructions(text);
    if (fromGen.isNotEmpty) return fromGen;

    final fromResult = <Map<String, dynamic>>[];
    for (final match in ImgGenPatterns.imgResultRegex.allMatches(text)) {
      final raw = match.group(1) ?? '';
      final pipeIdx = raw.indexOf('|');
      if (pipeIdx < 0 || pipeIdx >= raw.length - 1) continue;
      try {
        fromResult.add(
          jsonDecode(raw.substring(pipeIdx + 1)) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return fromResult;
  }

  /// Replaces the [index]-th [IMG:RESULT:…] token, preserving instruction JSON.
  String replaceExtBlockImageResult(
    String text,
    String newPath, {
    int index = 0,
  }) {
    var count = 0;
    return text.replaceAllMapped(ImgGenPatterns.imgResultRegex, (match) {
      if (count++ != index) return match.group(0)!;
      final raw = match.group(1)!;
      final pipeIdx = raw.indexOf('|');
      final suffix = pipeIdx != -1 ? raw.substring(pipeIdx) : '';
      return '[IMG:RESULT:$newPath$suffix]';
    });
  }
}
