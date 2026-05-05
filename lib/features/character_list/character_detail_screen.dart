import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../core/models/character.dart';
import '../../core/state/db_provider.dart';

class CharacterDetailScreen extends ConsumerWidget {
  final String charId;
  const CharacterDetailScreen({super.key, required this.charId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/characters')),
        title: const Text('Character Info'),
      ),
      body: FutureBuilder<Character?>(
        future: ref.read(characterRepoProvider).getById(charId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final char = snap.data;
          if (char == null) {
            return const Center(child: Text('Character not found'));
          }
          return _CharacterDetailView(character: char);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.go('/chat/$charId'),
                  icon: const Icon(Icons.chat_bubble),
                  label: const Text('Start Chat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterDetailView extends StatelessWidget {
  final Character character;
  const _CharacterDetailView({required this.character});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                _buildAvatar(context, 96),
                const SizedBox(height: 12),
                Text(character.name,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (character.creator != null &&
                    character.creator!.isNotEmpty)
                  Text('by ${character.creator}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (character.tags.isNotEmpty) ...[
            _SectionLabel('Tags'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: character.tags
                  .map((t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (character.description != null &&
              character.description!.isNotEmpty) ...[
            _SectionLabel('Description'),
            const SizedBox(height: 4),
            _ExpandableText(character.description!),
            const SizedBox(height: 16),
          ],
          if (character.personality != null &&
              character.personality!.isNotEmpty) ...[
            _SectionLabel('Personality'),
            const SizedBox(height: 4),
            _ExpandableText(character.personality!),
            const SizedBox(height: 16),
          ],
          if (character.scenario != null &&
              character.scenario!.isNotEmpty) ...[
            _SectionLabel('Scenario'),
            const SizedBox(height: 4),
            _ExpandableText(character.scenario!),
            const SizedBox(height: 16),
          ],
          if (character.firstMes != null &&
              character.firstMes!.isNotEmpty) ...[
            _SectionLabel('First Message'),
            const SizedBox(height: 4),
            _ExpandableText(character.firstMes!),
            const SizedBox(height: 16),
          ],
          if (character.mesExample != null &&
              character.mesExample!.isNotEmpty) ...[
            _SectionLabel('Example Dialogue'),
            const SizedBox(height: 4),
            _ExpandableText(character.mesExample!),
            const SizedBox(height: 16),
          ],
          if (character.systemPrompt != null &&
              character.systemPrompt!.isNotEmpty) ...[
            _SectionLabel('System Prompt'),
            const SizedBox(height: 4),
            _ExpandableText(character.systemPrompt!),
            const SizedBox(height: 16),
          ],
          if (character.postHistoryInstructions != null &&
              character.postHistoryInstructions!.isNotEmpty) ...[
            _SectionLabel('Post-History Instructions'),
            const SizedBox(height: 4),
            _ExpandableText(character.postHistoryInstructions!),
            const SizedBox(height: 16),
          ],
          if (character.creatorNotes != null &&
              character.creatorNotes!.isNotEmpty) ...[
            _SectionLabel('Creator Notes'),
            const SizedBox(height: 4),
            _ExpandableText(character.creatorNotes!),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, double radius) {
    if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
      final file = File(character.avatarPath!);
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(file),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
        style: TextStyle(fontSize: radius * 0.6),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ));
  }
}

class _ExpandableText extends StatefulWidget {
  final String text;
  const _ExpandableText(this.text);

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    if (widget.text.length <= 300 || _expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(widget.text, style: style),
          if (widget.text.length > 300)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _expanded = false),
                child: const Text('Show less'),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.text.substring(0, 300) + '...', style: style),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _expanded = true),
            child: const Text('Show more'),
          ),
        ),
      ],
    );
  }
}
