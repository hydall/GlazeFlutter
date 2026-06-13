import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/character.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/theme_preset.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../chat/widgets/chat_header.dart';
import '../chat/widgets/chat_input_bar.dart';

/// Live preview of a theme preset, framed like the avatar card in
/// generic_editor.dart:319. Intrinsic height; the message style follows the
/// user's `chatLayout` setting (default = standard, no bubbles; bubble = bubbles).
class ThemeChatPreview extends ConsumerWidget {
  final ThemePreset preset;
  final Color borderColor;

  const ThemeChatPreview({
    super.key,
    required this.preset,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = preset.themeMode != 'light';
    final previewFont = preset.uiFontMode == 'glaze' ? kInterFontFamily : null;
    final previewTheme = isDark
        ? AppTheme.dark(preset, fontFamily: previewFont)
        : AppTheme.light(preset, fontFamily: previewFont);
    final previewCharacter = Character(
      id: 'preview_character',
      name: 'Rei',
      color: preset.accentColor,
    );
    final chatLayout = preset.chatLayout;
    final isStandard = chatLayout == 'default';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Theme(
        data: previewTheme,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: previewTheme.scaffoldBackgroundColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: AbsorbPointer(
            child: _PreviewChatScene(
              preset: preset,
              character: previewCharacter,
              isStandard: isStandard,
            ),
          ),
        ),
      ),
    );
  }

  static Color textOn(Color bg) {
    return bg.computeLuminance() > 0.45
        ? const Color(0xFF1C1D22)
        : const Color(0xFFF4F6FA);
  }
}

class _PreviewChatScene extends StatelessWidget {
  final ThemePreset preset;
  final Character character;
  final bool isStandard;

  const _PreviewChatScene({
    required this.preset,
    required this.character,
    required this.isStandard,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cs = context.cs;
    final charText = colors.charText ?? ThemeChatPreview.textOn(cs.surface);
    final userText =
        colors.userText ?? ThemeChatPreview.textOn(colors.userBubble);

    return Material(
      color: cs.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: GlazeAppBar(
              showBack: true,
              onBack: () {},
              titleWidget: ChatHeader(
                character: character,
                sessionName: 'Session #4',
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  color: cs.primary,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _PreviewDateSeparator(label: '24 March 2026'),
          const SizedBox(height: 4),
          if (isStandard) ...[
            _PreviewStandardMessage(
              character: character,
              isUser: false,
              showAvatar: preset.showCharAvatar,
              showName: preset.showCharName,
              metaColor: cs.onSurfaceVariant,
              italicColor: colors.charItalic ?? cs.onSurface,
              quoteColor: colors.charQuote ?? cs.primary,
              fontWeight: preset.charMessageFontWeightValue,
              text: 'Rei watches in silence, waiting for an answer.',
              quoted: '"Lost?"',
              index: 1,
              time: '10:08',
            ),
            _PreviewStandardMessage(
              character: Character(
                id: 'preview_user',
                name: 'You',
                color: preset.accentColor,
              ),
              isUser: true,
              showAvatar: preset.showUserAvatar,
              showName: preset.showUserName,
              metaColor: cs.onSurfaceVariant,
              italicColor: colors.userItalic ?? cs.onSurface,
              quoteColor: colors.userQuote ?? cs.primary,
              fontWeight: preset.userMessageFontWeightValue,
              text: 'I lean against the wall.',
              quoted: '"Not lost. Just looking."',
              index: 2,
              time: '10:09',
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: _PreviewBubble(
                alignment: Alignment.centerLeft,
                color: colors.charBubble,
                textColor: charText,
                italicColor: colors.charItalic,
                quoteColor: colors.charQuote ?? cs.primary,
                radius: preset.charBubbleRadius,
                fontWeight: preset.charMessageFontWeightValue,
                text: 'Rei watches in silence, waiting for an answer.',
                quoted: '"Lost?"',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _PreviewBubble(
                alignment: Alignment.centerRight,
                color: colors.userBubble,
                textColor: userText,
                italicColor: colors.userItalic,
                quoteColor: colors.userQuote ?? cs.primary,
                radius: preset.userBubbleRadius,
                fontWeight: preset.userMessageFontWeightValue,
                text: 'I lean against the wall.',
                quoted: '"Not lost. Just looking."',
              ),
            ),
          ],
          ChatInputBar(
            focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
            isGenerating: false,
            onSend: (_) {},
            initialDraft: '',
          ),
        ],
      ),
    );
  }
}

class _PreviewDateSeparator extends StatelessWidget {
  final String label;
  const _PreviewDateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    final line = context.cs.outlineVariant.withValues(alpha: 0.6);
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: line)),
      ],
    );
  }
}

/// Standard ("default") chat layout — no bubble, full-width italic text,
/// avatar + name + #index row above. Mirrors the standard layout in WebView renderer.
class _PreviewStandardMessage extends StatelessWidget {
  final Character character;
  final bool isUser;
  final bool showAvatar;
  final bool showName;
  final Color metaColor;
  final Color italicColor;
  final Color quoteColor;
  final FontWeight fontWeight;
  final String text;
  final String? quoted;
  final int index;
  final String time;

  const _PreviewStandardMessage({
    required this.character,
    required this.isUser,
    required this.showAvatar,
    required this.showName,
    required this.metaColor,
    required this.italicColor,
    required this.quoteColor,
    required this.fontWeight,
    required this.text,
    required this.quoted,
    required this.index,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
        character.name.isNotEmpty ? character.name[0].toUpperCase() : '?';
    final avatarBg = isUser ? context.cs.primary : const Color(0xFFCCCCCC);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showAvatar)
                CircleAvatar(
                  radius: 12,
                  backgroundColor: avatarBg,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (showAvatar) const SizedBox(width: 8),
              if (showName)
                Text(
                  character.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: metaColor,
                  ),
                ),
              if (showName) const SizedBox(width: 6),
              Text(
                '#$index',
                style: TextStyle(
                  fontSize: 11,
                  color: metaColor.withValues(alpha: 0.55),
                ),
              ),
              const Spacer(),
              Text(
                time,
                style: TextStyle(
                  fontSize: 12,
                  color: metaColor.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
                color: italicColor,
                fontWeight: fontWeight,
              ),
              children: [
                TextSpan(text: text),
                if (quoted != null) ...[
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: quoted,
                    style: TextStyle(
                      color: quoteColor,
                      fontStyle: FontStyle.normal,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Bubble" chat layout — message in a colored bubble. Mirrors the bubble layout
/// in WebView renderer.
class _PreviewBubble extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final Color textColor;
  final Color? italicColor;
  final Color quoteColor;
  final double radius;
  final FontWeight fontWeight;
  final String text;
  final String? quoted;

  const _PreviewBubble({
    required this.alignment,
    required this.color,
    required this.textColor,
    required this.italicColor,
    required this.quoteColor,
    required this.radius,
    required this.fontWeight,
    required this.text,
    required this.quoted,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: context.cs.outline.withValues(alpha: 0.35),
          ),
        ),
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: italicColor ?? textColor,
              fontWeight: fontWeight,
            ),
            children: [
              TextSpan(text: text),
              if (quoted != null) ...[
                const TextSpan(text: ' '),
                TextSpan(
                  text: quoted,
                  style: TextStyle(
                    color: quoteColor,
                    fontStyle: FontStyle.normal,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
