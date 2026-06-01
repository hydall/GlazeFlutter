import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glaze_flutter/app.dart';
import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';

import 'helpers/pump_glaze_app.dart';

void main() {
  setUpAll(initLocalizationOnce);

  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // widget_test is intentionally simple — it only verifies that the
    // MaterialApp builds and the EasyLocalization tree mounts. We skip
    // the navigation-aware pumpGlazeApp because it relies on
    // tester.runAsync() which deadlocks when InAppWebView's platform
    // channel has no mock handler. See test/navigation_smoke_test.dart
    // for the full-app navigation test path.
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await EasyLocalization.ensureInitialized();

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ru')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          child: const GlazeApp(),
        ),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);

    container.dispose();
    await db.close();
  });
}
