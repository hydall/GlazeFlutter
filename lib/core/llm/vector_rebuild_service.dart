import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../state/db_provider.dart';
import '../../features/settings/api_list_provider.dart';
import 'chat_message_embedding_service.dart';
import 'lorebook_providers.dart';
import 'memory_injection_service.dart';

enum VectorRebuildSource { memoryBooks, lorebooks, rawChat }

enum VectorRebuildStatus { idle, running, paused, cancelled, completed, error }

class VectorRebuildState {
  final VectorRebuildStatus status;
  final int current;
  final int total;
  final int indexed;
  final int skipped;
  final int failed;
  final String currentLabel;
  final String message;

  const VectorRebuildState({
    this.status = VectorRebuildStatus.idle,
    this.current = 0,
    this.total = 0,
    this.indexed = 0,
    this.skipped = 0,
    this.failed = 0,
    this.currentLabel = '',
    this.message = '',
  });

  double get progress => total <= 0 ? 0 : current / total;
  bool get isRunning => status == VectorRebuildStatus.running;
  bool get isPaused => status == VectorRebuildStatus.paused;
  bool get canStart => !isRunning && !isPaused;

  VectorRebuildState copyWith({
    VectorRebuildStatus? status,
    int? current,
    int? total,
    int? indexed,
    int? skipped,
    int? failed,
    String? currentLabel,
    String? message,
  }) {
    return VectorRebuildState(
      status: status ?? this.status,
      current: current ?? this.current,
      total: total ?? this.total,
      indexed: indexed ?? this.indexed,
      skipped: skipped ?? this.skipped,
      failed: failed ?? this.failed,
      currentLabel: currentLabel ?? this.currentLabel,
      message: message ?? this.message,
    );
  }
}

class VectorRebuildRequest {
  final Set<VectorRebuildSource> sources;
  final int vectorsPerMinute;
  final int batchSize;
  final bool forceReindex;

  const VectorRebuildRequest({
    required this.sources,
    this.vectorsPerMinute = 30,
    this.batchSize = 10,
    this.forceReindex = false,
  });
}

final vectorRebuildControllerProvider =
    NotifierProvider<VectorRebuildController, VectorRebuildState>(
      VectorRebuildController.new,
    );

class VectorRebuildController extends Notifier<VectorRebuildState> {
  bool _cancelRequested = false;
  Completer<void>? _pauseCompleter;

  @override
  VectorRebuildState build() => const VectorRebuildState();

