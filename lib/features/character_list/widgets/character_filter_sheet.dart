import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../shared/widgets/filter_sheet.dart';

/// Filter state for the My Characters grid. Local characters carry no token
/// count or NSFW flags, so only favorites + tags are filterable.
class CharacterListFilters {
  final bool favOnly;
  final Set<String> tagNames;

  const CharacterListFilters({this.favOnly = false, this.tagNames = const {}});

  bool get isActive => favOnly || tagNames.isNotEmpty;

  int get activeCount => (favOnly ? 1 : 0) + tagNames.length;

  CharacterListFilters copyWith({bool? favOnly, Set<String>? tagNames}) =>
      CharacterListFilters(
        favOnly: favOnly ?? this.favOnly,
        tagNames: tagNames ?? this.tagNames,
      );
}

/// Reuses the shared [FilterSheet] to filter the My Characters grid by
/// favorites and tags. Mirrors [CatalogFilterSheet]'s apply-on-dispose pattern.
class CharacterFilterSheet extends StatefulWidget {
  final CharacterListFilters filters;
  final List<String> allTags;
  final ValueChanged<CharacterListFilters> onApply;

  const CharacterFilterSheet({
    super.key,
    required this.filters,
    required this.allTags,
    required this.onApply,
  });

  @override
  State<CharacterFilterSheet> createState() => _CharacterFilterSheetState();
}

class _CharacterFilterSheetState extends State<CharacterFilterSheet> {
  late bool _favOnly;
  late Set<String> _selectedTagNames;

  @override
  void initState() {
    super.initState();
    _favOnly = widget.filters.favOnly;
    _selectedTagNames = Set.from(widget.filters.tagNames);
  }

  @override
  void dispose() {
    final changed = _favOnly != widget.filters.favOnly ||
        _selectedTagNames.length != widget.filters.tagNames.length ||
        !_selectedTagNames.containsAll(widget.filters.tagNames);

    if (changed) {
      final apply = widget.onApply;
      final result = CharacterListFilters(
        favOnly: _favOnly,
        tagNames: Set.from(_selectedTagNames),
      );
      Future.microtask(() => apply(result));
    }
    super.dispose();
  }

  void _toggleTag(FilterTag tag) {
    setState(() {
      if (!_selectedTagNames.remove(tag.name)) {
        _selectedTagNames.add(tag.name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FilterSheet(
      title: 'catalog_filters'.tr(),
      sections: [
        FilterToggleSection(
          label: 'section_favorites'.tr(),
          value: _favOnly,
          onChanged: (v) => setState(() => _favOnly = v),
        ),
        FilterTagsSection(
          title: 'catalog_tags'.tr(),
          searchHint: 'catalog_search_tags'.tr(),
          tags: [for (final t in widget.allTags) FilterTag(name: t)],
          selectedIds: const {},
          selectedNames: _selectedTagNames,
          onToggle: _toggleTag,
          onClear: () => setState(() => _selectedTagNames.clear()),
        ),
      ],
    );
  }
}
