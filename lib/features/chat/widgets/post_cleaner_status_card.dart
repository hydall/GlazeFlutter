import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/post_cleaner_state_provider.dart';

/// Floating card shown at the top of the chat while the POST-cleaner is
/// running, and for a brief moment after it finishes (done/error).
///
/// Mirrors the visual style of [_StudioRuntimeCard] in `chat_screen.dart`.
/// Auto-dismisses 2.5s after the cleaner finishes.
class PostCleanerStatusCard extends ConsumerStatefulWidget {
  const PostCleanerStatusCard({super.key});

  @override
  ConsumerState<PostCleanerStatusCard> createState() =>
      _PostCleanerStatusCardState();
}

class _PostCleanerStatusCardState
    extends ConsumerState<PostCleanerStatusCard> {
  PostCleanerPhase? _lastSeenPhase;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(postCleanerStateProvider);
    final cs = Theme.of(context).colorScheme;

    // Track phase transitions to trigger auto-dismiss.
    if (_lastSeenPhase != state.phase) {
      _lastSeenPhase = state.phase;
      if (state.phase == PostCleanerPhase.done ||
          state.phase == PostCleanerPhase.skipped ||
          state.phase == PostCleanerPhase.error) {
        _scheduleAutoDismiss();
      }
    }

    if (state.phase == PostCleanerPhase.idle) return const SizedBox.shrink();

    final isRunning = state.phase == PostCleanerPhase.running;
    final isError = state.phase == PostCleanerPhase.error;

    final String label;
    final IconData icon;
    final Color accent;

    if (isRunning) {
      label = 'Cleaning…';
      icon = Icons.cleaning_services_outlined;
      accent = cs.primary;
    } else if (state.phase == PostCleanerPhase.done) {
      final delta = state.charDelta;
      label = delta != null
          ? 'Cleaned (${delta >= 0 ? '+' : ''}$delta chars)'
          : 'Cleaned';
      icon = Icons.check_circle_outline;
      accent = Colors.green;
    } else if (isError) {
      label = 'Cleaner failed';
      icon = Icons.error_outline;
      accent = Colors.orange;
    } else {
      label = 'Cleaner skipped';
      icon = Icons.skip_next_outlined;
      accent = Colors.grey;
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
            if (isRunning)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent,
                ),
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

  void _scheduleAutoDismiss() {
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final current = ref.read(postCleanerStateProvider);
      // Only auto-clear if we're still in the same done/error/skipped phase
      // (i.e. a new cleaner run hasn't started in the meantime).
      if (current.phase != PostCleanerPhase.running &&
          current.phase != PostCleanerPhase.idle) {
        ref.read(postCleanerStateProvider.notifier).state =
            const PostCleanerState.idle();
      }
    });
  }
}
