import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/shell/nav_height_provider.dart';
import '../../../shared/widgets/glaze_scaffold.dart';
import '../../../shared/widgets/menu_group.dart';
import '../providers/extension_presets_provider.dart';
import '../providers/extensions_settings_provider.dart';

/// Registry of available extensions.
/// Each extension has a unique id, display label, icon, and a flag indicating
/// whether it has a dedicated settings sheet accessible from the magic drawer.
class ExtensionDescriptor {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final bool Function(WidgetRef ref) isEnabled;
  final ValueChanged<bool> Function(WidgetRef ref) onToggle;
  final String? Function(WidgetRef ref)? statusLabel;

  const ExtensionDescriptor({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.isEnabled,
    required this.onToggle,
    this.statusLabel,
  });
}

final _availableExtensions = <ExtensionDescriptor>[
  ExtensionDescriptor(
    id: 'ext-blocks',
    label: 'Ext Blocks',
    description: 'Автоматические инфоблоки и картинки после ответа модели',
    icon: Icons.extension_outlined,
    isEnabled: (ref) => ref.watch(extensionsSettingsProvider).enabled,
    onToggle: (ref) => (v) =>
        ref.read(extensionsSettingsProvider.notifier).setEnabled(v),
    statusLabel: (ref) {
      final settings = ref.watch(extensionsSettingsProvider);
      final presets = ref.watch(extensionPresetsProvider);
      if (!settings.enabled) return null;
      if (settings.activePresetId == null) return 'Пресет не выбран';
      final preset = presets
          .where((p) => p.id == settings.activePresetId)
          .firstOrNull;
      return preset?.name;
    },
  ),
];

class ExtensionsScreen extends ConsumerWidget {
  const ExtensionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPad = ref.watch(navHeightProvider) + 20;
    final items = _availableExtensions.map((ext) {
      return MenuSwitchItem(
        label: ext.label,
        description: ext.description,
        value: ext.isEnabled(ref),
        onChanged: ext.onToggle(ref),
      );
    }).toList();

    return GlazeScaffold(
      title: 'Расширения',
      onBack: () => context.pop(),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, 12, 0, bottomPad),
        children: [
          MenuGroup(
            header: 'Доступные расширения',
            items: items,
          ),
        ],
      ),
    );
  }
}
