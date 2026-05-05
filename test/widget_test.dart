import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glaze_flutter/app.dart';

void main() {
  testWidgets('App renders character list', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: GlazeApp()));
    await tester.pumpAndSettle();
    expect(find.text('Glaze'), findsOneWidget);
  });
}
