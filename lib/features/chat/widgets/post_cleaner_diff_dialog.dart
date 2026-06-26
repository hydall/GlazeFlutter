import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/theme/app_colors.dart';

/// Side-by-side diff viewer for POST-cleaner results.
///
/// Loads the message from the DB by [sessionId]/[messageId], extracts the
/// `final` and `cleaned` agent swipes, and renders them in two parallel
/// scrollable columns. Opened from the Agentic Operations Log when the user
/// taps "View Diff" on a postCleaner operation.
class PostCleanerDiffDialog extends ConsumerStatefulWidget {
  final String sessionId;
  final String messageId;

  const PostCleanerDiffDialog({
    super.key,
    required this.sessionId,
    required this.messageId,
  });

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
    required String messageId,
  }) {
    return showDialog(
      context: context,
      builder: (_) =>
          PostCleanerDiffDialog(sessionId: sessionId, messageId: messageId),
    );
  }

  @override
  ConsumerState<PostCleanerDiffDialog> createState() =>
      _PostCleanerDiffDialogState();
}

class _PostCleanerDiffDialogState extends ConsumerState<PostCleanerDiffDialog> {
  bool _loading = true;
  String? _error;
  AgentSwipe? _original;
  AgentSwipe? _cleaned;

  @override
  void initState() {
    super.initState();
    _loadMessage();
  }

  Future<void> _loadMessage() async {
    try {
      final session = await ref.read(chatRepoProvider).getById(widget.sessionId);
      if (session == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Session not found';
        });
        return;
      }
      final msg = session.messages.where((m) => m.id == widget.messageId).firstOrNull;
      if (msg == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Message not found';
        });
        return;
      }

      final swipes = msg.agentSwipes;
      AgentSwipe? original;
      AgentSwipe? cleaned;
      for (final s in swipes) {
        if (s.kind == 'cleaned') {
          cleaned = s;
          final parentId = s.parentSwipeId;
          if (parentId != null && parentId < swipes.length) {
            original = swipes[parentId];
          }
        }
      }
      if (original == null && swipes.isNotEmpty) {
        original = swipes.where((s) => s.kind == 'final').lastOrNull;
      }

      if (!mounted) return;
      setState(() {
        _original = original;
        _cleaned = cleaned;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      child: SizedBox(
        width: 900,
        height: 600,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.compare_arrows, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Cleaner Diff', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 8),
                  if (_original != null && _cleaned != null)
                    Text(
                      '${_cleaned!.content.length - _original!.content.length >= 0 ? '+' : ''}${_cleaned!.content.length - _original!.content.length} chars',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: TextStyle(color: context.cs.error)),
        ),
      );
    }
    if (_original == null || _cleaned == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No cleaner diff available for this message.'),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildPanel(
            context,
            label: 'Original',
            content: _original!.content,
            accent: cs.onSurfaceVariant,
          )),
          const VerticalDivider(width: 1),
          Expanded(child: _buildPanel(
            context,
            label: 'Cleaned',
            content: _cleaned!.content,
            accent: cs.primary,
          )),
        ],
      ),
    );
  }

  Widget _buildPanel(
    BuildContext context, {
    required String label,
    required String content,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.label_outline, size: 14, color: accent),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${content.length} chars',
                  style: TextStyle(fontSize: 10, color: accent.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: context.cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
