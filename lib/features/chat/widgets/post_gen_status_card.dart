import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/post_gen_status_provider.dart';

/// Floating card shown at the top of the chat while post-generation tasks
/// (Ledger and extension blocks) are running. Auto-dismisses 2.5s after
/// the last task completes.
class PostGenStatusCard extends ConsumerStatefulWidget {
  const PostGenStatusCard({super.key, required this.sessionId});

  final String? sessionId;

  @override
  ConsumerState<PostGenStatusCard> createState() => _PostGenStatusCardState();
}

class _PostGenStatusCardState extends ConsumerState<PostGenStatusCard> {
  PostGenTaskPhase? _lastSeenPhase;
  PostGenTask? _lastSeenTask;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch<PostGenStatusState>(postGenStatusProvider);
    final cs = Theme.of(context).colorScheme;

    if (state.phase == PostGenTaskPhase.idle ||
        state.task == PostGenTask.none ||
        state.sessionId != widget.sessionId) {
      _lastSeenPhase = null;
      _lastSeenTask = null;
      return const SizedBox.shrink();
    }

    // Detect transitions: when either the phase or the task changes we
    // may need to (re)schedule the auto-dismiss.  Without tracking the
    // task, completing a second post-gen task while the card still shows the
    // first task's `done` phase would skip the dismiss timer — leaving the
    // later completion card stuck.
    if (_lastSeenPhase != state.phase || _lastSeenTask != state.task) {
      _lastSeenPhase = state.phase;
      _lastSeenTask = state.task;
      if (state.phase == PostGenTaskPhase.done ||
          state.phase == PostGenTaskPhase.error) {
        _scheduleAutoDismiss(state);
      }
    }

    final String label;
    final IconData icon;
    final Color accent;
    final bool showSpinner;

    switch (state.task) {
      case PostGenTask.ledger:
        if (state.phase == PostGenTaskPhase.running) {
          label = 'Ledger running...';
          icon = Icons.menu_book_outlined;
          accent = cs.primary;
          showSpinner = true;
        } else if (state.phase == PostGenTaskPhase.done) {
          label = state.detail ?? 'Ledger done';
          icon = Icons.check_circle_outline;
          accent = Colors.green;
          showSpinner = false;
        } else {
          label = state.detail ?? 'Ledger failed';
          icon = Icons.error_outline;
          accent = Colors.redAccent;
          showSpinner = false;
        }
      case PostGenTask.extBlocks:
        if (state.phase == PostGenTaskPhase.running) {
          label = 'Extension blocks running...';
          icon = Icons.extension_outlined;
          accent = cs.primary;
          showSpinner = true;
        } else if (state.phase == PostGenTaskPhase.done) {
          label = state.detail ?? 'Extension blocks done';
          icon = Icons.check_circle_outline;
          accent = Colors.green;
          showSpinner = false;
        } else {
          label = 'Extension blocks failed';
          icon = Icons.error_outline;
          accent = Colors.redAccent;
          showSpinner = false;
        }
      case PostGenTask.none:
        return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            if (showSpinner)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              )
            else
              Icon(icon, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleAutoDismiss(PostGenStatusState expected) {
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final current = ref.read(postGenStatusProvider);
      if (identical(current, expected)) {
        ref.read(postGenStatusProvider.notifier).state =
            const PostGenStatusState.idle();
      }
    });
  }
}
