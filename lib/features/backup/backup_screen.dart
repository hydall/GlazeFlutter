import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/file_export_service.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_toast.dart';
import 'backup_provider.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _exporting = false;
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    return GlazeScaffold(
      title: 'Backup',
      onBack: () => context.go('/menu'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Export Backup',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Create a .glz backup of all your data: characters, chats, personas, presets, lorebooks, gallery images, and settings.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _exporting ? null : _exportBackup,
                        icon: _exporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_file),
                        label: Text(_exporting ? 'Exporting...' : 'Export .glz'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Import Backup',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Restore from a .glz backup file. This will replace all current data. Also supports Glaze JS backups.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _importing ? null : _importBackup,
                        icon: _importing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.file_download),
                        label: Text(_importing ? 'Importing...' : 'Import .glz'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Warning: Importing a backup will completely replace all your current data. Make sure to export first if you want to keep your current state.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _restartApp() {
    final ctx = context;
    Navigator.of(ctx).pushNamedAndRemoveUntil('/', (_) => false);
  }

  Future<void> _exportBackup() async {
    setState(() => _exporting = true);
    try {
      final service = await ref.read(backupServiceProvider.future);
      final json = await service.exportBackup();

      final now = DateTime.now();
      final filename =
          'Glaze_backup_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}.glz';

      final path = await FileExportService.export(
        data: json,
        filename: filename,
        subfolder: 'backup',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup saved to $path')),
        );
      }
    } catch (e) {
      if (mounted) {
        GlazeToast.error(context, 'Export failed: ', e);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace all data?'),
        content: const Text(
            'Importing a backup will completely replace all your current data. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _importing = true);
    try {
      final result = await FilePicker.pickFiles(
        type: Platform.isIOS ? FileType.any : FileType.custom,
        allowMultiple: false,
        allowedExtensions: Platform.isIOS ? null : ['glz', 'json'],
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _importing = false);
        return;
      }

      final path = result.files.single.path;
      if (path == null) {
        setState(() => _importing = false);
        return;
      }

      final file = File(path);
      final jsonString = await file.readAsString();

      final service = await ref.read(backupServiceProvider.future);
      await service.importBackup(jsonString);

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Backup Restored'),
            content: const Text(
                'All data has been replaced. Restart the app to apply all changes.'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _restartApp();
                },
                child: const Text('Restart'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        GlazeToast.error(context, 'Import failed: ', e);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
