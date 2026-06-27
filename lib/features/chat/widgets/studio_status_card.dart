import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/studio_cycle_state_provider.dart';

/// Floating card shown at the top of the chat while the Studio tracker-cycle
/// is running, and for a brief moment after it finishes (done/agentErrors/
/// error).
///
/// Auto-dismisses 2.5s after the cycle finishes.
class StudioStatusCard extends ConsumerStatefulWidget {
  const StudioStatusCard({super.key});

  @override
  ConsumerState<StudioStatusCard> createState() => _StudioStatusCardState();
}

class _StudioStatusCardState extends ConsumerState<StudioStatusCard> {
  StudioCyclePhase? _lastSeenPhase;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studioCycleStateProvider);
    final cs = Theme.of(context).colorScheme;

    // Track phase transitions to trigger auto-dismiss.
    if (_lastSeenPhase != state.phase) {
      _lastSeenPhase = state.phase;
      if (state.phase == StudioCyclePhase.done ||
          state.phase == StudioCyclePhase.agentErrors ||
          state.phase == StudioCyclePhase.error) {
        _scheduleAutoDismiss();
      }
    }

    if (state.phase == StudioCyclePhase.idle) return const SizedBox.shrink();

    final isRunning = state.phase == StudioCyclePhase.running;
    final isWritingFinal = state.phase == StudioCyclePhase.writingFinal;

    final String label;
    final IconData icon;
    final Color accent;

    if (isRunning) {
      final done = state.completedAgents + state.failedAgents;
      label = state.totalAgents > 0
          ? 'Trackers $done/${state.totalAgents}…'
          : 'Trackers…';
      icon = Icons.auto_awesome_outlined;
      accent = cs.primary;
    } else if (isWritingFinal) {
      label = 'Generating…';
      icon = Icons.edit_note;
      accent = cs.primary;
    } else if (state.phase == StudioCyclePhase.done) {
      final failed = state.failedAgents;
      label = failed > 0
          ? 'Studio done ($failed failed)'
          : 'Studio done (${state.totalAgents})';
      icon = Icons.check_circle_outline;
      accent = Colors.green;
    } else if (state.phase == StudioCyclePhase.agentErrors) {
      final names = state.failedAgentNames.join(', ');
      label = 'Trackers failed: $names';
      icon = Icons.warning_amber_outlined;
      accent = Colors.orange;
    } else {
      // error
      label = 'Studio failed';
      icon = Icons.error_outline;
      accent = Colors.redAccent;
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
            if (isRunning || isWritingFinal)
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

  void _scheduleAutoDismiss() {
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final current = ref.read(studioCycleStateProvider);
      // Only auto-clear if we're still in the same done/agentErrors/error
      // phase (i.e. a new cycle hasn't started in the meantime).
      if (current.phase != StudioCyclePhase.running &&
          current.phase != StudioCyclePhase.writingFinal &&
          current.phase != StudioCyclePhase.idle) {
        ref.read(studioCycleStateProvider.notifier).state =
            const StudioCycleState.idle();
      }
    });
  }
}
