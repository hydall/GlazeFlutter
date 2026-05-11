import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../catalog_models.dart';
import '../catalog_provider.dart';
import '../services/datacat_provider.dart';

class ImportUrlDialog extends ConsumerStatefulWidget {
  const ImportUrlDialog({super.key});

  @override
  ConsumerState<ImportUrlDialog> createState() => _ImportUrlDialogState();
}

class _ImportUrlDialogState extends ConsumerState<ImportUrlDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _phase;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Import by URL',
        style: TextStyle(color: context.colors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste a JanitorAI, Saucepan.ai, or Chub.ai character URL',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            style: TextStyle(fontSize: 14, color: context.colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'https://...',
              hintStyle: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
              ),
              filled: true,
              fillColor: context.colors.background,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            enabled: !_loading,
            onSubmitted: (_) => _startExtraction(),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _phase != null
                        ? 'Phase: $_phase'
                        : 'Extracting character...',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (!_loading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
        if (!_loading)
          TextButton(
            onPressed: _startExtraction,
            child: Text(
              'Import',
              style: TextStyle(color: context.colors.accent),
            ),
          ),
        if (_loading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
      ],
    );
  }

  Future<void> _startExtraction() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _phase = null;
    });

    try {
      final result = await datacatExtractAndPoll(
        url,
        onPhaseChange: (phase) {
          if (mounted) setState(() => _phase = phase);
        },
      );

      if (result.error != null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = result.error;
          });
        }
        return;
      }

      if (result.charData != null && mounted) {
        final notifier = ref.read(catalogProvider.notifier);
        final downloaded = DownloadedCharacter(
          charData: result.charData!,
          avatarUrl: result.avatarUrl,
        );
        await notifier.importCharacter(downloaded);
        if (mounted) {
          Navigator.pop(context);
          GlazeToast.show(context, 'Imported ${result.charData!.name}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }
}
