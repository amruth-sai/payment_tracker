import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:payment_tracker/models/app_category.dart';
import 'package:payment_tracker/models/salary_cycle.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/screens/spending_heatmap_screen.dart';
import 'package:payment_tracker/services/database_schema.dart';
import 'package:payment_tracker/services/local_storage_service.dart';
import 'package:payment_tracker/utils/format_utils.dart';

void main() {
  late DateTime month;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: DatabaseSchema.create),
    );
    LocalStorageService.useDatabaseForTesting(db);
    for (final id in ['fuel', 'shopping']) {
      await LocalStorageService.saveCategory(
        AppCategory(
          id: id,
          name: id == 'fuel' ? 'Fuel' : 'Shopping',
          emoji: 'C',
          colorValue: 0xff123456,
          createdAt: month,
        ),
      );
    }
    Transaction payment(
      String id,
      double amount,
      int day, {
      String bank = 'BANK_A',
      String? category = 'fuel',
      String? tag = 'bike',
      bool credit = false,
      bool ignored = false,
      bool salary = false,
      String? transfer,
      String? note,
      String? reference,
      DateTime? date,
    }) => Transaction(
      id: id,
      amount: amount,
      type: credit ? TransactionType.credit : TransactionType.debit,
      source: PaymentSource.bank,
      sender: bank,
      merchant: id,
      categoryId: category,
      tag: tag,
      date: date ?? DateTime(month.year, month.month, day),
      rawMessage: 'Payment $id',
      isIgnored: ignored,
      isSalary: salary,
      transferGroupId: transfer,
      note: note,
      referenceId: reference,
    );
    await LocalStorageService.saveTransactions([
      payment('Fuel stop', 100.25, 2, note: 'weekday ride', reference: 'REF-A'),
      payment(
        'Groceries',
        49.75,
        2,
        bank: 'BANK_B',
        category: 'shopping',
        tag: 'home',
      ),
      payment('Fuel refill', 80, 3),
      payment('Fuel refund', 25, 2, credit: true),
      payment(
        'Salary',
        1000,
        1,
        bank: 'BANK_B',
        category: null,
        tag: 'income',
        credit: true,
        salary: true,
      ),
      payment('No category', 30, 4, bank: 'BANK_B', category: null, tag: null),
      payment('Bike shopping', 40, 5, category: 'shopping'),
      payment('Transfer out', 200, 6, transfer: 'pair'),
      payment('Transfer in', 200, 6, credit: true, transfer: 'pair'),
      payment('Ignored', 999, 2, ignored: true),
      payment(
        'Previous month',
        100,
        1,
        date: DateTime(month.year, month.month, 0, 23, 59),
      ),
    ]);
    await LocalStorageService.saveSalaryCycle(
      SalaryCycle(
        id: 'closed-cycle',
        startDate: month,
        endDate: DateTime(month.year, month.month, 3),
        salaryAmount: 1000,
        salaryTransactionId: 'Salary',
      ),
    );
  });
  tearDown(LocalStorageService.close);

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool small = false}) async {
    tester.view.physicalSize = small
        ? const Size(320, 740)
        : const Size(1080, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: small ? Brightness.dark : Brightness.light,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(small ? 1.6 : 1)),
          child: child!,
        ),
        home: const SpendingHeatmapScreen(),
      ),
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  void total(WidgetTester tester, double value) => expect(
    tester.widget<Text>(find.byKey(const ValueKey('heatmap-total'))).data,
    FormatUtils.formatCurrency(value),
  );

  Future<void> closeDay(WidgetTester tester) async {
    Navigator.of(
      tester.element(find.byKey(const ValueKey('heatmap-day-total'))),
    ).pop();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'default spending, daily details and statistics share the same read-only results',
    (tester) async {
      final before = await tester.runAsync(LocalStorageService.createBackup);
      await open(tester);
      total(tester, 300);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('heatmap-average'))).data,
        FormatUtils.formatCurrency(75),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('heatmap-peak'))).data,
        FormatUtils.formatCurrency(150),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('heatmap-active'))).data,
        '4',
      );
      await tap(tester, 'heatmap-day-2');
      expect(
        find.byKey(const ValueKey('heatmap-transaction-Fuel stop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('heatmap-transaction-Groceries')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('heatmap-transaction-Fuel refund')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('heatmap-transaction-Ignored')),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('heatmap-day-total')))
            .data,
        contains(FormatUtils.formatCurrency(150)),
      );
      await closeDay(tester);
      await tap(tester, 'heatmap-day-6');
      expect(find.text('No matching transactions this day'), findsOneWidget);
      await closeDay(tester);
      expect(
        (await tester.runAsync(LocalStorageService.createBackup))!.tables,
        before!.tables,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bank, category and tag selections combine and preserve recoverable empty filters',
    (tester) async {
      await open(tester);
      await tap(tester, 'heatmap-banks-BANK_A');
      total(tester, 220.25);
      await tap(tester, 'heatmap-banks-BANK_B');
      total(tester, 300);
      await tap(tester, 'heatmap-categories-fuel');
      total(tester, 180.25);
      await tap(tester, 'heatmap-categories-shopping');
      total(tester, 270);
      await tap(tester, 'heatmap-tags-bike');
      total(tester, 220.25);
      await tap(tester, 'heatmap-tags-home');
      total(tester, 270);
      await tap(tester, 'heatmap-reset');
      await tap(tester, 'heatmap-categories-');
      total(tester, 30);
      await tester.enterText(find.byType(SearchBar), 'no such payment');
      await tester.pumpAndSettle();
      total(tester, 0);
      expect(
        find.text('No transactions match this month and these filters.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('heatmap-categories-')),
            )
            .selected,
        isTrue,
      );
      await tap(tester, 'heatmap-reset');
      total(tester, 300);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search uses Activity rules and recomputes calendar intensity and day contents',
    (tester) async {
      await open(tester);
      final day3 = find
          .ancestor(
            of: find.byKey(const ValueKey('heatmap-day-3')),
            matching: find.byType(Material),
          )
          .first;
      final before = tester.widget<Material>(day3).color;
      await tap(tester, 'heatmap-banks-BANK_A');
      await tap(tester, 'heatmap-categories-fuel');
      total(tester, 180.25);
      expect(tester.widget<Material>(day3).color, isNot(before));
      await tester.enterText(find.byType(SearchBar), '  WEEKDAY RIDE  ');
      await tester.pumpAndSettle();
      total(tester, 100.25);
      await tap(tester, 'heatmap-day-2');
      expect(
        find.byKey(const ValueKey('heatmap-transaction-Fuel stop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('heatmap-transaction-Groceries')),
        findsNothing,
      );
      await closeDay(tester);
      await tester.enterText(find.byType(SearchBar), 'ref-a');
      await tester.pumpAndSettle();
      total(tester, 100.25);
      await tap(tester, 'heatmap-reset');
      await tester.enterText(find.byType(SearchBar), '49.75');
      await tester.pumpAndSettle();
      total(tester, 49.75);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'directions and optional internal transfers update totals and signed day rows',
    (tester) async {
      await open(tester);
      await tap(tester, 'heatmap-direction-1');
      total(tester, 1025);
      await tap(tester, 'heatmap-day-2');
      expect(find.text('+${FormatUtils.formatCurrency(25)}'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('heatmap-transaction-Fuel stop')),
        findsNothing,
      );
      await closeDay(tester);
      await tap(tester, 'heatmap-direction-0');
      total(tester, 1325);
      await tap(tester, 'heatmap-transfers');
      total(tester, 1725);
      await tap(tester, 'heatmap-day-6');
      expect(
        find.byKey(const ValueKey('heatmap-transaction-Transfer out')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('heatmap-transaction-Transfer in')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('heatmap-day-total')))
            .data,
        contains(FormatUtils.formatCurrency(400)),
      );
      await closeDay(tester);
      await tap(tester, 'heatmap-direction-2');
      total(tester, 500);
      await tap(tester, 'heatmap-reset');
      total(tester, 300);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'salary cycle uses exclusive end boundary and intersects month while keeping filters',
    (tester) async {
      await open(tester);
      await tap(tester, 'heatmap-banks-BANK_A');
      await tap(tester, 'heatmap-period-closed-cycle');
      total(tester, 100.25);
      await tap(tester, 'heatmap-day-3');
      expect(find.text('No matching transactions this day'), findsOneWidget);
      await closeDay(tester);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      total(tester, 0);
      await tap(tester, 'heatmap-period-all');
      total(tester, 100);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      total(tester, 220.25);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('heatmap-banks-BANK_A')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tracking start and refresh retain the active filters and load new transactions',
    (tester) async {
      await tester.runAsync(
        () => LocalStorageService.setTrackFromDate(
          DateTime(month.year, month.month, 3),
        ),
      );
      await open(tester);
      total(tester, 150);
      await tap(tester, 'heatmap-banks-BANK_A');
      total(tester, 120);
      await tester.runAsync(() async {
        await LocalStorageService.saveTransaction(
          Transaction(
            id: 'New fuel',
            amount: 5,
            type: TransactionType.debit,
            source: PaymentSource.bank,
            sender: 'BANK_A',
            categoryId: 'fuel',
            tag: 'bike',
            date: DateTime(month.year, month.month, 5),
            rawMessage: 'New fuel payment',
          ),
        );
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
      });
      await tester.pumpAndSettle();
      total(tester, 125);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('heatmap-banks-BANK_A')),
            )
            .selected,
        isTrue,
      );
      await tap(tester, 'heatmap-day-2');
      expect(find.text('No matching transactions this day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small dark layouts and keyboard remain scrollable with larger text',
    (tester) async {
      await open(tester, small: true);
      await tap(tester, 'heatmap-day-2');
      expect(find.byKey(const ValueKey('heatmap-day-total')), findsOneWidget);
      await closeDay(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final search = find.byType(SearchBar);
      await tester.ensureVisible(search);
      await tester.enterText(search, 'missing');
      await tester.pumpAndSettle();
      total(tester, 0);
      await tap(tester, 'heatmap-reset');
      total(tester, 300);
      expect(tester.takeException(), isNull);
    },
  );
}
