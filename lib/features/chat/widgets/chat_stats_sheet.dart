import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/state/db_provider.dart';
import '../../../core/models/character.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/rolling_number.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../../../shared/widgets/glaze_tab_bar.dart';
import '../chat_provider.dart';

class _StatsData {
  final int tokens;
  final int characters;
  final int messages;
  final int regenerations;
  final int deleted;
  final int timeSpent;
  final String firstMessage;

  const _StatsData({
    this.tokens = 0,
    this.characters = 0,
    this.messages = 0,
    this.regenerations = 0,
    this.deleted = 0,
    this.timeSpent = 0,
    this.firstMessage = '-',
  });

  _StatsData copyWith({
    int? tokens,
    int? characters,
    int? messages,
    int? regenerations,
    int? deleted,
    int? timeSpent,
    String? firstMessage,
  }) {
    return _StatsData(
      tokens: tokens ?? this.tokens,
      characters: characters ?? this.characters,
      messages: messages ?? this.messages,
      regenerations: regenerations ?? this.regenerations,
      deleted: deleted ?? this.deleted,
      timeSpent: timeSpent ?? this.timeSpent,
      firstMessage: firstMessage ?? this.firstMessage,
    );
  }
}

class ChatStatsSheet extends ConsumerStatefulWidget {
  final String initialCharId;

  const ChatStatsSheet({super.key, required this.initialCharId});

  @override
  ConsumerState<ChatStatsSheet> createState() => _ChatStatsSheetState();
}

class _ChatStatsSheetState extends ConsumerState<ChatStatsSheet> {
  String _currentTab = 'chat';
  String? _selectedCharId;
  List<Character> _allCharacters = [];
  bool _showCharDropdown = false;
  bool _loading = true;

  _StatsData _chatStats = const _StatsData();
  _StatsData _charStats = const _StatsData();
  _StatsData _generalStats = const _StatsData();

  Timer? _updateInterval;

