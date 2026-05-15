import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';


import '../../../core/models/lorebook.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../../lorebooks/lorebook_connections_sheet.dart';

/// Quick-access lorebook panel opened from MagicDrawer.
///
/// Three views:
///   list     — global settings (collapsible) + lorebook list with activation badges
///   entries  — entry list for a selected lorebook
///
/// Mirrors JS LorebookSheet.vue list/entries views.
void showLorebookQuickSheet(BuildContext context, WidgetRef ref, String charId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _LorebookQuickSheet(charId: charId),
  );
}

class _LorebookQuickSheet extends ConsumerStatefulWidget {
  final String charId;
  const _LorebookQuickSheet({required this.charId});

  @override
  ConsumerState<_LorebookQuickSheet> createState() => _LorebookQuickSheetState();
}

typedef _View = String;
const _viewList = 'list';
const _viewEntries = 'entries';

class _LorebookQuickSheetState extends ConsumerState<_LorebookQuickSheet> {
  _View _view = _viewList;
  Lorebook? _activeLorebook;
  bool _globalExpanded = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectLorebook(Lorebook lb) => setState(() {
        _activeLorebook = lb;
        _view = _viewEntries;
        _searchController.clear();
      });

  void _goBack() {
    if (_view == _viewEntries) {
      setState(() {
        _view = _viewList;
        _activeLorebook = null;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lorebooks = ref.watch(lorebooksProvider).value ?? [];

    String title;
    bool showBack;
    List<SheetViewAction> actions = const [];

    if (_view == _viewEntries && _activeLorebook != null) {
      final lb = lorebooks.where((l) => l.id == _activeLorebook!.id).firstOrNull ?? _activeLorebook!;
      title = lb.name;
      showBack = true;
      actions = [
        SheetViewAction(
          icon: const Icon(Icons.settings_outlined, size: 20),
          tooltip: 'Open full editor',
          onPressed: () {
            Navigator.of(context).pop();
            context.go('/tools/lorebooks/${lb.id}');
          },
        ),
      ];
    } else {
      title = 'Lorebooks';
      showBack = false;
      actions = [
        SheetViewAction(
          icon: const Icon(Icons.open_in_new_outlined, size: 20),
          tooltip: 'Open Lorebook Manager',
          onPressed: () {
            Navigator.of(context).pop();
            context.go('/tools/lorebooks');
          },
        ),
      ];
    }

    final body = switch (_view) {
      _viewEntries => _EntriesView(
          lorebook: lorebooks.where((l) => l.id == _activeLorebook?.id).firstOrNull ?? _activeLorebook!,
          charId: widget.charId,
          searchController: _searchController,
          onOpenEditor: () {
            Navigator.of(context).pop();
            context.go('/tools/lorebooks/${_activeLorebook!.id}');
          },
        ),
      _ => _ListView(
          lorebooks: lorebooks,
          charId: widget.charId,
          globalExpanded: _globalExpanded,
          onGlobalExpandToggle: () => setState(() => _globalExpanded = !_globalExpanded),
          onSelect: _selectLorebook,
          onOpenConnections: (lb) {
            showModalBottomSheet(
              context: context,
              useRootNavigator: true,
              useSafeArea: true,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => LorebookConnectionsSheet(lorebookId: lb.id),
            );
          },
        ),
    };

    return SheetView(
      title: title,
      showBack: showBack,
      onBack: _goBack,
      actions: actions,
      startExpanded: true,
      headerBottom: _view == _viewEntries
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: context.cs.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search entries...',
                  hintStyle: TextStyle(color: context.cs.onSurfaceVariant),
                  prefixIcon: Icon(Icons.search, size: 18, color: context.cs.onSurfaceVariant),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            )
          : null,
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// View: List
// ─────────────────────────────────────────────────────────────

class _ListView extends ConsumerWidget {
  final List<Lorebook> lorebooks;
  final String charId;
  final bool globalExpanded;
  final VoidCallback onGlobalExpandToggle;
  final ValueChanged<Lorebook> onSelect;
  final ValueChanged<Lorebook> onOpenConnections;

  const _ListView({
    required this.lorebooks,
    required this.charId,
    required this.globalExpanded,
    required this.onGlobalExpandToggle,
    required this.onSelect,
    required this.onOpenConnections,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(lorebookSettingsProvider);
    final activations = ref.watch(lorebookActivationsProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── Global Settings (collapsible) ──
        InkWell(
          onTap: onGlobalExpandToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Icon(Icons.tune_outlined, size: 16, color: context.cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Global Settings',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.cs.primary,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: globalExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, size: 18, color: context.cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _GlobalSettingsPanel(settings: settings),
          crossFadeState: globalExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),

        Divider(height: 1, color: context.cs.outlineVariant.withValues(alpha: 0.3)),
        const SizedBox(height: 4),

        if (lorebooks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.menu_book_outlined, size: 40, color: context.cs.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'No lorebooks yet.',
                  style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Import a backup or create one in the Lorebook Manager.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 12),
                ),
              ],
            ),
          )
        else
          ...lorebooks.map((lb) {
            final charCount = activations.character.entries.where((e) => e.value.contains(lb.id)).length;
            final chatCount = activations.chat.entries.where((e) => e.value.contains(lb.id)).length;

            return InkWell(
              onTap: () => onSelect(lb),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      lb.enabled ? Icons.menu_book : Icons.menu_book_outlined,
                      size: 20,
                      color: lb.enabled ? context.cs.primary : context.cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lb.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: context.cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                '${lb.entries.length} entries',
                                style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
                              ),
                              if (lb.enabled) ...[
                                const SizedBox(width: 6),
                                _Badge('Global', Colors.green),
                              ],
                              if (charCount > 0) ...[
                                const SizedBox(width: 4),
                                _Badge('$charCount char', Colors.purple),
                              ],
                              if (chatCount > 0) ...[
                                const SizedBox(width: 4),
                                _Badge('$chatCount chat', Colors.orange),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Connections button
                    IconButton(
                      icon: Icon(
                        Icons.link,
                        size: 18,
                        color: (lb.enabled || charCount > 0 || chatCount > 0)
                            ? context.cs.primary
                            : context.cs.onSurfaceVariant,
                      ),
                      tooltip: 'Connections',
                      onPressed: () => onOpenConnections(lb),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: context.cs.onSurfaceVariant),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// View: Entries
// ─────────────────────────────────────────────────────────────

class _EntriesView extends ConsumerWidget {
  final Lorebook lorebook;
  final String charId;
  final TextEditingController searchController;
  final VoidCallback onOpenEditor;

  const _EntriesView({
    required this.lorebook,
    required this.charId,
    required this.searchController,
    required this.onOpenEditor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lorebooks = ref.watch(lorebooksProvider).value ?? [];
    final lb = lorebooks.where((l) => l.id == lorebook.id).firstOrNull ?? lorebook;
    final query = searchController.text.toLowerCase();

    final entries = lb.entries.where((e) {
      if (query.isEmpty) return true;
      return e.comment.toLowerCase().contains(query) ||
          e.keys.any((k) => k.toLowerCase().contains(query)) ||
          e.content.toLowerCase().contains(query);
    }).toList();

    if (lb.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 40, color: context.cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('No entries', style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14)),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onOpenEditor,
                child: const Text('Open Editor'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: entries.isEmpty ? 1 : entries.length + 1,
      itemBuilder: (context, i) {
        // Footer: open editor button
        if (i == (entries.isEmpty ? 0 : entries.length)) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open Full Editor'),
              onPressed: onOpenEditor,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.cs.primary,
                side: BorderSide(color: context.cs.primary.withValues(alpha: 0.4)),
              ),
            ),
          );
        }

        if (entries.isEmpty) return const SizedBox.shrink();

        final entry = entries[i];
        final name = entry.comment.isNotEmpty ? entry.comment : entry.keys.join(', ');
        final hint = entry.constant ? 'constant' : (entry.keys.isNotEmpty ? entry.keys.first : '');

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
            leading: Icon(
              entry.enabled ? Icons.description : Icons.description_outlined,
              size: 20,
              color: entry.enabled ? context.cs.primary : context.cs.onSurfaceVariant,
            ),
            title: Text(
              name,
              style: TextStyle(fontSize: 14, color: context.cs.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: hint.isNotEmpty
                ? Text(
                    hint,
                    style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.vectorSearch)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Badge('vec', Colors.blue),
                  ),
                if (entry.constant)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Badge('const', Colors.amber),
                  ),
                Switch(
                  value: entry.enabled,
                  activeThumbColor: context.cs.primary,
                  onChanged: (v) {
                    final notifier = ref.read(lorebooksProvider.notifier);
                    final updatedEntries = lb.entries.map((e) => e.id == entry.id ? e.copyWith(enabled: v) : e).toList();
                    notifier.updateLorebook(lb.copyWith(entries: updatedEntries));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Global Settings Panel (collapsible)
// ─────────────────────────────────────────────────────────────

class _GlobalSettingsPanel extends ConsumerWidget {
  final LorebookGlobalSettings settings;
  const _GlobalSettingsPanel({required this.settings});

  void _update(WidgetRef ref, LorebookGlobalSettings s) {
    ref.read(lorebookSettingsProvider.notifier).state = s;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsRow(
            label: 'Search Type',
            child: _SegmentedPicker<String>(
              value: settings.searchType,
              options: const [
                ('keyword', 'Keys'),
                ('vector', 'Vector'),
                ('both', 'Hybrid'),
              ],
              onChanged: (v) => _update(ref, settings.copyWith(searchType: v)),
            ),
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            label: 'Injection Position',
            child: _SegmentedPicker<String>(
              value: settings.injectionPosition,
              options: const [
                ('worldInfoBefore', 'Before char'),
                ('worldInfoAfter', 'After char'),
                ('lorebooksMacro', '{{lorebooks}}'),
              ],
              onChanged: (v) => _update(ref, settings.copyWith(injectionPosition: v)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SettingsRow(
                  label: 'Scan Depth',
                  child: _SmallNumberField(
                    value: settings.scanDepth,
                    onChanged: (v) => _update(ref, settings.copyWith(scanDepth: v)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SettingsRow(
                  label: 'Max Entries',
                  child: _SmallNumberField(
                    value: settings.maxInjectedEntries,
                    onChanged: (v) => _update(ref, settings.copyWith(maxInjectedEntries: v)),
                  ),
                ),
              ),
            ],
          ),
          if (settings.searchType != 'keyword') ...[
            const SizedBox(height: 10),
            _SettingsRow(
              label: 'Similarity Threshold',
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: settings.vectorThreshold,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      activeColor: context.cs.primary,
                      onChanged: (v) => _update(ref, settings.copyWith(vectorThreshold: v)),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      settings.vectorThreshold.toStringAsFixed(2),
                      style: TextStyle(fontSize: 12, color: context.cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _SettingsRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _SegmentedPicker<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const _SegmentedPicker({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: options.map((opt) {
        final selected = opt.$1 == value;
        return GestureDetector(
          onTap: () => onChanged(opt.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? context.cs.primary.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? context.cs.primary.withValues(alpha: 0.6) : context.cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              opt.$2,
              style: TextStyle(
                fontSize: 11,
                color: selected ? context.cs.primary : context.cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SmallNumberField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _SmallNumberField({required this.value, required this.onChanged});

  @override
  State<_SmallNumberField> createState() => _SmallNumberFieldState();
}

class _SmallNumberFieldState extends State<_SmallNumberField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_SmallNumberField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value.toString()) {
      _ctrl.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: TextFormField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        style: TextStyle(color: context.cs.onSurface, fontSize: 13),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null && n > 0) widget.onChanged(n);
        },
      ),
    );
  }
}
