import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/theme/app_colors.dart';

const _onboardingCompleteKey = 'onboarding_complete';

Future<bool> isOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_onboardingCompleteKey) ?? false;
}

Future<void> markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingCompleteKey, true);
}

Future<void> checkAndShowOnboarding(BuildContext context) async {
  if (await isOnboardingComplete()) return;
  if (!context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const _OnboardingFlow(), fullscreenDialog: true),
  );
}

class _OnboardingFlow extends ConsumerStatefulWidget {
  const _OnboardingFlow();

  @override
  ConsumerState<_OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<_OnboardingFlow> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _steps = [
    _OnboardingStep(
      icon: Icons.waving_hand,
      title: 'Welcome to Glaze',
      description: 'Your AI character chat companion. Let\'s get you set up in a few quick steps.',
    ),
    _OnboardingStep(
      icon: Icons.api,
      title: 'Connect Your API',
      description: 'Add an OpenAI-compatible API endpoint to start chatting. You can always change this later in Settings.',
      route: '/tools/api',
    ),
    _OnboardingStep(
      icon: Icons.person_add,
      title: 'Import a Character',
      description: 'Bring in a character card (PNG or JSON) to start your first conversation.',
      route: '/characters',
    ),
    _OnboardingStep(
      icon: Icons.chat,
      title: 'Start Chatting',
      description: 'You\'re all set! Tap any character to begin.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () => _finish(),
                child: const Text('Skip', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) => _buildStep(_steps[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == i ? AppColors.accent : AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    _currentPage == _steps.length - 1 ? 'Get Started' : 'Next',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(_OnboardingStep step) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(step.icon, color: AppColors.accent, size: 36),
          ),
          const SizedBox(height: 24),
          Text(
            step.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            step.description,
            style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _nextStep() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await markOnboardingComplete();
    if (mounted) Navigator.of(context).pop();
  }
}

class _OnboardingStep {
  final IconData icon;
  final String title;
  final String description;
  final String? route;
  const _OnboardingStep({required this.icon, required this.title, required this.description, this.route});
}
