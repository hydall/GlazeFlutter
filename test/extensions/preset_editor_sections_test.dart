import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';
import 'package:glaze_flutter/features/extensions/models/block_config.dart';
import 'package:glaze_flutter/features/extensions/models/extension_preset.dart';
import 'package:glaze_flutter/features/extensions/screens/preset_editor/block_edit_dialog.dart';
import 'package:glaze_flutter/features/extensions/screens/preset_editor/sections/blocks_section.dart';
import 'package:glaze_flutter/features/extensions/screens/preset_editor/sections/permissions_section.dart';
import 'package:glaze_flutter/features/extensions/screens/preset_editor/sections/profiles_section.dart';

void main() {
  Future<AppDatabase> pumpSection(WidgetTester tester, Widget child) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDbProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump();
    addTearDown(db.close);
    return db;
  }

  const preset = ExtensionPreset(
    id: 'preset-1',
    name: 'Test preset',
    blocks: [BlockConfig(id: 'block-1', name: 'Ledger')],
  );

  testWidgets('BlocksSection renders block list and add action', (
    tester,
  ) async {
    await pumpSection(tester, const BlocksSection(preset: preset));

    expect(find.text('Блоки'), findsOneWidget);
    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('Добавить блок'), findsOneWidget);
  });

  testWidgets('PermissionsSection renders capability switches', (tester) async {
    await pumpSection(tester, const PermissionsSection(preset: preset));

    expect(find.text('Разрешения (capabilities)'), findsOneWidget);
    expect(find.text('show_toast'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsWidgets);
  });

  testWidgets('ProfilesSection renders generateText profile rows', (
    tester,
  ) async {
    await pumpSection(tester, const ProfilesSection(preset: preset));

    expect(find.text('Профили подключения (generateText)'), findsOneWidget);
    expect(find.text('big'), findsOneWidget);
    expect(find.text('medium'), findsOneWidget);
    expect(find.text('small'), findsOneWidget);
  });

  testWidgets('BlockEditDialog renders the default infoblock editor', (
    tester,
  ) async {
    await pumpSection(
      tester,
      BlockEditDialog(block: preset.blocks.first, onSave: (_) {}),
    );

    expect(find.text('Настройки блока'), findsOneWidget);
    expect(find.text('Название'), findsOneWidget);
    expect(find.text('Инфоблок'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
  });
}
