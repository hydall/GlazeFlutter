import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app.dart' show rootNavigatorKey;
import '../../shared/theme/app_colors.dart';
import '../../features/backup/backup_screen.dart';
import '../../features/settings/api_settings_screen.dart';
import '../../features/personas/persona_list_screen.dart';

const _onboardingCompleteKey = 'onboarding_complete';

Future<bool> isOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_onboardingCompleteKey) ?? false;
}

Future<void> markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingCompleteKey, true);
}

Future<void> resetOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingCompleteKey, false);
}

Future<void> checkAndShowOnboarding(BuildContext context) async {
  if (await isOnboardingComplete()) return;
  showOnboarding(context);
}

void showOnboarding(BuildContext context) {
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  nav.push(
    PageRouteBuilder(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (_, __, ___) => const _OnboardingFlow(),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

// ---------------------------------------------------------------------------
// Slide data
// ---------------------------------------------------------------------------

enum _SlideType { welcome, features, dataImport, api, persona, allSet }

class _SlideData {
  final _SlideType type;
  final String title;
  final String? desc;
  final IconData? icon;
  const _SlideData({required this.type, required this.title, this.desc, this.icon});
}

class _InfoBlock {
  final IconData icon;
  final String title;
  final String desc;
  const _InfoBlock({required this.icon, required this.title, required this.desc});
}

const _slides = <_SlideData>[
  _SlideData(type: _SlideType.welcome, title: 'Welcome\nto Glaze'),
  _SlideData(type: _SlideType.features, title: 'Glaze Features'),
  _SlideData(
    type: _SlideType.dataImport,
    title: 'Data Import',
    desc: 'If you have a backup from Tavo, SillyTavern or Glaze, you can restore it now.',
    icon: Icons.download_rounded,
  ),
  _SlideData(
    type: _SlideType.api,
    title: 'API Setup',
    desc: 'Connect your AI now. Set up your endpoint and model.',
    icon: Icons.dns_outlined,
  ),
  _SlideData(
    type: _SlideType.persona,
    title: 'Your Persona',
    desc: 'Set up your profile. Characters will know you by this.',
    icon: Icons.person_outline_rounded,
  ),
  _SlideData(
    type: _SlideType.allSet,
    title: 'All Set!',
    desc: 'You\'ve successfully configured Glaze. Press "Start" to dive into the world of roleplay!',
    icon: Icons.check_circle_outline_rounded,
  ),
];

const _introContent = <_InfoBlock>[
  _InfoBlock(
    icon: Icons.layers_outlined,
    title: 'Roleplay',
    desc: 'Your perfect companion for roleplay. Forget complex settings — just open the app and start your story.',
  ),
  _InfoBlock(
    icon: Icons.link_rounded,
    title: 'Your AI, your rules',
    desc: 'Connect to any OpenAI-compatible endpoint in a couple of clicks. Glaze never limits your API choice.',
  ),
  _InfoBlock(
    icon: Icons.verified_outlined,
    title: 'Full privacy',
    desc: 'Your secrets stay with you. All chats and characters are stored only on your device. No tracking.',
  ),
];

const _featuresContent = <_InfoBlock>[
  _InfoBlock(
    icon: Icons.image_outlined,
    title: 'Image Generation',
    desc: 'Naistera integration: create visual character images with reference support right in chat.',
  ),
  _InfoBlock(
    icon: Icons.menu_book_outlined,
    title: 'Glossary',
    desc: 'Your technical jargon reference. Available in the menu and quick-access chat for instant lookup.',
  ),
  _InfoBlock(
    icon: Icons.palette_outlined,
    title: 'Customization',
    desc: 'Customize the look: dark and light themes, custom backgrounds and fonts.',
  ),
  _InfoBlock(
    icon: Icons.description_outlined,
    title: 'SillyTavern Compatible',
    desc: 'Full support for SillyTavern V2 character cards. Import PNG and JSON with one tap.',
  ),
];

// ---------------------------------------------------------------------------
// Flow widget
// ---------------------------------------------------------------------------

class _OnboardingFlow extends ConsumerStatefulWidget {
  const _OnboardingFlow();

  @override
  ConsumerState<_OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<_OnboardingFlow> {
  int _currentSlide = 0;
  int _direction = 1;

  bool get _isLastSlide => _currentSlide == _slides.length - 1;

  String get _buttonLabel {
    if (_isLastSlide) return 'Start';
    switch (_slides[_currentSlide].type) {
      case _SlideType.dataImport:
      case _SlideType.api:
      case _SlideType.persona:
        return 'Skip';
      default:
        return 'Next';
    }
  }

  void _next() {
    if (_isLastSlide) {
      _finish();
    } else {
      setState(() { _direction = 1; _currentSlide++; });
    }
  }

  void _prev() {
    if (_currentSlide > 0) {
      setState(() { _direction = -1; _currentSlide--; });
    }
  }

  Future<void> _finish() async {
    await markOnboardingComplete();
    if (mounted) Navigator.of(context).pop();
  }

  void _openSheet(Widget sheet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) => sheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0E),
      body: Stack(
        children: [
          // ── Scrollable content ──
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                top: topPad + 84,
                bottom: 120 + bottomPad,
                left: 24,
                right: 24,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) {
                  final dir = (child.key == ValueKey(_currentSlide)) ? _direction : -_direction;
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: Offset(0.06 * dir, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_currentSlide),
                  child: _buildSlide(_slides[_currentSlide]),
                ),
              ),
            ),
          ),

          // ── Header gradient ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: topPad + 84,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x66000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // ── Stories progress bar ──
          Positioned(
            top: topPad + 16, left: 20, right: 20,
            child: _StoriesBar(
              total: _slides.length,
              current: _currentSlide,
            ),
          ),

          // ── Back button ──
          if (_currentSlide > 0)
            Positioned(
              top: topPad + 36, left: 12,
              child: _GlassBackButton(onTap: _prev),
            ),

          // ── Footer gradient ──
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 120 + bottomPad,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0x80000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // ── Footer button ──
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: _PrimaryButton(
                  label: _buttonLabel,
                  onTap: _next,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Slide builders ──

  Widget _buildSlide(_SlideData slide) {
    switch (slide.type) {
      case _SlideType.welcome:
        return _buildBlocksSlide(slide.title, _introContent);
      case _SlideType.features:
        return _buildBlocksSlide(slide.title, _featuresContent);
      case _SlideType.dataImport:
        return _buildActionSlide(
          slide: slide,
          actionIcon: Icons.download_rounded,
          actionTitle: 'Restore from Backup',
          actionSub: 'Backups',
          onAction: () => _openSheet(const BackupScreen()),
          context: context,
        );
      case _SlideType.api:
        return _buildActionSlide(
          slide: slide,
          actionIcon: Icons.settings_outlined,
          actionTitle: 'Configure API',
          actionSub: 'Endpoint, model, key',
          onAction: () => _openSheet(const ApiSettingsScreen()),
          context: context,
        );
      case _SlideType.persona:
        return _buildActionSlide(
          slide: slide,
          actionIcon: Icons.person_add_outlined,
          actionTitle: 'Set Up Persona',
          actionSub: 'Name, avatar, description',
          onAction: () => _openSheet(const PersonaListScreen()),
          context: context,
        );
      case _SlideType.allSet:
        return _buildStandardSlide(slide, context);
    }
  }

  /// Welcome / Features — title + list of info blocks
  Widget _buildBlocksSlide(String title, List<_InfoBlock> blocks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 32, fontWeight: FontWeight.w800,
            color: Colors.white, height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        ...blocks.map((b) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _IntroBlockCard(block: b),
        )),
      ],
    );
  }

  /// Standard centered slide — icon + title + description
  Widget _buildStandardSlide(_SlideData slide, BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          const SizedBox(height: 40),
          _IconBubble(icon: slide.icon ?? Icons.check),
          const SizedBox(height: 24),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800,
              color: Colors.white, height: 1.3,
            ),
          ),
          if (slide.desc != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                slide.desc!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16, color: context.cs.onSurfaceVariant, height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Standard slide + clickable action card
  Widget _buildActionSlide({
    required _SlideData slide,
    required IconData actionIcon,
    required String actionTitle,
    required String actionSub,
    required VoidCallback onAction,
    required BuildContext context,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          const SizedBox(height: 40),
          _IconBubble(icon: slide.icon ?? Icons.settings),
          const SizedBox(height: 24),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800,
              color: Colors.white, height: 1.3,
            ),
          ),
          if (slide.desc != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                slide.desc!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16, color: context.cs.onSurfaceVariant, height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _ClickableBlock(
            icon: actionIcon,
            title: actionTitle,
            subtitle: actionSub,
            onTap: onAction,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable sub-widgets
// ---------------------------------------------------------------------------

/// Stories-style progress bar (Instagram / Telegram-like)
class _StoriesBar extends StatelessWidget {
  final int total;
  final int current;
  const _StoriesBar({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final filled = i <= current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3, right: i == total - 1 ? 0 : 3),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: const Color(0x33808080),
              ),
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                alignment: Alignment.centerLeft,
                widthFactor: filled ? 1.0 : 0.0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                     color: context.cs.primary,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Glass-morphism circular back button
class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: context.cs.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: const [
                BoxShadow(color: Color(0x4D000000), blurRadius: 15, offset: Offset(0, 4)),
              ],
            ),
            child: Icon(Icons.arrow_back, size: 20, color: context.cs.primary),
          ),
        ),
      ),
    );
  }
}

