import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:payment_tracker/screens/categories_screen.dart';
import 'package:payment_tracker/screens/budget_screen.dart';
import 'package:payment_tracker/services/database_schema.dart';
import 'package:payment_tracker/services/local_storage_service.dart';
import 'package:payment_tracker/services/sms_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.create,
      ),
    );
    LocalStorageService.useDatabaseForTesting(db);
  });
  tearDown(LocalStorageService.close);

  Future<void> finishDatabaseWork(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Widget app(Widget screen) => ChangeNotifierProvider(
    create: (_) => SmsService(),
    child: MaterialApp(home: screen),
  );

  testWidgets('empty categories support create, rename, and delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const CategoriesScreen()));
    await finishDatabaseWork(tester);
    expect(find.text('No categories yet'), findsOneWidget);
    await tester.tap(find.text('Add Category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'My arbitrary category');
    await tester.tap(find.text('Create'));
    await finishDatabaseWork(tester);
    expect(find.text('My arbitrary category'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed category');
    await tester.tap(find.text('Save'));
    await finishDatabaseWork(tester);
    expect(find.text('Renamed category'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await finishDatabaseWork(tester);
    expect(find.text('No categories yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adding first budget opens category setup when catalog is empty',
    (tester) async {
      await tester.pumpWidget(app(const BudgetScreen()));
      await finishDatabaseWork(tester);
      await tester.tap(find.text('Add Budget'));
      await finishDatabaseWork(tester);
      expect(find.text('No categories yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