  Future<void> start(VectorRebuildRequest request) async {
    if (!state.canStart || request.sources.isEmpty) return;

    _cancelRequested = false;
    _pauseCompleter = null;
    state = const VectorRebuildState(
      status: VectorRebuildStatus.running,
      message: 'Preparing vector rebuild...',
    );

    try {
      await ref.read(apiListProvider.future);
      final config = ref.read(embeddingConfigProvider);
      if (config.endpoint.isEmpty) {
        state = state.copyWith(
          status: VectorRebuildStatus.error,
          message: 'Configure an embedding endpoint before rebuilding vectors.',
        );
        return;
      }

      final tasks = await _buildTasks(request);
      if (tasks.isEmpty) {
        state = state.copyWith(
          status: VectorRebuildStatus.completed,
          message: 'No vector rebuild work found.',
        );
        return;
      }

      final delay = vectorRebuildDelayForRate(request.vectorsPerMinute);
      final batchSize = request.batchSize < 1 ? 1 : request.batchSize;
      state = state.copyWith(
        total: tasks.length,
        message: 'Rebuilding vectors...',
      );

      for (var i = 0; i < tasks.length; i++) {
        if (_cancelRequested) {
          state = state.copyWith(
            status: VectorRebuildStatus.cancelled,
            message: 'Vector rebuild cancelled.',
          );
          return;
        }
        await _waitIfPaused();
        if (_cancelRequested) continue;

        final task = tasks[i];
        state = state.copyWith(
          status: VectorRebuildStatus.running,
          currentLabel: task.label,
          message: task.sourceLabel,
        );

        try {
          final result = await task.run();
          state = state.copyWith(
            indexed: state.indexed + result.indexed,
            skipped: state.skipped + result.skipped,
            failed: state.failed + result.failed,
          );
        } catch (e) {
          debugPrint('[VectorRebuild] failed task=${task.label}: $e');
          state = state.copyWith(failed: state.failed + 1);
        }

        state = state.copyWith(current: i + 1);
        if (i + 1 < tasks.length && delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        if ((i + 1) % batchSize == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      state = state.copyWith(
        status: VectorRebuildStatus.completed,
        currentLabel: '',
        message: 'Vector rebuild complete.',
      );
    } catch (e) {
      state = state.copyWith(
        status: VectorRebuildStatus.error,
        message: 'Vector rebuild failed: $e',
      );
    }
  }

  void pause() {
    if (!state.isRunning) return;
    _pauseCompleter ??= Completer<void>();
    state = state.copyWith(
      status: VectorRebuildStatus.paused,
      message: 'Vector rebuild paused.',
    );
  }

  void resume() {
    if (!state.isPaused) return;
    final completer = _pauseCompleter;
    _pauseCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    state = state.copyWith(
      status: VectorRebuildStatus.running,
      message: 'Rebuilding vectors...',
    );
  }

  void cancel() {
    if (!state.isRunning && !state.isPaused) return;
    _cancelRequested = true;
    resume();
  }

  Future<void> _waitIfPaused() async {
    final completer = _pauseCompleter;
    if (completer != null) await completer.future;
  }

  Future<List<_VectorRebuildTask>> _buildTasks(
    VectorRebuildRequest request,
  ) async {
    final tasks = <_VectorRebuildTask>[];
    final config = ref.read(embeddingConfigProvider);

    if (request.sources.contains(VectorRebuildSource.memoryBooks)) {
      final sessions = await ref.read(chatRepoProvider).getAllSessions();
      final charBySession = {
        for (final session in sessions) session.id: session.characterId,
      };
      final books = await ref.read(memoryBookRepoProvider).getAll();
      final memoryService = ref.read(memoryEmbeddingServiceProvider);
      final embeddingRepo = ref.read(embeddingRepoProvider);
      for (final book in books) {
        final charId = charBySession[book.sessionId];
        if (charId == null) continue;
        for (final entry in book.entries) {
          if (entry.status != 'active') continue;
          tasks.add(
            _VectorRebuildTask(
              sourceLabel: 'MemoryBook',
              label: entry.title.isNotEmpty ? entry.title : entry.id,
              run: () async {
                if (request.forceReindex) {
                  await embeddingRepo.deleteByEntryId(entry.id);
                }
                await memoryService.indexMemoryEntry(
                  entry,
                  charId: charId,
                  sessionId: book.sessionId,
                  config: config,
                );
                return const _VectorTaskResult(indexed: 1);
              },
            ),
          );
        }
      }
    }

    if (request.sources.contains(VectorRebuildSource.lorebooks)) {
      final lorebookService = ref.read(lorebookEmbeddingServiceProvider);
      final lorebooks = await ref.read(lorebookRepoProvider).getAll();
      for (final lorebook in lorebooks) {
        for (final entry in lorebook.entries) {
          if (!entry.enabled || entry.constant) continue;
          if (entry.excludeFromVectorization) continue;
          if (!entry.vectorSearch &&
              (entry.keys.isNotEmpty || entry.secondaryKeys.isNotEmpty)) {
            continue;
          }
          tasks.add(
            _VectorRebuildTask(
              sourceLabel: 'Lorebook',
              label:
                  '${lorebook.name}: ${entry.comment.isNotEmpty ? entry.comment : entry.id}',
              run: () async {
                final result = await lorebookService.indexLorebookEntries(
                  lorebook.id,
                  [entry],
                  config,
                  forceReindex: request.forceReindex,
                  embeddingTarget:
                      lorebook.settings?.embeddingTarget ?? 'content',
                );
                return _VectorTaskResult(
                  indexed: result.indexed,
                  skipped: result.skipped,
                  failed: result.failed,
                );
              },
            ),
          );
        }
      }
    }

    if (request.sources.contains(VectorRebuildSource.rawChat)) {
      final chatService = ref.read(chatMessageEmbeddingServiceProvider);
      final embeddingRepo = ref.read(embeddingRepoProvider);
      final sessions = await ref.read(chatRepoProvider).getAllSessions();
      for (final session in sessions) {
        final eligibleCount = session.messages
            .where(_isEmbeddableMessage)
            .length;
        if (eligibleCount < ChatMessageEmbeddingService.defaultChunkSize) {
          continue;
        }
        tasks.add(
          _VectorRebuildTask(
            sourceLabel: 'Raw chat',
            label: 'Session ${session.sessionIndex}',
            run: () async {
              if (request.forceReindex) {
                await embeddingRepo.deleteBySourceId(session.id);
              }
              await chatService.indexSessionMessages(
                sessionId: session.id,
                messages: session.messages,
                config: config,
              );
              return const _VectorTaskResult(indexed: 1);
            },
          ),
        );
      }
    }

    return tasks;
  }
}

Duration vectorRebuildDelayForRate(int vectorsPerMinute) {
  if (vectorsPerMinute <= 0) return Duration.zero;
  return Duration(milliseconds: (60000 / vectorsPerMinute).round());
}

bool _isEmbeddableMessage(ChatMessage message) {
  return !message.isTyping &&
      !message.isHidden &&
      !message.isError &&
      message.id.isNotEmpty &&
      message.content.trim().isNotEmpty &&
      (message.role == 'user' || message.role == 'assistant');
}

class _VectorRebuildTask {
  final String sourceLabel;
  final String label;
  final Future<_VectorTaskResult> Function() run;

  const _VectorRebuildTask({
    required this.sourceLabel,
    required this.label,
    required this.run,
  });
}

class _VectorTaskResult {
  final int indexed;
  final int skipped;
  final int failed;

  const _VectorTaskResult({
    this.indexed = 0,
    this.skipped = 0,
    this.failed = 0,
  });
}
