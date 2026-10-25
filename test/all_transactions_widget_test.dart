import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:payment_tracker/models/app_category.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/services/transfer_service.dart';
import 'package:payment_tracker/utils/format_utils.dart';
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

  void totals(WidgetTester tester, double credit, double debit) {
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('filtered-credit'))).data,
      'Total credit: ${FormatUtils.formatCurrency(credit)}',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('filtered-debit'))).data,
      'Total debit: ${FormatUtils.formatCurrency(debit)}',
    );
  }

  Future<void> select(WidgetTester tester) async {
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
  }

  Future<void> assign(WidgetTester tester, String category) async {
    await tester.tap(find.byKey(const ValueKey('assign-category')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey('assign-category-$category')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'totals follow banks, categories, tags, search, tabs and empty results',
    (tester) async {
      await open(tester);
      totals(tester, 20, 80);
      await chip(tester, 'banks-BANK_A');
      totals(tester, 0, 50);
      await chip(tester, 'categories-a');
      totals(tester, 0, 40);
      await chip(tester, 'banks-all');
      totals(tester, 0, 70);
      await chip(tester, 'categories-all');
      await chip(tester, 'tags-home');
      totals(tester, 20, 10);
      await tester.tap(find.widgetWithText(Tab, 'Money In'));
      await tester.pumpAndSettle();
      totals(tester, 20, 0);
      await tester.enterText(find.byType(TextField), 'no such merchant');
      await tester.pumpAndSettle();
      totals(tester, 0, 0);
      expect(find.text('No matching transactions'), findsOneWidget);
    },
  );

  testWidgets(
    'select all applies only to filtered rows and refreshes category filters',
    (tester) async {
      await open(tester);
      await chip(tester, 'categories-a');
      await select(tester);
      await chip(tester, 'select-all-filtered');
      expect(find.text('2 selected'), findsOneWidget);
      totals(tester, 0, 70);
      await assign(tester, 'b');
      expect(find.text('No matching transactions'), findsOneWidget);
      totals(tester, 0, 0);
      expect(sms.transactions.every((tx) => tx.categoryId == 'b'), isTrue);
      expect(
        sms.transactions
            .where((tx) => tx.categorySource == 'user')
            .map((tx) => tx.id)
            .toSet(),
        {'0', '2'},
      );
      expect(sms.transactions.firstWhere((tx) => tx.id == '0').tag, 'work');
      await chip(tester, 'categories-all');
      totals(tester, 20, 80);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual selection drops hidden rows and cancellation preserves data',
    (tester) async {
      await open(tester);
      await select(tester);
      await chip(tester, 'select-transaction-0');
      await chip(tester, 'select-transaction-2');
      expect(find.text('2 selected'), findsOneWidget);
      await chip(tester, 'banks-BANK_A');
      expect(find.text('1 selected'), findsOneWidget);
      await chip(tester, 'banks-all');
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assign-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        sms.transactions.where((tx) => tx.categoryId == 'a'),
        hasLength(2),
      );
      await assign(tester, 'b');
      expect(sms.transactions.firstWhere((tx) => tx.id == '0').categoryId, 'b');
      expect(sms.transactions.firstWhere((tx) => tx.id == '2').categoryId, 'a');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transfer legs and paise are counted once and can be categorized separately',
    (tester) async {
      await tester.runAsync(() async {
        final debit = sms.transactions
            .firstWhere((tx) => tx.id == '0')
            .copyWith(amount: 0.1);
        final credit = sms.transactions
            .firstWhere((tx) => tx.id == '3')
            .copyWith(amount: 0.1);
        await LocalStorageService.saveTransactions([
          debit,
          credit,
          sms.transactions
              .firstWhere((tx) => tx.id == '1')
              .copyWith(amount: 0.2),
          debit.copyWith(id: 'ignored', amount: 999, isIgnored: true),
        ]);
        await TransferService.mergeAsTransfer(debit, credit);
        await sms.reloadFromCache();
      });
      await open(tester);
      totals(tester, 0.1, 30.3);
      await select(tester);
      expect(find.byType(Checkbox), findsNWidgets(4));
      await chip(tester, 'select-transaction-0');
      await assign(tester, 'b');
      final debit = sms.transactions.firstWhere((tx) => tx.id == '0');
      final credit = sms.transactions.firstWhere((tx) => tx.id == '3');
      expect(debit.categoryId, 'b');
      expect(credit.categorySource, isNull);
      expect(debit.transferPartnerId, credit.id);
      expect(
        TransferService.getMergedTransfers(sms.transactions),
        hasLength(1),
      );
      totals(tester, 0.1, 30.3);
    },
  );

  testWidgets(
    'selection and totals fit a phone and category setup is available when empty',
    (tester) async {
      await tester.runAsync(() async {
        await LocalStorageService.deleteCategory('a');
        await LocalStorageService.deleteCategory('b');
        await sms.reloadFromCache();
      });
      await open(tester);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await select(tester);
      await chip(tester, 'select-all-filtered');
      await tester.tap(find.byKey(const ValueKey('assign-category')));
      await tester.pumpAndSettle();
      expect(find.text('No categories yet. Create one below.'), findsOneWidget);
      expect(find.text('Create or manage categories'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Exit selection'));
      await tester.pumpAndSettle();
      totals(tester, 20, 80);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('salary periods use the same boundaries for totals and rows', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final base = sms.transactions.firstWhere((tx) => tx.id == '0');
      await LocalStorageService.saveTransactions([
        base.copyWith(
          id: 'prior-salary',
          type: TransactionType.credit,
          amount: 0.3,
          isSalary: true,
        ),
        sms.transactions
            .firstWhere((tx) => tx.id == '3')
            .copyWith(isSalary: true),
      ]);
      await sms.reloadFromCache();
    });
    await open(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    totals(tester, 20, 0);
    final cycles = await tester.runAsync(
      LocalStorageService.getAllSalaryCycles,
    );
    final prior = cycles!.firstWhere((cycle) => !cycle.isCurrent);
    await chip(tester, 'period-${prior.id}');
    totals(tester, 0.3, 80);
    await tester.tap(find.text('All Time'));
    await tester.pumpAndSettle();
    totals(tester, 20.3, 80);
  });

  testWidgets(
    'select all includes matching transactions beyond the visible viewport',
    (tester) async {
      await tester.runAsync(() async {
        final base = sms.transactions.first;
        await LocalStorageService.saveTransactions([
          for (var i = 0; i < 60; i++) base.copyWith(id: 'extra-$i'),
        ]);
        await sms.reloadFromCache();
      });
      await open(tester);
      await select(tester);
      await chip(tester, 'select-all-filtered');
      expect(find.text('64 selected'), findsOneWidget);
      await assign(tester, 'a');
      expect(
        sms.transactions.where((tx) => tx.categoryId == 'a'),
        hasLength(64),
      );
    },
  );

  testWidgets(
    'long press selects that transaction, taps add selections, and swipe edits are disabled',
    (tester) async {
      await open(tester);
      await tester.longPress(find.byKey(const ValueKey('transaction-0')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('select-transaction-0')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('transaction-2')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byType(Dismissible), findsNothing);
      await assign(tester, 'b');
      expect(
        sms.transactions
            .where((tx) => tx.categorySource == 'user')
            .map((tx) => tx.id)
            .toSet(),
        {'0', '2'},
      );
      expect(find.byType(Dismissible), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'net and internal transfers follow filters without double counting merged pairs',
    (tester) async {
      await tester.runAsync(() async {
        final debit = sms.transactions
            .firstWhere((tx) => tx.id == '0')
            .copyWith(amount: 20);
        final credit = sms.transactions.firstWhere((tx) => tx.id == '3');
        await LocalStorageService.saveTransaction(debit);
        await TransferService.mergeAsTransfer(debit, credit);
        await sms.reloadFromCache();
      });
      await open(tester);
      void summary(double net, double internal) {
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('filtered-net'))).data,
          'Total amount (net): ${FormatUtils.formatCurrency(net)}',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('filtered-transfers')))
              .data,
          'Internal transfers: ${FormatUtils.formatCurrency(internal)}',
        );
      }

      totals(tester, 20, 60);
      summary(-40, 20);
      final pair = TransferService.getMergedTransfers(sms.transactions).single;
      await tester.longPress(
        find.byKey(ValueKey('transfer-${pair.transferGroupId}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await chip(tester, 'select-transaction-3');
      expect(find.text('1 selected'), findsOneWidget);
      await assign(tester, 'b');
      expect(
        sms.transactions.firstWhere((tx) => tx.id == '0').categorySource,
        'user',
      );
      expect(
        sms.transactions.firstWhere((tx) => tx.id == '3').categorySource,
        isNull,
      );
      summary(-40, 20);
      await chip(tester, 'banks-BANK_A');
      totals(tester, 0, 30);
      summary(-30, 20);
      await chip(tester, 'banks-all');
      await tester.tap(find.widgetWithText(Tab, 'Money In'));
      await tester.pumpAndSettle();
      summary(20, 20);
      await tester.enterText(find.byType(TextField), 'no matching transaction');
      await tester.pumpAndSettle();
      summary(0, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long press preserves scroll position and selected card visibility',
    (tester) async {
      await tester.runAsync(() async {
        final base = sms.transactions.first;
        await LocalStorageService.saveTransactions([
          for (var i = 0; i < 60; i++) base.copyWith(id: 'scroll-$i'),
        ]);
        await sms.reloadFromCache();
      });
      await open(tester);
      final list = find.byKey(const PageStorageKey('transactions-0'));
      await tester.drag(list, const Offset(0, -900));
      await tester.pumpAndSettle();
      final target = find.byType(TransactionCard).hitTestable().first;
      final card = tester.widget<TransactionCard>(target);
      final before = tester.getTopLeft(target).dy;
      await tester.longPress(target);
      await tester.pumpAndSettle();
      final selected = find.byKey(ValueKey('transaction-${card.tx.id}'));
      expect(selected.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(selected).dy, closeTo(before, 1));
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Exit selection'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