  @override
  void initState() {
    super.initState();
    _selectedCharId = widget.initialCharId;
    _initData();
    _updateInterval = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimeStats();
    });
  }

  @override
  void dispose() {
    _updateInterval?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    final charRepo = ref.read(characterRepoProvider);
    _allCharacters = await charRepo.getAll();
    await _calculateStats();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateTimeStats() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();

    int chatTime = 0;
    int charTime = 0;
    int generalTime = 0;

    for (final key in prefs.getKeys()) {
      if (key.startsWith('chat_time_')) {
        final t = prefs.getInt(key) ?? 0;
        generalTime += t;
        final cid = key.replaceFirst('chat_time_', '');
        if (cid == _selectedCharId) {
          charTime += t;
          chatTime += t; 
        }
      }
    }

    setState(() {
      _generalStats = _generalStats.copyWith(timeSpent: generalTime);
      _charStats = _charStats.copyWith(timeSpent: charTime);
      _chatStats = _chatStats.copyWith(timeSpent: chatTime);
    });
  }

  Future<void> _calculateStats() async {
    final repo = ref.read(chatRepoProvider);
    final allSessions = await repo.getAllSessions();
    final currentSession =
        ref.read(chatProvider(widget.initialCharId)).value?.session;
    final currentSessionId = currentSession?.id;

    int chatMsg = 0, chatTok = 0, chatChar = 0, chatRegen = 0, chatDel = 0;
    int charMsg = 0, charTok = 0, charChar = 0, charRegen = 0, charDel = 0;
    int genMsg = 0, genTok = 0, genChar = 0, genRegen = 0, genDel = 0;

    int? chatFirstMsg, charFirstMsg, genFirstMsg;

    for (final session in allSessions) {
      final isCurrentChar = session.characterId == _selectedCharId;
      final isCurrentChat = isCurrentChar && session.id == currentSessionId;

      for (final msg in session.messages) {
        final int tokens = (msg.tokens?.toInt()) ?? (msg.content.length ~/ 4);
        final int chars = msg.content.length.toInt();
        final int regens = msg.swipes.length > 1 ? (msg.swipes.length - 1).toInt() : 0;
        final isDeleted = msg.isHidden;
        final ts = msg.timestamp;

        // General
        genMsg++;
        genTok += tokens;
        genChar += chars;
        genRegen += regens;
        if (isDeleted) genDel++;
        if (ts != null && (genFirstMsg == null || ts < genFirstMsg)) {
          genFirstMsg = ts;
        }

        // Character
        if (isCurrentChar) {
          charMsg++;
          charTok += tokens;
          charChar += chars;
          charRegen += regens;
          if (isDeleted) charDel++;
          if (ts != null && (charFirstMsg == null || ts < charFirstMsg)) {
            charFirstMsg = ts;
          }
        }

        // Chat
        if (isCurrentChat) {
          chatMsg++;
          chatTok += tokens;
          chatChar += chars;
          chatRegen += regens;
          if (isDeleted) chatDel++;
          if (ts != null && (chatFirstMsg == null || ts < chatFirstMsg)) {
            chatFirstMsg = ts;
          }
        }
      }
    }

    String formatDate(int? ts) {
      if (ts == null) return '-';
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    setState(() {
      _chatStats = _chatStats.copyWith(
        messages: chatMsg,
        tokens: chatTok,
        characters: chatChar,
        regenerations: chatRegen,
        deleted: chatDel,
        firstMessage: formatDate(chatFirstMsg),
      );
      _charStats = _charStats.copyWith(
        messages: charMsg,
        tokens: charTok,
        characters: charChar,
        regenerations: charRegen,
        deleted: charDel,
        firstMessage: formatDate(charFirstMsg),
      );
      _generalStats = _generalStats.copyWith(
        messages: genMsg,
        tokens: genTok,
        characters: genChar,
        regenerations: genRegen,
        deleted: genDel,
        firstMessage: formatDate(genFirstMsg),
      );
    });

    await _updateTimeStats();
  }

  String _formatTime(int seconds) {
    if (seconds == 0) return '0s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  _StatsData get _currentStats {
    switch (_currentTab) {
      case 'char':
        return _charStats;
      case 'general':
        return _generalStats;
      case 'chat':
      default:
        return _chatStats;
    }
  }


  Widget _buildHero(_StatsData stats) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.colors.accent,
            Color.lerp(context.colors.accent, Colors.black, 0.2)!,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          RollingNumber(
            value: _loading ? '...' : _formatNumber(stats.messages),
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'MESSAGES',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.75),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      RollingNumber(
                        value: _loading ? '...' : _formatNumber(stats.tokens),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'TOKENS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.65),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                    width: 1,
                    height: 28,
                    color: Colors.white.withValues(alpha: 0.2)),
                Expanded(
                  child: Column(
                    children: [
                      RollingNumber(
                        value: _loading ? '...' : _formatNumber(stats.characters),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'CHARACTERS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.65),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool isDate = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          isDate
              ? AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    value,
                    key: ValueKey(value),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textSecondary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                )
              : RollingNumber(
                  value: value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textSecondary,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSeparator() {
    return Padding(
      padding: const EdgeInsets.only(left: 64),
      child: Container(
        height: 0.5,
        color: Colors.white.withValues(alpha: 0.06),
      ),
    );
  }

  Widget _buildCharPicker() {
    final selectedChar = _allCharacters
        .where((c) => c.id == _selectedCharId)
        .firstOrNull;
    final charName = selectedChar?.name ?? '—';
    final charColor = selectedChar?.color ?? '#66ccff';
    final parsedColor = Color(int.parse(charColor.replaceFirst('#', '0xFF')));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showCharDropdown = !_showCharDropdown),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: parsedColor,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: selectedChar?.avatarPath != null
                      ? Image.file(
                          File(selectedChar!.avatarPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildInitials(charName),
                        )
                      : _buildInitials(charName),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    charName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _showCharDropdown
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(height: 0, width: double.infinity),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: const Color(0xFF282828).withValues(alpha: 0.9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _allCharacters.length,
                separatorBuilder: (context, index) => Container(
                  height: 0.5,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                itemBuilder: (context, index) {
                  final char = _allCharacters[index];
                  final active = char.id == _selectedCharId;
                  final cColor = Color(
                      int.parse((char.color ?? '#66ccff').replaceFirst('#', '0xFF')));
                  return InkWell(
                    onTap: () async {
                      setState(() {
                        _selectedCharId = char.id;
                        _showCharDropdown = false;
                        _loading = true;
                      });
                      await _calculateStats();
                      if (mounted) {
                        setState(() => _loading = false);
                      }
                    },
                    child: Container(
                      color: active
                          ? context.colors.accent.withValues(alpha: 0.08)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: cColor,
                              shape: BoxShape.circle,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: char.avatarPath != null
                                ? Image.file(
                                    File(char.avatarPath!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _buildInitials(char.name),
                                  )
                                : _buildInitials(char.name),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              char.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: context.colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (active)
                            Icon(
                              Icons.check,
                              color: context.colors.accent,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          crossFadeState: _showCharDropdown
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildInitials(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _currentStats;

    return SheetView(
      title: 'Statistics',
      showHandle: true,
      headerBottom: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: GlazeTabBar(
          tabs: const [
            GlazeTabItem(label: 'Chat', icon: Icons.chat_bubble),
            GlazeTabItem(label: 'Character', icon: Icons.person),
            GlazeTabItem(label: 'General', icon: Icons.public),
          ],
          activeIndex: _currentTab == 'chat' ? 0 : (_currentTab == 'char' ? 1 : 2),
          onChanged: (index) {
            setState(() {
              _currentTab = index == 0 ? 'chat' : (index == 1 ? 'char' : 'general');
            });
          },
        ),
      ),
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + 12,
            16,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          children: [
            if (_currentTab == 'char') ...[
              _buildCharPicker(),
              const SizedBox(height: 12),
            ],
            _buildHero(stats),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildStatItem(
                    icon: Icons.refresh,
                    color: const Color(0xFF4CAF50),
                    label: 'Regenerations',
                    value: _loading ? '...' : _formatNumber(stats.regenerations),
                  ),
                  _buildSeparator(),
                  _buildStatItem(
                    icon: Icons.delete_outline,
                    color: const Color(0xFFF44336),
                    label: 'Deleted',
                    value: _loading ? '...' : _formatNumber(stats.deleted),
                  ),
                  _buildSeparator(),
                  _buildStatItem(
                    icon: Icons.access_time,
                    color: const Color(0xFF2196F3),
                    label: _currentTab == 'general' ? 'App Time' : 'Time Spent',
                    value: _loading ? '...' : _formatTime(stats.timeSpent),
                  ),
                  _buildSeparator(),
                  _buildStatItem(
                    icon: Icons.history,
                    color: const Color(0xFFFF9800),
                    label: 'First Message',
                    value: _loading ? '...' : stats.firstMessage,
                    isDate: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
