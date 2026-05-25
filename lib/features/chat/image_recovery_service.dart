import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/image_gen_patterns.dart';
import '../../core/models/chat_message.dart';
import '../../core/state/db_provider.dart';
import '../../core/utils/time_helpers.dart';
import '../image_gen/image_gen_provider.dart';
import 'chat_generation_service.dart';
import 'chat_state.dart';

class ImageRecoveryService {
  final Ref _ref;
  final String _charId;
  final void Function(CancelToken?) _setImgGenCancelToken;
  final void Function(AsyncValue<ChatState>) _setState;
  final AsyncValue<ChatState> Function() _getState;

  ImageRecoveryService({
    required Ref ref,
    required String charId,
    required void Function(CancelToken?) setImgGenCancelToken,
    required void Function(AsyncValue<ChatState>) setState,
    required AsyncValue<ChatState> Function() getState,
  }) : _ref = ref, _charId = charId, _setImgGenCancelToken = setImgGenCancelToken,
       _setState = setState, _getState = getState;

  static ChatSession fixupSwipesWithImageResults(ChatSession session) {
    bool changed = false;
    final messages = List<ChatMessage>.from(session.messages);
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      var currentMsg = msg;

      if (msg.swipes.isNotEmpty) {
        final swipeIdx = msg.swipeId;
        if (swipeIdx >= 0 && swipeIdx < msg.swipes.length && msg.content != msg.swipes[swipeIdx]) {
          final fixedSwipes = List<String>.from(msg.swipes);
          fixedSwipes[swipeIdx] = msg.content;
          currentMsg = msg.copyWith(swipes: fixedSwipes);
          changed = true;
        }
      }

      final cleanedContent = cleanStuckImgGenTags(currentMsg.content);
      if (cleanedContent != currentMsg.content) {
        currentMsg = currentMsg.copyWith(content: cleanedContent);
        changed = true;
      }

      if (currentMsg.swipes.isNotEmpty) {
        final fixedSwipes = List<String>.from(currentMsg.swipes);
        bool swipesChanged = false;
        for (int s = 0; s < fixedSwipes.length; s++) {
          final cleaned = cleanStuckImgGenTags(fixedSwipes[s]);
          if (cleaned != fixedSwipes[s]) {
            fixedSwipes[s] = cleaned;
            swipesChanged = true;
          }
        }
        if (swipesChanged) {
          currentMsg = currentMsg.copyWith(swipes: fixedSwipes);
          changed = true;
        }
      }

      messages[i] = currentMsg;
    }
    if (!changed) return session;
    return session.copyWith(messages: messages);
  }

  static String cleanStuckImgGenTags(String text) {
    if (!ImgGenPatterns.imgGenRegex.hasMatch(text) && !ImgGenPatterns.htmlIigTagRegex.hasMatch(text) && !ImgGenPatterns.htmlIigTagDoubleRegex.hasMatch(text) && !ImgGenPatterns.imgSrcGenRegex.hasMatch(text)) return text;
    var result = text;
    result = result.replaceAll(ImgGenPatterns.imgSrcGenRegex, '[IMG:ERROR:${jsonEncode({'error': 'Generation interrupted'})}]');
    result = result.replaceAllMapped(ImgGenPatterns.htmlIigTagRegex, (m) {
      final instruction = m.group(1) ?? '';
      final errorJson = jsonEncode({'error': 'Generation interrupted', 'instruction': instruction});
      return '[IMG:ERROR:$errorJson]';
    });
    result = result.replaceAllMapped(ImgGenPatterns.htmlIigTagDoubleRegex, (m) {
      final instruction = m.group(1) ?? '';
      final errorJson = jsonEncode({'error': 'Generation interrupted', 'instruction': instruction});
      return '[IMG:ERROR:$errorJson]';
    });
    result = result.replaceAllMapped(ImgGenPatterns.imgGenRegex, (m) {
      final instruction = m.group(1) ?? '';
      final errorJson = instruction.isNotEmpty
          ? jsonEncode({'error': 'Generation interrupted', 'instruction': instruction})
          : jsonEncode({'error': 'Generation interrupted'});
      return '[IMG:ERROR:$errorJson]';
    });
    return result;
  }

  static String replaceFirstImgErrorOrGen(String text, String resultPath) {
    if (ImgGenPatterns.imgErrorRegex.hasMatch(text)) {
      return text.replaceFirst(ImgGenPatterns.imgErrorRegex, '[IMG:RESULT:$resultPath]');
    }
    if (ImgGenPatterns.imgGenHtmlRegex.hasMatch(text)) {
      return text.replaceFirst(ImgGenPatterns.imgGenHtmlRegex, '[IMG:RESULT:$resultPath]');
    }
    if (text.contains('[IMG:GEN]')) {
      return text.replaceFirst('[IMG:GEN]', '[IMG:RESULT:$resultPath]');
    }
    if (ImgGenPatterns.imgGenRegex.hasMatch(text)) {
      return text.replaceFirst(ImgGenPatterns.imgGenRegex, '[IMG:RESULT:$resultPath]');
    }
    return text;
  }

  static String resetImgTagsToGen(String text) {
    var result = text;
    result = result.replaceAllMapped(ImgGenPatterns.imgErrorRegex, (m) {
      final data = m.group(1) ?? '';
      String instruction = '';
      try {
        final parsed = jsonDecode(data);
        instruction = (parsed['instruction'] ?? '') as String;
      } catch (_) {}
      if (instruction.isNotEmpty) {
        return '[IMG:GEN:$instruction]';
      }
      return '[IMG:GEN]';
    });
    result = result.replaceAllMapped(ImgGenPatterns.imgResultRegex, (m) {
      final raw = m.group(1) ?? '';
      final pipeIdx = raw.indexOf('|');
      final instr = pipeIdx != -1 ? raw.substring(pipeIdx + 1) : '';
      if (instr.isNotEmpty) {
        return '[IMG:GEN:$instr]';
      }
      return '[IMG:GEN]';
    });
    return result;
  }

  Future<void> retryImageGeneration() async {
    final current = _getState().value;
    if (current == null || current.session == null) return;
    if (current.isGeneratingImage) return;

    final session = current.session!;
    final lastIdx = session.messages.length - 1;
    if (lastIdx < 0) return;
    final lastMsg = session.messages[lastIdx];
    if (lastMsg.role != 'assistant') return;

    final notifier = _ref.read(imageGenSettingsProvider.notifier);
    final service = await notifier.getServiceAsync();

    final hasRetryableContent = service.hasImageGenTags(lastMsg.content)
        || lastMsg.content.contains('[IMG:ERROR:')
        || lastMsg.content.contains('[IMG:RESULT:');
    if (!hasRetryableContent) return;

    final resetContent = service.resetErrorTags(lastMsg.content);
    if (resetContent == lastMsg.content && !service.hasImageGenTags(resetContent)) return;

    final newMessages = List<ChatMessage>.from(session.messages);
    final swipeIdx = lastMsg.swipeId;
    final updatedSwipes = lastMsg.swipes.isNotEmpty && swipeIdx >= 0 && swipeIdx < lastMsg.swipes.length
        ? (List<String>.from(lastMsg.swipes)..[swipeIdx] = resetContent)
        : lastMsg.swipes;
    newMessages[lastIdx] = lastMsg.copyWith(content: resetContent, swipes: updatedSwipes);
    final resetSession = session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    _setState(AsyncData(current.copyWith(session: resetSession, isGeneratingImage: true)));

    final imgCancelToken = CancelToken();
    _setImgGenCancelToken(imgCancelToken);

    final genService = ChatGenerationService(_ref);
    await genService.processImageTags(
      currentState: _getState().value!,
      charId: _charId,
      cancelToken: imgCancelToken,
      onStateUpdate: (s) { _setState(AsyncData(s)); },
    );

    _setImgGenCancelToken(null);
  }

  Future<void> retryImageGenerationForMessage(int messageIndex) async {
    final current = _getState().value;
    if (current == null || current.session == null || current.isGenerating || current.isGeneratingImage) {
      return;
    }
    if (messageIndex < 0 || messageIndex >= current.messages.length) return;

    final msg = current.messages[messageIndex];
    if (msg.role != 'assistant') return;

    var resetContent = resetImgTagsToGen(msg.content);
    if (resetContent == msg.content) return;

    final swipeIdx = msg.swipeId;
    final updatedSwipes = List<String>.from(msg.swipes);
    if (swipeIdx >= 0 && swipeIdx < updatedSwipes.length) {
      updatedSwipes[swipeIdx] = resetContent;
    }

    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[messageIndex] = msg.copyWith(content: resetContent, swipes: updatedSwipes);
    final resetSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );

    _setState(AsyncData(current.copyWith(session: resetSession, isGeneratingImage: true)));

    final imgCancelToken = CancelToken();
    _setImgGenCancelToken(imgCancelToken);

    final genService = ChatGenerationService(_ref);
    await genService.processImageTags(
      currentState: _getState().value!,
      charId: _charId,
      cancelToken: imgCancelToken,
      onStateUpdate: (updatedState) {
        _setState(AsyncData(updatedState));
      },
    );

    _setImgGenCancelToken(null);
    final finalState = _getState().value;
    if (finalState != null) {
      _setState(AsyncData(finalState.copyWith(isGeneratingImage: false)));
    }
  }

  Future<void> findImageOnDisk(String messageId, String instruction) async {
    final current = _getState().value;
    if (current == null || current.session == null) return;

    final msgIdx = current.messages.indexWhere((m) => m.id == messageId);
    if (msgIdx < 0) return;

    final imageStorage = await _ref.read(imageStorageProvider.future);
    final generatedDir = Directory(p.join(imageStorage.baseDir, 'generated'));
    if (!await generatedDir.exists()) return;

    final files = await generatedDir.list()
        .where((f) => f is File && p.extension(f.path).toLowerCase() == '.png')
        .cast<File>()
        .toList();

    if (files.isEmpty) return;

    final msg = current.messages[msgIdx];
    final Set<String> claimedPaths = {};
    for (final m in current.messages) {
      for (final match in ImgGenPatterns.imgResultRegex.allMatches(m.content)) {
        claimedPaths.add(match.group(1) ?? '');
      }
      for (final s in m.swipes) {
        for (final match in ImgGenPatterns.imgResultRegex.allMatches(s)) {
          claimedPaths.add(match.group(1) ?? '');
        }
      }
    }

    final unclaimed = files.where((f) => !claimedPaths.contains(f.path)).toList()
      ..sort((a, b) => b.lastAccessedSync().compareTo(a.lastAccessedSync()));

    final candidates = unclaimed.length > 20 ? unclaimed.sublist(0, 20) : unclaimed;

    if (candidates.isEmpty) return;

    final msgTimestamp = msg.timestamp ?? 0;
    File? bestMatch;
    int bestDiff = 0x7FFFFFFFFFFFFFFF;
    for (final f in candidates) {
      final stat = await f.stat();
      final fileMs = stat.modified.millisecondsSinceEpoch;
      final diff = (fileMs - msgTimestamp * 1000).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestMatch = f;
      }
    }

    if (bestMatch == null) return;

    final foundPath = bestMatch.path;

    var updatedContent = msg.content;
    updatedContent = replaceFirstImgErrorOrGen(updatedContent, foundPath);

    if (updatedContent == msg.content) return;

    final updatedSwipes = List<String>.from(msg.swipes);
    final swipeIdx = msg.swipeId;
    if (swipeIdx >= 0 && swipeIdx < updatedSwipes.length) {
      updatedSwipes[swipeIdx] = updatedContent;
    }

    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[msgIdx] = msg.copyWith(content: updatedContent, swipes: updatedSwipes);
    final updatedSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await _ref.read(chatRepoProvider).put(updatedSession);
    _setState(AsyncData(current.copyWith(session: updatedSession)));
  }
}