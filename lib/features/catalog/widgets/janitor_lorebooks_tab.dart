import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/lorebook.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../settings/app_settings_provider.dart';
import '../janitor_account_provider.dart';
import '../services/janitor_extractor.dart';
import '../services/janitor_lorebook_rebuilder.dart';
import '../services/janitor_public_lorebook.dart';

/// Context passed to the catalog-preview Lorebooks tab. Carries the JanitorAI
/// character id, its source URL and the raw `/hampter` metadata (for the
/// attached `scripts`).
class JanitorLorebookArgs {
  final String characterId;
  final String sourceUrl;
  final Map<String, dynamic> meta;
  final bool definitionPublic;

  const JanitorLorebookArgs({
    required this.characterId,
    required this.sourceUrl,
    required this.meta,
    this.definitionPublic = false,
  });
}

/// The catalog card sheet's **Lorebooks** tab — a Flutter port of JAR's
/// `#tabLorebook` UI.
///
/// - **Public lorebooks** attached to the character are downloaded whole
///   (`/hampter/script/{id}`) and can be saved to Glaze or exported as a
///   SillyTavern World Info `.json`.
/// - **Closed lorebooks** are recovered by capturing the assembled prompt via
///   the proxy ([JanitorExtractor.extract]) and rebuilt into structured entries
///   with the active LLM ([JanitorExtractor.buildLorebook]). Context-source
///   checkboxes pick what the build LLM may use to infer trigger keys.
class JanitorLorebooksTab extends ConsumerStatefulWidget {
  final JanitorLorebookArgs args;
  const JanitorLorebooksTab({super.key, required this.args});

  @override
  ConsumerState<JanitorLorebooksTab> createState() =>
      _JanitorLorebooksTabState();
}

/// Which context blocks the build LLM may use to infer trigger keys.
class _ContextSources {
  bool card = true;
  bool catalog = true;
  bool scenario = true;
  bool greetings = false;
  bool lorebookDescs = true;
  bool extra = false;
}

class _JanitorLorebooksTabState extends ConsumerState<JanitorLorebooksTab> {
  // Public lorebooks.
  bool _loadingPublic = true;
  List<PublicLorebook> _public = const [];

  // Closed-lorebook extraction.
  bool _extracting = false;
  String? _extractPhase;
  String? _extractError;
  ExtractionResult? _extraction;

  // Build.
  final _sources = _ContextSources();
  final _extraController = TextEditingController();
  final _nameController = TextEditingController();
  bool _building = false;
  String? _buildError;
  Lorebook? _built;
  List<Map<String, String>>? _previewMessages;
  Timer? _timer;
  int _elapsed = 0;

  List<JanitorScriptRef> get _scriptRefs =>
      lorebookScriptRefs(widget.args.meta);

  /// There is hidden lore to recover when the card itself is closed or the
  /// character lists a non-public lorebook.
  bool get _hasClosed =>
      !widget.args.definitionPublic ||
      _scriptRefs.any((r) => !r.isPublic) ||
      _public.any((b) => !b.accessible);

