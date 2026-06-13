import 'package:easy_localization/easy_localization.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'placeholder_janitor_url'.tr(),
              style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14),
            ),
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            style: TextStyle(fontSize: 14, color: context.cs.onSurface),
            decoration: InputDecoration(
              hintText: 'https://...',
              hintStyle: TextStyle(
                color: context.cs.onSurfaceVariant,
                fontSize: 14,
              ),
              filled: true,
              fillColor: context.cs.surface,
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
                    color: context.cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _phase != null
                        ? 'Phase: $_phase'
                        : 'catalog_extracting'.tr(),
                    style: TextStyle(
                      color: context.cs.onSurfaceVariant,
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
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _startExtraction,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.cs.primary,
                foregroundColor: context.cs.onPrimary,
              ),
              child: Text(
                _loading ? 'catalog_importing'.tr() : 'action_import'.tr(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
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