/// Accent-tinted circular icon bubble (100×100)
class _IconBubble extends StatelessWidget {
  final IconData icon;
  const _IconBubble({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100, height: 100,
      decoration: BoxDecoration(
        color: context.cs.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 48, color: context.cs.primary),
    );
  }
}

/// Info block card (column layout) — for welcome/features slides
class _IntroBlockCard extends StatelessWidget {
  final _InfoBlock block;
  const _IntroBlockCard({required this.block});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x14808080),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(block.icon, size: 48, color: context.cs.primary),
          const SizedBox(height: 8),
          Text(
            block.title,
            style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            block.desc,
            style: TextStyle(
              fontSize: 15, color: context.cs.onSurfaceVariant, height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clickable action card — for data import / api / persona slides
class _ClickableBlock extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ClickableBlock({
    required this.icon, required this.title,
    required this.subtitle, required this.onTap,
  });

  @override
  State<_ClickableBlock> createState() => _ClickableBlockState();
}

class _ClickableBlockState extends State<_ClickableBlock> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _pressed ? const Color(0x26808080) : const Color(0x14808080),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, size: 48, color: context.cs.primary),
              const SizedBox(height: 8),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: TextStyle(
                  fontSize: 15, color: context.cs.onSurfaceVariant, height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width accent primary button
class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: context.cs.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