  @override
  void initState() {
    super.initState();
    _loadPublic();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _extraController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadPublic() async {
    final books = await fetchPublicLorebooks(widget.args.meta);
    if (!mounted) return;
    setState(() {
      _public = books;
      _loadingPublic = false;
    });
  }

  // ─── Public lorebook actions ───────────────────────────────────────────────

  void _downloadPublic(PublicLorebook book) {
    GlazeBottomSheet.show<void>(
      context,
      items: [
        BottomSheetItem(
          icon: Icons.bookmark_add_outlined,
          label: 'Save to Glaze',
          onTap: () async {
            Navigator.of(context, rootNavigator: true).pop();
            await _saveLorebook(book.toLorebook());
          },
        ),
        BottomSheetItem(
          icon: Icons.download_outlined,
          label: 'Export .json (SillyTavern)',
          onTap: () async {
            Navigator.of(context, rootNavigator: true).pop();
            await _exportJson(book.toTavernJson(),
                book.title.isNotEmpty ? book.title : 'lorebook');
          },
        ),
      ],
    );
  }

  Future<void> _saveLorebook(Lorebook book) async {
    try {
      await ref.read(lorebooksProvider.notifier).addLorebook(book);
      if (mounted) {
        GlazeToast.show(
            context, 'Saved "${book.name}" (${book.entries.length} entries)');
      }
    } catch (e) {
      if (mounted) GlazeToast.show(context, 'Save failed: $e');
    }
  }

  Future<void> _exportJson(Map<String, dynamic> json, String name) async {
    try {
      final safe = name.replaceAll(RegExp(r'[^\w\- ]+'), '').trim();
      await FileExportService.export(
        data: const JsonEncoder.withIndent('  ').convert(json),
        filename: '${safe.isEmpty ? 'lorebook' : safe}.json',
        subfolder: 'Lorebooks',
      );
      if (mounted) GlazeToast.show(context, 'Exported $name.json');
    } catch (e) {
      if (mounted) GlazeToast.show(context, 'Export failed: $e');
    }
  }

  // ─── Closed-lorebook extraction + build ─────────────────────────────────────

  Future<void> _extract() async {
    setState(() {
      _extracting = true;
      _extractError = null;
      _extractPhase = null;
      _extraction = null;
      _built = null;
      _previewMessages = null;
      _buildError = null;
    });
    try {
      final result = await ref.read(janitorExtractorProvider).extract(
            widget.args.sourceUrl,
            onPhase: (p) {
              if (mounted) setState(() => _extractPhase = p);
            },
          );
      if (!mounted) return;
      setState(() {
        _extraction = result;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text =
              '${result.character.charData.name} — Closed Lorebook';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _extractError = e.toString());
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _build() async {
    final ex = _extraction;
    if (ex == null) return;
    setState(() {
      _building = true;
      _buildError = null;
      _built = null;
      _elapsed = 0;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
    try {
      final book = await ref.read(janitorExtractorProvider).buildLorebook(
            lorebookText: ex.lorebookText,
            name: _nameController.text.trim().isEmpty
                ? '${ex.character.charData.name} — Closed Lorebook'
                : _nameController.text.trim(),
            card: _sources.card ? ex.cardContext : '',
            catalog: _sources.catalog ? ex.catalogContext : '',
            scenario: _sources.scenario ? ex.scenarioContext : '',
            greetings: _sources.greetings ? ex.greetingsContext : '',
            lorebookDescs: _sources.lorebookDescs ? ex.lorebookDescsContext : '',
            extra: _sources.extra ? _extraController.text.trim() : '',
          );
      if (mounted) setState(() => _built = book);
    } catch (e) {
      if (mounted) setState(() => _buildError = e.toString());
    } finally {
      _timer?.cancel();
      if (mounted) setState(() => _building = false);
    }
  }

  void _preview() {
    final ex = _extraction;
    if (ex == null) return;
    setState(() {
      _previewMessages = buildLorebookMessages(
        ex.lorebookText,
        card: _sources.card ? ex.cardContext : '',
        catalog: _sources.catalog ? ex.catalogContext : '',
        scenario: _sources.scenario ? ex.scenarioContext : '',
        greetings: _sources.greetings ? ex.greetingsContext : '',
        lorebookDescs: _sources.lorebookDescs ? ex.lorebookDescsContext : '',
        extra: _sources.extra ? _extraController.text.trim() : '',
      );
    });
  }

  void _downloadRaw() {
    final ex = _extraction;
    if (ex == null) return;
    _exportJson(
      {
        'name': _nameController.text.trim().isEmpty
            ? 'Janitor Lorebook (raw)'
            : _nameController.text.trim(),
        'rawText': ex.lorebookText,
      },
      'janitor-lorebook-raw',
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PublicSection(
            loading: _loadingPublic,
            books: _public,
            onDownload: _downloadPublic,
          ),
          if (_hasClosed) ...[
            const SizedBox(height: 20),
            _SectionTitle('Closed lorebook', cs: cs),
            const SizedBox(height: 4),
            Text(
              'Recover the hidden lorebook by capturing the assembled prompt '
              'through your Janitor.AI session, then rebuild it into keyed '
              'entries with your active LLM.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _buildExtractControls(cs),
            if (_extraction != null) ...[
              const SizedBox(height: 16),
              _buildBuildBlock(cs),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildExtractControls(ColorScheme cs) {
    final loggedIn = ref.watch(janitorAccountProvider).isLoggedIn;
    final enabled =
        ref.watch(appSettingsProvider).value?.extractJanitorLocally ?? false;
    final canExtract = loggedIn && enabled && !_extracting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!enabled)
          _Hint(
            'Enable "Extract lorebooks and characters locally using Janitor.AI '
            'account" in Settings to extract closed lorebooks.',
            cs: cs,
          )
        else if (!loggedIn)
          _Hint('Log in to Janitor.AI (catalog menu) to extract.', cs: cs),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: canExtract ? _extract : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
              icon: _extracting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_extraction == null ? 'Extract' : 'Re-extract'),
            ),
            const SizedBox(width: 12),
            if (_extracting && _extractPhase != null)
              Expanded(
                child: Text(_extractPhase!,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
          ],
        ),
        if (_extractError != null) ...[
          const SizedBox(height: 8),
          Text(_extractError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildBuildBlock(ColorScheme cs) {
    final ex = _extraction!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ex.hasLorebook
                ? 'Captured ${ex.entryBlockCount} block(s), '
                    '${ex.lorebookText.length} chars'
                : 'No closed lorebook text was found.',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface),
          ),
          if (ex.hasLorebook) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _downloadRaw,
              icon: const Icon(Icons.notes_rounded, size: 16),
              label: const Text('Download raw (no keys)'),
            ),
            const _OrDivider(),
            _SectionTitle('Build with LLM', cs: cs),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              decoration: _fieldDecoration(cs, 'World info name (optional)'),
            ),
            const SizedBox(height: 12),
            Text(
              'Context sent for key inference (never output as entries):',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            _contextChecks(cs),
            if (_sources.extra) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _extraController,
                maxLines: 3,
                style: TextStyle(fontSize: 13, color: cs.onSurface),
                decoration:
                    _fieldDecoration(cs, 'Optional custom context…'),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _building ? null : _build,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                  ),
                  child: _building
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Text('Building… ${_elapsed}s'),
                        ])
                      : const Text('Build lorebook'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _building ? null : _preview,
                  child: const Text('Preview prompt'),
                ),
              ],
            ),
            if (_buildError != null) ...[
              const SizedBox(height: 8),
              Text(_buildError!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
            if (_previewMessages != null) ...[
              const SizedBox(height: 12),
              _PromptPreview(messages: _previewMessages!, cs: cs),
            ],
            if (_built != null) ...[
              const SizedBox(height: 12),
              _buildResult(cs, _built!),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildResult(ColorScheme cs, Lorebook book) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Built ${book.entries.length} entries',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => _saveLorebook(book),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: const Text('Save to Glaze'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _exportJson(glazeLorebookToTavernJson(book), book.name),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Export .json'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contextChecks(ColorScheme cs) {
    return Column(
      children: [
        _CheckRow(
          label: 'Character card',
          value: _sources.card,
          onChanged: (v) => setState(() => _sources.card = v),
        ),
        _CheckRow(
          label: 'Card description on site',
          value: _sources.catalog,
          onChanged: (v) => setState(() => _sources.catalog = v),
        ),
        _CheckRow(
          label: 'Scenario',
          value: _sources.scenario,
          onChanged: (v) => setState(() => _sources.scenario = v),
        ),
        _CheckRow(
          label: 'First message(s)',
          value: _sources.greetings,
          onChanged: (v) => setState(() => _sources.greetings = v),
        ),
        _CheckRow(
          label: 'Lorebook descriptions',
          value: _sources.lorebookDescs,
          onChanged: (v) => setState(() => _sources.lorebookDescs = v),
        ),
        _CheckRow(
          label: 'Custom text',
          value: _sources.extra,
          onChanged: (v) => setState(() => _sources.extra = v),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(ColorScheme cs, String hint) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        filled: true,
        fillColor: cs.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _PublicSection extends StatelessWidget {
  final bool loading;
  final List<PublicLorebook> books;
  final void Function(PublicLorebook) onDownload;
  const _PublicSection({
    required this.loading,
    required this.books,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    if (loading) {
      return Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Text('Loading public lorebooks…',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      );
    }
    if (books.isEmpty) {
      return Text('No public lorebooks attached.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Public lorebooks', cs: cs),
        const SizedBox(height: 4),
        Text('Downloaded whole from Janitor.AI — no LLM needed.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        for (final b in books) ...[
          _PublicRow(book: b, onDownload: () => onDownload(b)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PublicRow extends StatelessWidget {
  final PublicLorebook book;
  final VoidCallback onDownload;
  const _PublicRow({required this.book, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(book.accessible ? Icons.menu_book_rounded : Icons.lock_outline,
              size: 18,
              color: book.accessible ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title.isEmpty ? 'Lorebook' : book.title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface),
                ),
                Text(
                  book.accessible
                      ? '${book.entryCount} entries'
                      : 'Private — use Extract below',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (book.accessible)
            IconButton(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, size: 20),
              color: cs.primary,
              tooltip: 'Download',
            ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _CheckRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _PromptPreview extends StatelessWidget {
  final List<Map<String, String>> messages;
  final ColorScheme cs;
  const _PromptPreview({required this.messages, required this.cs});

  @override
  Widget build(BuildContext context) {
    final text = messages
        .map((m) => '### ${m['role']}\n${m['content']}')
        .join('\n\n');
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('Prompt sent to the build LLM',
            style: TextStyle(fontSize: 12, color: cs.onSurface)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: cs.onSurfaceVariant,
                    fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _SectionTitle(this.text, {required this.cs});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
      );
}

class _Hint extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _Hint(this.text, {required this.cs});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final line = Expanded(
      child: Divider(color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('OR',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
          ),
          line,
        ],
      ),
    );
  }
}
