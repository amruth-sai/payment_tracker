import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:payment_tracker/models/app_category.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/screens/all_transactions_screen.dart';
import 'package:payment_tracker/services/database_schema.dart';
import 'package:payment_tracker/services/local_storage_service.dart';
import 'package:payment_tracker/services/sms_service.dart';
import 'package:payment_tracker/widgets/transaction_card.dart';

void main() {
  late SmsService sms;
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
    for (final id in ['a', 'b']) {
      await LocalStorageService.saveCategory(
        AppCategory(
          id: id,
          name: 'Category $id',
          emoji: 'A',
          colorValue: 0xff123456,
          createdAt: DateTime(2026),
        ),
      );
    }
    await LocalStorageService.saveTransactions([
      for (var i = 0; i < 4; i++)
        Transaction(
          id: '$i',
          amount: [40, 10, 30, 20][i].toDouble(),
          type: i == 3 ? TransactionType.credit : TransactionType.debit,
          source: PaymentSource.bank,
          sender: i < 2 ? 'BANK_A' : 'BANK_B',
          merchant: 'Merchant $i',
          categoryId: i.isEven ? 'a' : 'b',
          tag: i.isEven ? 'work' : 'home',
          date: DateTime(2026, 10, 15, 12, i),
          rawMessage: 'Transaction $i',
        ),
    ]);
    sms = SmsService();
    await sms.reloadFromCache();
  });
  tearDown(() async {
    sms.dispose();
    await LocalStorageService.close();
  });

  Future<void> open(WidgetTester tester, {int filter = 0}) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: sms,
        child: MaterialApp(home: AllTransactionsScreen(filter: filter)),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> visibleIds(WidgetTester tester) => tester
      .widgetList<TransactionCard>(find.byType(TransactionCard))
      .map((card) => card.tx.id)
      .toList();

  Future<void> chip(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'multi-select chips combine within rows and intersect across rows',
    (tester) async {
      await open(tester);
      await chip(tester, 'banks-BANK_A');
      expect(visibleIds(tester), ['1', '0']);
      await chip(tester, 'banks-BANK_B');
      expect(visibleIds(tester), ['3', '2', '1', '0']);
      await chip(tester, 'categories-a');
      expect(visibleIds(tester), ['2', '0']);
      await chip(tester, 'categories-b');
      expect(visibleIds(tester), ['3', '2', '1', '0']);
      await chip(tester, 'tags-work');
      expect(visibleIds(tester), ['2', '0']);
      await chip(tester, 'banks-BANK_B');
      expect(visibleIds(tester), ['0']);
      await chip(tester, 'banks-all');
      expect(visibleIds(tester), ['2', '0']);
      await chip(tester, 'tags-all');
      await chip(tester, 'categories-all');
      expect(visibleIds(tester), ['3', '2', '1', '0']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tabs and search retain selected filters, including empty results',
    (tester) async {
      await open(tester, filter: 2);
      expect(visibleIds(tester), ['2', '1', '0']);
      await chip(tester, 'categories-a');
      await tester.tap(find.widgetWithText(Tab, 'Money In'));
      await tester.pumpAndSettle();
      expect(find.text('No matching transactions'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('categories-a')))
            .selected,
        isTrue,
      );
      await chip(tester, 'categories-all');
      expect(visibleIds(tester), ['3']);
      await tester.tap(find.widgetWithText(Tab, 'All'));
      await tester.pumpAndSettle();
      await chip(tester, 'banks-BANK_A');
      await tester.enterText(find.byType(TextField), 'Merchant 2');
      await tester.pumpAndSettle();
      expect(find.text('No matching transactions'), findsOneWidget);
      await chip(tester, 'banks-all');
      expect(visibleIds(tester), ['2']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('amount sorting changes displayed order without mutating cache', (
    tester,
  ) async {
    await open(tester);
    final original = sms.transactions.map((tx) => tx.id).toList();
    for (final entry in {
      'Amount: Low to High': ['1', '3', '2', '0'],
      'Amount: High to Low': ['0', '2', '3', '1'],
      'Default (by date)': ['3', '2', '1', '0'],
    }.entries) {
      await tester.tap(find.byTooltip('Sort by amount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(visibleIds(tester), entry.value);
      expect(sms.transactions.map((tx) => tx.id).toList(), original);
    }
    expect(tester.takeException(), isNull);
  });
}
