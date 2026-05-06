import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../catalog_models.dart';

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

  @override
  void initState() {
    super.initState();
    _nsfw = widget.filters.nsfw;
    _nsfl = widget.filters.nsfl;
    _minTokens = widget.filters.minTokens;
    _maxTokens = widget.filters.maxTokens;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Filters',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _toggleTile('NSFW', _nsfw, (v) => setState(() => _nsfw = v)),
        if (widget.provider == CatalogProvider.chub)
          _toggleTile('NSFL', _nsfl, (v) => setState(() => _nsfl = v)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _tokenField(
                  'Min tokens',
                  _minTokens,
                  (v) => setState(() => _minTokens = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tokenField(
                  'Max tokens',
                  _maxTokens,
                  (v) => setState(() => _maxTokens = v),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _nsfw = false;
                    _nsfl = false;
                    _minTokens = 29;
                    _maxTokens = 100000;
                  }),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Center(
                      child: Text(
                        'Reset',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () {
                    widget.onApply(
                      CatalogFilters(
                        sort: widget.filters.sort,
                        nsfw: _nsfw,
                        nsfl: _nsfl,
                        tagIds: widget.filters.tagIds,
                        tagNames: widget.filters.tagNames,
                        minTokens: _minTokens,
                        maxTokens: _maxTokens,
                      ),
                    );
                    Navigator.pop(context);
                  },
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Apply',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toggleTile(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          ),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
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
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: TextField(
            controller: TextEditingController(text: '$value'),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
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
}
