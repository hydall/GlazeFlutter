import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../catalog_models.dart';
import '../services/chub_provider.dart';
import '../services/datacat_provider.dart';
import '../services/janitor_provider.dart';

class CatalogFilterSheet extends StatefulWidget {
  final CatalogFilters filters;
  final CatalogProvider provider;
  final ValueChanged<CatalogFilters> onApply;

  const CatalogFilterSheet({
    super.key,
    required this.filters,
    required this.provider,
    required this.onApply,
  });

  @override
  State<CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<CatalogFilterSheet> {
  late bool _nsfw;
  late bool _nsfl;
  late int _minTokens;
  late int _maxTokens;

  Set<int> _selectedTagIds = {};
  Set<String> _selectedTagNames = {};

  List<CatalogTag> _allTags = [];
  String _tagSearch = '';

  @override
  void initState() {
    super.initState();
    _nsfw = widget.filters.nsfw;
    _nsfl = widget.filters.nsfl;
    _minTokens = widget.filters.minTokens;
    _maxTokens = widget.filters.maxTokens;
    _selectedTagIds = Set.from(widget.filters.tagIds);
    _selectedTagNames = Set.from(widget.filters.tagNames);

    _loadTags();
  }

  Future<void> _loadTags() async {
    List<CatalogTag> tags = [];
    if (widget.provider == CatalogProvider.chub) {
      tags = await fetchChubTags();
    } else if (widget.provider == CatalogProvider.datacat) {
      tags = await fetchDatacatTags();
    } else {
      tags = await fetchJanitorTags();
    }

    // Sort alphabetically
    tags.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (mounted) {
      setState(() {
        _allTags = tags;
      });
    }
  }

  @override
  void dispose() {
    // Only apply if changed
    final changed = _nsfw != widget.filters.nsfw ||
        _nsfl != widget.filters.nsfl ||
        _minTokens != widget.filters.minTokens ||
        _maxTokens != widget.filters.maxTokens ||
        _selectedTagIds.length != widget.filters.tagIds.length ||
        _selectedTagNames.length != widget.filters.tagNames.length ||
        !_selectedTagIds.containsAll(widget.filters.tagIds) ||
        !_selectedTagNames.containsAll(widget.filters.tagNames);

    if (changed) {
      final newTagIds = _selectedTagIds.toList()..sort();
      final newTagNames = _selectedTagNames.toList()..sort();
      final apply = widget.onApply;

      Future.microtask(() {
        apply(
          CatalogFilters(
            sort: widget.filters.sort,
            nsfw: _nsfw,
            nsfl: _nsfl,
            tagIds: newTagIds,
            tagNames: newTagNames,
            minTokens: _minTokens,
            maxTokens: _maxTokens,
          ),
        );
      });
    }
    super.dispose();
  }

  bool _isTagSelected(CatalogTag tag) {
    if (tag.id != null) return _selectedTagIds.contains(tag.id);
    return _selectedTagNames.contains(tag.name);
  }

  void _cycleTag(CatalogTag tag) {
    setState(() {
      if (tag.id != null) {
        if (_selectedTagIds.contains(tag.id)) {
          _selectedTagIds.remove(tag.id);
        } else {
          _selectedTagIds.add(tag.id!);
        }
      } else {
        if (_selectedTagNames.contains(tag.name)) {
          _selectedTagNames.remove(tag.name);
        } else {
          _selectedTagNames.add(tag.name);
        }
      }
    });
  }

  void _clearTags() {
    setState(() {
      _selectedTagIds.clear();
      _selectedTagNames.clear();
    });
  }

  void _onNsflToggle(bool value) {
    if (value) {
      // Trying to enable — show warning
      GlazeBottomSheet.show(
        context,
        title: 'NSFL Content',
        bigInfo: const BottomSheetBigInfo(
          icon: Icons.warning_amber_rounded,
          description: "You don't want to see this.",
        ),
        items: [
          BottomSheetItem(
            label: 'I have nothing to lose',
            isDestructive: true,
            centered: true,
            onTap: () {
              setState(() => _nsfl = true);
              Navigator.of(context, rootNavigator: true).pop();
            },
          ),
          BottomSheetItem(
            label: 'I don\'t want to die',
            centered: true,
            onTap: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      );
    } else {
      // Disabling
      setState(() => _nsfl = false);
    }
  }

  List<CatalogTag> get _filteredTags {
    if (_tagSearch.isEmpty) return _allTags;
    final q = _tagSearch.toLowerCase();
    return _allTags.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  List<CatalogTag> get _selectedTagsList {
    return _allTags.where((t) => _isTagSelected(t)).toList();
  }

  int get _totalSelectedCount => _selectedTagIds.length + _selectedTagNames.length;

  @override
  Widget build(BuildContext context) {
    return SheetView(
      title: 'Filters',
      showHandle: true,
      bodyPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          // NSFW
          _toggleTile('Show NSFW', _nsfw, (v) => setState(() => _nsfw = v)),

            // NSFL
            if (widget.provider == CatalogProvider.chub)
              _toggleTile('Show NSFL', _nsfl, _onNsflToggle, isDanger: true),

            const SizedBox(height: 20),

            // Tokens
            Text(
              'TOKEN RANGE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.cs.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _tokenField('Min', _minTokens, (v) => setState(() => _minTokens = v)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('—', style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 18)),
                ),
                Expanded(
                  child: _tokenField('Max', _maxTokens, (v) => setState(() => _maxTokens = v)),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Tags Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TAGS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.cs.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                if (_totalSelectedCount > 0)
                  GestureDetector(
                    onTap: _clearTags,
                    child: Text(
                      'Clear ($_totalSelectedCount)',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Selected tags preview
            if (_selectedTagsList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selectedTagsList.map((t) => _buildTagChip(t, active: true)).toList(),
                  ),
                ),
              ),

            // Tag Search
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search tags...',
                  hintStyle: TextStyle(color: context.cs.onSurfaceVariant),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _tagSearch = v),
              ),
            ),
            const SizedBox(height: 12),

            // Tags grid
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _filteredTags.map((t) => _buildTagChip(t, active: _isTagSelected(t))).toList(),
            ),
            const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _toggleTile(String label, bool value, ValueChanged<bool> onChanged, {bool isDanger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: context.cs.onSurface, fontSize: 15),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: isDanger ? Colors.redAccent : context.cs.primary,
            activeColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            inactiveThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _tokenField(String label, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: TextField(
            controller: TextEditingController(text: '$value'),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14, color: Colors.white),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            onSubmitted: (v) {
              final p = int.tryParse(v);
              if (p != null) onChanged(p);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTagChip(CatalogTag tag, {required bool active}) {
    return GestureDetector(
      onTap: () => _cycleTag(tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? context.cs.primary : Colors.white.withValues(alpha: 0.12),
          ),
          color: active ? context.cs.primary.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tag.name,
              style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : Colors.white.withValues(alpha: 0.65),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 5),
              const Icon(Icons.close, size: 10, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}
