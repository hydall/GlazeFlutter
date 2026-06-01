import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glaze_flutter/app.dart';

/// Call once in setUpAll to initialise EasyLocalization's static state
/// (device locale + saved locale from SharedPreferences).
Future<void> initLocalizationOnce() async {
  SharedPreferences.setMockInitialValues({'onboarding_complete': true});
  await EasyLocalization.ensureInitialized();
}

/// Pumps [GlazeApp] wrapped in [EasyLocalization], mirroring `main.dart`.
///
/// Why NO pumpAndSettle:
///   NoiseOverlay.picture.toImage() is async and triggers setState when done,
///   creating an infinite repaint cycle that pumpAndSettle never escapes.
///
/// The pump sequence uses [tester.runAsync] to let the real Dart event loop
/// process GoRouter's async redirect evaluation and EasyLocalization's
/// rootBundle Future. Without runAsync, GoRouter's StatefulShellRoute
/// never builds its first route in the test process.
Future<void> pumpGlazeApp(
  WidgetTester tester, {
  required ProviderContainer container,
  VoidCallback? restart,
  Map<String, Object> prefsSeed = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': true,
    ...prefsSeed,
  });

  await tester.runAsync(() async {
    await tester.pumpWidget(_buildApp(container, restart));
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 3; i++) {
      await tester.pump(Duration.zero);
    }
    await tester.pump(const Duration(milliseconds: 400));
  });
}

/// Pumps enough frames for GoRouter to complete a navigation after [go()].
/// Use after every [router.go()] call in tests.
Future<void> pumpNavigation(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 3; i++) {
      await tester.pump(Duration.zero);
    }
    await tester.pump(const Duration(milliseconds: 400));
  });
}

Widget _buildApp(ProviderContainer container, VoidCallback? restart) =>
    UncontrolledProviderScope(
      container: container,
      child: EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ru')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: GlazeApp(restart: restart),
      ),
    );
