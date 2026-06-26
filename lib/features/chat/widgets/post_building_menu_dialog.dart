import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/memory_book.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/theme/app_colors.dart';

/// Post-Building menu dialog. Session-bound.
///
/// Hosts all POST-cleaner settings: enable switch, continuity check,
/// character audit, model/temperature/tokens/timeout, history window.
/// Works independently of Studio — the cleaner only needs MemoryBookSettings.
class PostBuildingMenuDialog extends ConsumerStatefulWidget {
  final String charId;
  final String sessionId;

  const PostBuildingMenuDialog({
    super.key,
    required this.charId,
    required this.sessionId,
  });

  @override
  ConsumerState<PostBuildingMenuDialog> createState() =>
      _PostBuildingMenuDialogState();
}

class _PostBuildingMenuDialogState
    extends ConsumerState<PostBuildingMenuDialog> {
  bool _postCleanerEnabled = false;
  bool _continuityEnabled = true;
  bool _characterCheckEnabled = false;
  double _postCleanerTemperature = 0.3;
  int _postCleanerMaxTokens = 0;
  int _postCleanerTimeoutMs = 0;
  int _historyMessages = 12;
  int _maxCharsPerMessage = 3000;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final book = await ref
          .read(memoryBookRepoProvider)
          .getBySessionId(widget.sessionId);
      if (mounted) {
        final s = book?.settings ?? const MemoryBookSettings();
        setState(() {
          _postCleanerEnabled = s.postCleanerEnabled;
          _continuityEnabled = s.postCleanerContinuityEnabled;
          _characterCheckEnabled = s.postCleanerCharacterCheckEnabled;
          _postCleanerTemperature = s.postCleanerTemperature;
          _postCleanerMaxTokens = s.postCleanerMaxTokens;
          _postCleanerTimeoutMs = s.postCleanerTimeoutMs;
          _historyMessages = s.postCleanerHistoryMessages;
          _maxCharsPerMessage = s.postCleanerMaxCharsPerMessage;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveSetting(
    MemoryBookSettings Function(MemoryBookSettings) mutator,
  ) async {
    final repo = ref.read(memoryBookRepoProvider);
    final book = await repo.ensureForSession(widget.sessionId);
    final updated = mutator(book.settings);
    await repo.updateSettings(widget.sessionId, updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        content: SizedBox(
          width: 80,
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.cleaning_services_outlined, color: context.cs.primary),
          const SizedBox(width: 8),
          const Text('Post-Building'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('POST-cleaner (anti-cliche rewrite)'),
                subtitle: const Text(
                  'After generation, silently rewrites the response to remove '
                  'cliches and repetition. Original preserved as a swipe.',
                ),
                value: _postCleanerEnabled,
                onChanged: (v) async {
                  await _saveSetting(
                    (s) => s.copyWith(postCleanerEnabled: v),
                  );
                  if (mounted) setState(() => _postCleanerEnabled = v);
                },
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Continuity check (recent history)'),
                subtitle: const Text(
                  'Includes recent chat history in the cleaner prompt for '
                  'local continuity checks: who said what, positions, '
                  'clothing, recent actions. No extra LLM call.',
                ),
                value: _continuityEnabled,
                onChanged: (v) async {
                  await _saveSetting(
                    (s) => s.copyWith(postCleanerContinuityEnabled: v),
                  );
                  if (mounted) setState(() => _continuityEnabled = v);
                },
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Character & world audit (extra sidecar call)',
                ),
                subtitle: const Text(
                  'Opt-in. A diagnostic sidecar pass checks the response '
                  'against character card, persona, lorebooks, and memory. '
                  'Returns contradictions that the cleaner then fixes.',
                ),
                value: _characterCheckEnabled,
                onChanged: (v) async {
                  await _saveSetting(
                    (s) => s.copyWith(postCleanerCharacterCheckEnabled: v),
                  );
                  if (mounted) setState(() => _characterCheckEnabled = v);
                },
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Cleaner temperature'),
                subtitle: Text(
                  '$_postCleanerTemperature — lower = more faithful rewrite, '
                  'higher = more creative.',
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: _showTemperatureDialog,
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Cleaner max tokens'),
                subtitle: Text(
                  _postCleanerMaxTokens == 0
                      ? 'Auto (half of original length).'
                      : '$_postCleanerMaxTokens tokens.',
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: _showMaxTokensDialog,
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Cleaner timeout'),
                subtitle: Text(
                  _postCleanerTimeoutMs == 0
                      ? 'Inherit from write-loop (${(_resolveInheritedTimeout() / 1000).toStringAsFixed(0)}s).'
                      : '${(_postCleanerTimeoutMs / 1000).toStringAsFixed(0)}s',
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: _showTimeoutDialog,
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('History messages'),
                subtitle: Text(
                  '$_historyMessages — number of recent messages included '
                  'for continuity checks.',
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: _showHistoryMessagesDialog,
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Max chars per message'),
                subtitle: Text(
                  '$_maxCharsPerMessage — each history message is trimmed to '
                  'this many characters.',
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: _showMaxCharsDialog,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  int _resolveInheritedTimeout() {
    return 60000;
  }

  Future<void> _showTemperatureDialog() async {
    final controller = TextEditingController(
      text: _postCleanerTemperature.toStringAsFixed(2),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cleaner temperature'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controls how creative the POST-cleaner rewrite is.\n'
              '0.0 = almost identical to original\n'
              '0.3 = default, light cleanup\n'
              '0.7 = more aggressive rewrite',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v == null || v < 0 || v > 2) {
                Navigator.of(ctx).pop();
                return;
              }
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _saveSetting((s) => s.copyWith(postCleanerTemperature: result));
    if (mounted) setState(() => _postCleanerTemperature = result);
  }

  Future<void> _showMaxTokensDialog() async {
    final controller = TextEditingController(
      text: _postCleanerMaxTokens == 0 ? '' : '$_postCleanerMaxTokens',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cleaner max tokens'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Maximum tokens for the cleaner rewrite.\n'
              '0 = auto (half the original text length).\n'
              'If the cleaner truncates responses, increase this.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '0 (auto)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop(v ?? 0);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _saveSetting((s) => s.copyWith(postCleanerMaxTokens: result));
    if (mounted) setState(() => _postCleanerMaxTokens = result);
  }

  Future<void> _showTimeoutDialog() async {
    final controller = TextEditingController(
      text: _postCleanerTimeoutMs == 0
          ? ''
          : (_postCleanerTimeoutMs / 1000).toStringAsFixed(0),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cleaner timeout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How long to wait for the cleaner LLM before giving up.\n'
              '0 = inherit from write-loop sidecar timeout.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '0 (inherit)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop(v == null ? 0 : v * 1000);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _saveSetting((s) => s.copyWith(postCleanerTimeoutMs: result));
    if (mounted) setState(() => _postCleanerTimeoutMs = result);
  }

  Future<void> _showHistoryMessagesDialog() async {
    final controller = TextEditingController(text: '$_historyMessages');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('History messages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Number of recent chat messages included in the cleaner prompt '
              'for continuity checks. Recommended: 8-20.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 0 || v > 100) {
                Navigator.of(ctx).pop();
                return;
              }
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _saveSetting((s) => s.copyWith(postCleanerHistoryMessages: result));
    if (mounted) setState(() => _historyMessages = result);
  }

  Future<void> _showMaxCharsDialog() async {
    final controller = TextEditingController(text: '$_maxCharsPerMessage');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Max chars per message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Each recent history message is trimmed to this many '
              'characters before being included in the cleaner prompt. '
              'Recommended: 1000-8000.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 100 || v > 50000) {
                Navigator.of(ctx).pop();
                return;
              }
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _saveSetting(
      (s) => s.copyWith(postCleanerMaxCharsPerMessage: result),
    );
    if (mounted) setState(() => _maxCharsPerMessage = result);
  }
}
