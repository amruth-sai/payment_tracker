import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:payment_tracker/models/app_category.dart';
import 'package:payment_tracker/models/budget.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/screens/budget_screen.dart';
import 'package:payment_tracker/services/budget_service.dart';
import 'package:payment_tracker/services/database_schema.dart';
import 'package:payment_tracker/services/local_storage_service.dart';
import 'package:payment_tracker/services/sms_service.dart';
import 'package:payment_tracker/widgets/transaction_card.dart';

final periodStart = DateTime(2026, 10, 1);
final periodEnd = DateTime(2026, 10, 31, 23, 59, 59, 999);
Transaction payment(
  String id,
  double amount, {
  bool credit = false,
  String category = 'c',
  DateTime? date,
}) => Transaction(
  id: id,
  amount: amount,
  type: credit ? TransactionType.credit : TransactionType.debit,
  source: PaymentSource.bank,
  sender: 'BANK',
  merchant: id,
  categoryId: category,
  date: date ?? DateTime(2026, 10, 5),
  rawMessage: 'payment $id',
);

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
    for (final id in ['c', 'outside']) {
      await LocalStorageService.saveCategory(
        AppCategory(
          id: id,
          name: id == 'c' ? 'Shopping' : 'Other',
          emoji: 'S',
          colorValue: 0xff123456,
          createdAt: DateTime(2026),
        ),
      );
    }
    await LocalStorageService.saveBudget(
      Budget(id: 'budget', categoryId: 'c', monthlyLimit: 1000),
    );
  });
  tearDown(LocalStorageService.close);

  Future<BudgetStatus> status(List<Transaction> rows) async =>
      (await BudgetService.checkBudgets(
        transactions: rows,
        start: periodStart,
        end: periodEnd,
      )).single;

  test(
    'credits reduce the same category and period; ignored and transfers remain excluded',
    () async {
      final rows = [
        payment('purchase', 1000),
        payment('refund', 250, credit: true),
        payment('ignored debit', 900).copyWith(isIgnored: true),
        payment('ignored credit', 900, credit: true).copyWith(isIgnored: true),
        payment('transfer debit', 400).copyWith(transferGroupId: 'pair'),
        payment(
          'transfer credit',
          400,
          credit: true,
        ).copyWith(transferGroupId: 'pair'),
        payment('other refund', 500, credit: true, category: 'outside'),
        payment(
          'previous refund',
          500,
          credit: true,
          date: DateTime(2026, 9, 30),
        ),
        payment('next refund', 500, credit: true, date: DateTime(2026, 11, 1)),
      ];
      final result = await status(rows);
      expect(result.debits, 1000);
      expect(result.credits, 250);
      expect(result.spent, 750);
      expect(result.percentage, 75);
      expect(result.remaining, 250);
      expect(result.isHealthy, isTrue);
      final outside = BudgetService.outsideBudgetTransactions(
        transactions: rows,
        budgetCategoryIds: {'c'},
        start: periodStart,
        end: periodEnd,
      );
      expect(outside.map((tx) => tx.id), ['other refund']);
      expect(BudgetService.netSpending(outside), -500);
    },
  );

  test(
    'credit-only and excess credits retain negative net and increase remaining budget',
    () async {
      final result = await status([
        payment('refund', 1250, credit: true),
        payment('purchase', 1000),
      ]);
      expect(result.spent, -250);
      expect(result.remaining, 1250);
      expect(result.percentage, 0);
      expect(result.isOverBudget, isFalse);
      expect(
        (await status([payment('refund only', 300, credit: true)])).spent,
        -300,
      );
    },
  );

  test('net sums and remaining amounts retain paise exactly', () async {
    final result = await status([
      payment('one', 0.1),
      payment('two', 0.2),
      payment('refund', 0.1, credit: true),
    ]);
    expect(result.debits, 0.3);
    expect(result.credits, 0.1);
    expect(result.spent, 0.2);
    expect(result.remaining, 999.8);
  });

  test('warnings and overspending use net spending after credits', () async {
    for (final credit in [100.0, 300.0, 500.0, 1300.0]) {
      final rows = [
        payment('purchase', 1200),
        payment('refund', credit, credit: true),
      ];
      final result = await status(rows);
      final alerts = await BudgetService.getOverBudgetAlerts(
        transactions: rows,
        start: periodStart,
        end: periodEnd,
      );
      expect(result.isOverBudget, credit == 100);
      expect(result.isWarning, credit == 300);
      expect(alerts.length, credit <= 300 ? 1 : 0);
    }
  });

  test(
    'suggestions use net monthly averages including credit-only months',
    () async {
      final suggestions = await BudgetService.suggestBudgets(
        transactions: [
          payment('purchase', 1000),
          payment('refund', 200, credit: true),
          payment(
            'credit next month',
            100,
            credit: true,
            date: DateTime(2026, 11, 1),
          ),
          payment('ignored', 500).copyWith(isIgnored: true),
          payment('transfer', 500).copyWith(transferGroupId: 'pair'),
        ],
        monthlyIncome: 10000,
      );
      expect(suggestions, {'c': 385});
      expect(
        await BudgetService.suggestBudgets(
          transactions: [payment('refund only', 500, credit: true)],
          monthlyIncome: 10000,
        ),
        isEmpty,
      );
    },
  );

  test('database-loaded budgets include current-period credits', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await LocalStorageService.saveTransactions([
      payment('purchase', 100, date: today),
      payment('refund', 20, credit: true, date: today),
      payment(
        'previous',
        500,
        credit: true,
        date: DateTime(now.year, now.month, 0),
      ),
    ]);
    final result = (await BudgetService.checkBudgets()).single;
    expect(result.debits, 100);
    expect(result.credits, 20);
    expect(result.spent, 80);
  });

  testWidgets(
    'phone cards and details show debit, credit, net and update after another credit',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sms = SmsService();
      addTearDown(sms.dispose);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await tester.runAsync(() async {
        await LocalStorageService.saveTransactions([
          payment('purchase', 1000, date: today),
          payment('refund', 250, credit: true, date: today),
        ]);
        await sms.reloadFromCache();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: sms,
          child: const MaterialApp(home: BudgetScreen()),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Net spent: \u20b9750 / \u20b91,000'), findsOneWidget);
      expect(find.text('Debits: \u20b91,000'), findsOneWidget);
      expect(find.text('Credits: \u20b9250'), findsOneWidget);
      expect(find.text('Remaining: \u20b9250'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('budget-net-c')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Net spent'), findsOneWidget);
      expect(find.text('Debits'), findsOneWidget);
      expect(find.text('Credits'), findsOneWidget);
      expect(
        tester
            .widgetList<TransactionCard>(find.byType(TransactionCard))
            .map((card) => card.tx.id),
        containsAll(['purchase', 'refund']),
      );
      await tester.runAsync(() async {
        await LocalStorageService.saveTransaction(
          payment('new refund', 1000, credit: true, date: today),
        );
        await sms.reloadFromCache();
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(find.text('\u20b9-250'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Net spent: \u20b9-250 / \u20b91,000'), findsOneWidget);
      expect(find.text('Remaining: \u20b91,250'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
