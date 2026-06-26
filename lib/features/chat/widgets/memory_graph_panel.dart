import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/db_provider.dart';
import '../../../core/state/memory_agent_providers.dart';
import '../../../shared/theme/app_colors.dart';

class MemoryGraphPanel extends ConsumerStatefulWidget {
  final String sessionId;

  const MemoryGraphPanel({super.key, required this.sessionId});

  @override
  ConsumerState<MemoryGraphPanel> createState() => _MemoryGraphPanelState();
}

class _MemoryGraphPanelState extends ConsumerState<MemoryGraphPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _rebuilding = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    'Memory Graph',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (_rebuilding)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: _rebuilding ? null : _rebuildGraph,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Rebuild'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Entities'),
                Tab(text: 'Arcs'),
                Tab(text: 'Errors'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _entitiesTab(),
                  _arcsTab(),
                  _errorsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entitiesTab() {
    return FutureBuilder(
      future: ref.read(memoryEntityRepoProvider).getBySessionId(
        widget.sessionId,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entities = snapshot.data!;
        if (entities.isEmpty) {
          return const Center(
            child: Text('No entities extracted yet. Run Rebuild to populate.'),
          );
        }
        return ListView.builder(
          itemCount: entities.length,
          itemBuilder: (context, index) {
            final e = entities[index];
            return ListTile(
              leading: Icon(
                e.entityType == 'character'
                    ? Icons.person_outline
                    : Icons.place_outlined,
                size: 20,
                color: context.cs.primary,
              ),
              title: Text(e.name),
              subtitle: Text(
                '${e.entityType} · salience ${e.salienceAvg.toStringAsFixed(2)} · ${e.mentionCount} mentions'
                '${e.aliases.isNotEmpty ? " · aliases: ${e.aliases.join(", ")}" : ""}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: e.status == 'active'
                  ? null
                  : Text(
                      e.status,
                      style: TextStyle(
                        fontSize: 11,
                        color: e.status == 'deceased'
                            ? Colors.red
                            : context.cs.onSurfaceVariant,
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _arcsTab() {
    return FutureBuilder(
      future: ref.read(memoryConsolidationRepoProvider).getBySessionId(
        widget.sessionId,
        tier: 2,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final arcs = snapshot.data!;
        if (arcs.isEmpty) {
          return const Center(
            child: Text(
              'No arc summaries. Enable consolidation in memory settings '
              'and accumulate enough entries.',
            ),
          );
        }
        return ListView.builder(
          itemCount: arcs.length,
          itemBuilder: (context, index) {
            final arc = arcs[index];
            return ExpansionTile(
              title: Text(arc.title),
              subtitle: Text(
                'range ${arc.messageRangeStart}-${arc.messageRangeEnd}',
                style: const TextStyle(fontSize: 12),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(arc.summary),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _errorsTab() {
    return FutureBuilder(
      future: ref.read(memoryConsolidationRepoProvider).getBySessionId(
        widget.sessionId,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final errors = snapshot.data!.where((c) => c.status == 'error').toList();
        if (errors.isEmpty) {
          return const Center(child: Text('No consolidation errors.'));
        }
        return ListView.builder(
          itemCount: errors.length,
          itemBuilder: (context, index) {
            final e = errors[index];
            return ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text('Tier ${e.tier}: ${e.title}'),
              subtitle: Text(
                e.errorMessage,
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  await ref
                      .read(memoryConsolidationRepoProvider)
                      .updateStatus(e.id, 'pending', null);
                  setState(() {});
                },
                child: const Text('Retry'),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _rebuildGraph() async {
    setState(() => _rebuilding = true);
    try {
      final bookRepo = ref.read(memoryBookRepoProvider);
      final book = await bookRepo.getBySessionId(widget.sessionId);
      if (book == null) return;
      final builder = ref.read(memoryGraphBuilderProvider);
      await builder.rebuildSession(
        widget.sessionId,
        book.entries,
      );
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }
}
