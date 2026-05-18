import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:glaze_flutter/app.dart';
import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await tester.pumpWidget(ProviderScope(
      overrides: [appDbProvider.overrideWithValue(db)],
      child: const GlazeApp(),
    ));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MaterialApp), findsOneWidget);

    await db.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });
}
