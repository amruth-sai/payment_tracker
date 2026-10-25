import 'package:flutter_test/flutter_test.dart';
import 'package:payment_tracker/models/account.dart';
import 'package:payment_tracker/models/app_category.dart';
import 'package:payment_tracker/models/budget.dart';
import 'package:payment_tracker/models/local_backup.dart';
import 'package:payment_tracker/models/sender_mapping.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/models/transaction_review.dart';
import 'package:payment_tracker/services/anomaly_service.dart';
import 'package:payment_tracker/services/budget_service.dart';
import 'package:payment_tracker/services/database_schema.dart';
import 'package:payment_tracker/services/local_storage_service.dart';
import 'package:payment_tracker/services/sms_fingerprint.dart';
import 'package:payment_tracker/services/sms_parser.dart';
import 'package:payment_tracker/services/transfer_service.dart';
import 'package:payment_tracker/utils/format_utils.dart';
import 'package:payment_tracker/utils/date_utils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

Transaction payment(
  String id, {
  DateTime? date,
  double amount = 10.25,
  TransactionType type = TransactionType.debit,
  String? categoryId,
  String sender = 'BANK',
  String? accountId,
}) => Transaction(
  id: id,
  amount: amount,
  type: type,
  source: PaymentSource.bank,
  sender: sender,
  date: date ?? DateTime(2026, 10, 1),
  rawMessage: 'payment',
  categoryId: categoryId,
  accountId: accountId,
);

AppCategory category(String id, String name) => AppCategory(
  id: id,
  name: name,
  emoji: 'X',
  colorValue: 0xff009688,
  createdAt: DateTime(2026, 10, 1),
);

void main() {
  group('First-release SQLite', () {
    late Database db;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchema.create,
        ),
      );
      LocalStorageService.useDatabaseForTesting(db);
    });
    tearDown(() async {
      await LocalStorageService.close();
      SmsParser.clearSenderMappingCache();
    });

    test(
      'bulk category assignment preserves all other fields and deduplicates IDs',
      () async {
        await LocalStorageService.saveCategory(category('a', 'Original'));
        await LocalStorageService.saveCategory(category('b', 'New'));
        await LocalStorageService.saveTransactions([
          payment(
            'one',
            categoryId: 'a',
          ).copyWith(note: 'keep', tag: 'work', isIgnored: true),
          payment('two', categoryId: 'a').copyWith(
            transferGroupId: 'pair',
            transferPartnerId: 'three',
            isTransferSource: true,
          ),
          payment(
            'three',
            categoryId: 'a',
            type: TransactionType.credit,
          ).copyWith(
            transferGroupId: 'pair',
            transferPartnerId: 'two',
            isTransferDestination: true,
          ),
        ]);
        final before = await db.query('transactions', orderBy: 'id');
        expect(
          await LocalStorageService.updateTransactionCategories(
            transactionIds: ['one', 'two', 'one'],
            categoryId: 'b',
          ),
          2,
        );
        final after = await db.query('transactions', orderBy: 'id');
        for (var i = 0; i < before.length; i++) {
          expect(after[i], {
            ...before[i],
            if (before[i]['id'] != 'three') ...{
              'category_id': 'b',
              'category_source': 'user',
            },
          });
        }
      },
    );

    test(
      'bulk category assignment rolls back missing transactions or categories',
      () async {
        await LocalStorageService.saveCategory(category('a', 'New'));
        await LocalStorageService.saveTransaction(payment('one'));
        await expectLater(
          LocalStorageService.updateTransactionCategories(
            transactionIds: ['one', 'missing'],
            categoryId: 'a',
          ),
          throwsStateError,
        );
        expect(
          (await LocalStorageService.getAllTransactions()).single.categoryId,
          isNull,
        );
        await expectLater(
          LocalStorageService.updateTransactionCategories(
            transactionIds: ['one'],
            categoryId: 'missing',
          ),
          throwsStateError,
        );
        expect(
          (await LocalStorageService.getAllTransactions()).single.categoryId,
          isNull,
        );
      },
    );

    test(
      'starts at v1 with no categories, rules, budgets, or migration tables',
      () async {
        expect(await db.getVersion(), 1);
        expect(await LocalStorageService.getAllCategories(), isEmpty);
        expect(await LocalStorageService.getMerchantRules(), isEmpty);
        expect(await LocalStorageService.getAllBudgets(), isEmpty);
        final names = (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        )).map((row) => row['name']);
        expect(names, containsAll(DatabaseSchema.tables));
        expect(names, isNot(contains('custom_categories')));
        expect(names, isNot(contains('standard_categories')));
      },
    );

    test(
      'category rename retains every reference; deletion preserves payments',
      () async {
        await LocalStorageService.saveCategory(
          category('c', 'My own category'),
        );
        await LocalStorageService.saveTransaction(
          payment('t', categoryId: 'c'),
        );
        await LocalStorageService.saveBudget(
          Budget(id: 'b', categoryId: 'c', monthlyLimit: 100.55),
        );
        await db.insert(
          'merchant_rules',
          MerchantRule(
            id: 'r',
            matchText: 'shop',
            merchant: 'Shop',
            categoryId: 'c',
            createdAt: DateTime.now(),
          ).toMap(),
        );
        await db.insert(
          'transaction_reviews',
          TransactionReview(
            id: 'review',
            amount: 10,
            source: PaymentSource.bank,
            sender: 'BANK',
            date: DateTime.now(),
            rawMessage: 'alert',
            categoryId: 'c',
            createdAt: DateTime.now(),
          ).toMap(),
        );
        await LocalStorageService.saveCategory(category('c', 'Renamed'));
        expect(
          (await LocalStorageService.getAllBudgets()).single.categoryId,
          'c',
        );
        expect(
          (await LocalStorageService.getAllTransactions()).single.categoryId,
          'c',
        );
        await LocalStorageService.deleteCategory('c');
        expect(
          (await LocalStorageService.getAllTransactions()).single.categoryId,
          isNull,
        );
        expect(
          (await db.query('transaction_reviews')).single['category_id'],
          isNull,
        );
        expect(
          (await db.query('merchant_rules')).single['category_id'],
          isNull,
        );
        expect(await LocalStorageService.getAllBudgets(), isEmpty);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );

    test(
      'case-insensitive duplicate and empty category names are rejected',
      () async {
        await LocalStorageService.saveCategory(category('1', 'Food'));
        await expectLater(
          LocalStorageService.saveCategory(category('2', ' food ')),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          LocalStorageService.saveCategory(category('3', ' ')),
          throwsArgumentError,
        );
        expect((await LocalStorageService.getAllCategories()).length, 1);
      },
    );

    test(
      'unknown categories and duplicate category budgets cannot persist',
      () async {
        await expectLater(
          LocalStorageService.saveTransaction(
            payment('invalid', categoryId: 'missing'),
          ),
          throwsA(isA<DatabaseException>()),
        );
        await LocalStorageService.saveCategory(category('c', 'Category'));
        await LocalStorageService.saveBudget(
          Budget(id: '1', categoryId: 'c', monthlyLimit: 1),
        );
        await expectLater(
          LocalStorageService.saveBudget(
            Budget(id: '2', categoryId: 'c', monthlyLimit: 2),
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          (await LocalStorageService.getAllBudgets()).single.monthlyLimit,
          1,
        );
      },
    );

    test(
      'money persists as integer paise and totals match across budgets',
      () async {
        await LocalStorageService.saveCategory(category('c', 'Category'));
        await LocalStorageService.saveBudget(
          Budget(id: 'b', categoryId: 'c', monthlyLimit: 12.34),
        );
        final rows = [
          payment('1', amount: 0.1, categoryId: 'c'),
          payment('2', amount: 0.2, categoryId: 'c'),
          payment('ignored', categoryId: 'c').copyWith(isIgnored: true),
          payment(
            'transfer',
            categoryId: 'c',
          ).copyWith(transferGroupId: 'pair'),
        ];
        await LocalStorageService.saveTransactions(rows);
        final stored = await db.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['1'],
        );
        expect(stored.single['amount'], 10);
        expect((await db.query('budgets')).single['monthly_limit'], 1234);
        expect(
          (await LocalStorageService.getAllTransactions())
              .where((t) => t.isExpense)
              .totalAmount,
          0.3,
        );
        final status = (await BudgetService.checkBudgets(
          transactions: rows,
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 31),
        )).single;
        expect(status.spent, closeTo(0.3, 0.000001));
      },
    );

    test(
      'editing an account preserves sender mappings and linked transactions',
      () async {
        final account = Account(
          id: 'a',
          name: 'Bank',
          type: AccountType.bankAccount,
        );
        await LocalStorageService.saveAccount(account);
        await LocalStorageService.saveSenderMapping(
          SenderMapping(
            id: 'm',
            senderId: 'BANK',
            accountId: 'a',
            createdAt: DateTime.now(),
          ),
        );
        await LocalStorageService.saveTransaction(payment('t', accountId: 'a'));
        await LocalStorageService.saveAccount(
          account.copyWith(name: 'Renamed'),
        );
        expect(
          (await LocalStorageService.getAllSenderMappings()).single.accountId,
          'a',
        );
        expect(
          (await LocalStorageService.getAllTransactions()).single.accountId,
          'a',
        );
        await LocalStorageService.deleteAccount('a');
        expect(await LocalStorageService.getAllSenderMappings(), isEmpty);
        expect(
          (await LocalStorageService.getAllTransactions()).single.accountId,
          isNull,
        );
      },
    );

    test(
      'salary cycles include the final day and regenerate without obsolete rows',
      () async {
        final start = DateTime(2026, 9, 25, 9);
        final next = DateTime(2026, 10, 25, 9);
        await LocalStorageService.saveTransactions([
          payment(
            's1',
            date: start,
            type: TransactionType.credit,
            amount: 50000,
          ).copyWith(isSalary: true),
          payment(
            's2',
            date: next,
            type: TransactionType.credit,
            amount: 50000,
          ).copyWith(isSalary: true),
          payment('last', date: DateTime(2026, 10, 24, 23, 59)),
          payment('boundary', date: next),
        ]);
        final cycles = await LocalStorageService.generateSalaryCycles();
        final first = cycles.singleWhere((c) => c.salaryTransactionId == 's1');
        expect(first.endDate, next);
        expect(first.transactions.map((t) => t.id), contains('last'));
        expect(
          first.transactions.map((t) => t.id),
          isNot(contains('boundary')),
        );
        await LocalStorageService.markAsSalary('s2', false);
        expect(
          (await LocalStorageService.generateSalaryCycles()).single.isCurrent,
          isTrue,
        );
        await LocalStorageService.markAsSalary('s1', false);
        expect(await LocalStorageService.generateSalaryCycles(), isEmpty);
        expect(await db.query('salary_cycles'), isEmpty);
      },
    );

    test(
      'direction correction unlinks both transfer legs atomically',
      () async {
        final debit = payment('debit', sender: 'A');
        final credit = payment(
          'credit',
          sender: 'B',
          type: TransactionType.credit,
        );
        await LocalStorageService.saveTransactions([debit, credit]);
        await TransferService.mergeAsTransfer(debit, credit);
        await LocalStorageService.updateTransactionType(
          'debit',
          TransactionType.credit,
        );
        final rows = await LocalStorageService.getAllTransactions();
        expect(
          rows.every(
            (tx) => tx.transferGroupId == null && tx.transferPartnerId == null,
          ),
          isTrue,
        );
        expect(rows.every((tx) => tx.isCredit), isTrue);
      },
    );

    test(
      'saving a salary transaction again does not cascade-delete its cycle',
      () async {
        final salary = payment(
          'salary',
          type: TransactionType.credit,
        ).copyWith(isSalary: true);
        await LocalStorageService.saveTransaction(salary);
        await LocalStorageService.generateSalaryCycles();
        await LocalStorageService.saveTransaction(
          salary.copyWith(note: 'updated'),
        );
        expect(await db.query('salary_cycles'), hasLength(1));
      },
    );

    test(
      'backup round-trip preserves references and resets device scan cursor',
      () async {
        await LocalStorageService.saveCategory(category('c', 'Category'));
        await LocalStorageService.saveTransaction(
          payment('t', categoryId: 'c'),
        );
        await LocalStorageService.setLastSmsScanAt(DateTime.now());
        final backup = await LocalStorageService.createBackup();
        await LocalStorageService.restoreBackup(
          backup,
          BackupRestoreMode.replace,
        );
        expect(
          (await LocalStorageService.getAllTransactions()).single.categoryId,
          'c',
        );
        expect(await LocalStorageService.getLastSmsScanAt(), isNull);
        expect(
          await LocalStorageService.restoreBackup(
            backup,
            BackupRestoreMode.merge,
          ),
          1,
        ); // only cleared cursor setting
        expect(await LocalStorageService.getLastSmsScanAt(), isNull);
        expect((await LocalStorageService.getAllTransactions()).length, 1);
      },
    );

    test(
      'invalid restore rolls back all deletion and rejects earlier schemas',
      () async {
        await LocalStorageService.saveTransaction(payment('keep'));
        final backup = await LocalStorageService.createBackup();
        final tables = {
          ...backup.tables,
          'transactions': [
            {
              ...backup.tables['transactions']!.single,
              'category_id': 'missing',
            },
          ],
        };
        await expectLater(
          LocalStorageService.restoreBackup(
            LocalBackup(
              createdAt: DateTime.now(),
              databaseVersion: 1,
              tables: tables,
            ),
            BackupRestoreMode.replace,
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          (await LocalStorageService.getAllTransactions()).single.id,
          'keep',
        );
        await expectLater(
          LocalStorageService.restoreBackup(
            LocalBackup(
              createdAt: DateTime.now(),
              databaseVersion: 8,
              tables: backup.tables,
            ),
            BackupRestoreMode.replace,
          ),
          throwsFormatException,
        );
      },
    );
  });

  group('Correctness regressions', () {
    Transaction? parse(String body, {String sender = 'BANK'}) =>
        SmsParser.parseSync(body, sender, DateTime(2026), 'sms');
    test(
      'failed and pending payments do not create transactions or review items',
      () {
        for (final body in [
          'Rs.500 payment failed, account not debited.',
          'Rs.500 payment pending.',
        ]) {
          expect(parse(body), isNull);
          expect(
            SmsParser.buildReviewCandidate(body, 'BANK', DateTime(2026), 'sms'),
            isNull,
          );
        }
      },
    );
    test('card purchases and refunds use completed movement direction', () {
      expect(
        parse('Your credit card was used for INR 200 at SHOP.')?.type,
        TransactionType.debit,
      );
      expect(
        parse(
          'Refund of INR 200 for purchase at SHOP credited.',
          sender: 'ONECARD',
        )?.type,
        TransactionType.credit,
      );
      expect(parse('INR 200 transaction alert.', sender: 'ONECARD'), isNull);
    });
    test(
      'balance-first SMS extracts payment and ambiguous amounts remain unparsed',
      () {
        expect(
          parse(
            'Avl Bal: INR 9000. INR 500 debited from your account.',
          )?.amount,
          500,
        );
        expect(parse('INR 100 debited and INR 200 debited.'), isNull);
      },
    );
    test(
      'fingerprints ignore Android row IDs and distinguish different messages',
      () {
        String fingerprint(String body, {bool sent = false}) =>
            SmsFingerprint.of(
              sender: 'DM-BANK',
              body: body,
              date: DateTime(2026),
              isSent: sent,
            );
        expect(fingerprint('INR 100 debited'), fingerprint('INR 100  debited'));
        expect(
          fingerprint('INR 100 debited'),
          isNot(fingerprint('INR 200 debited')),
        );
        expect(
          fingerprint('INR 100 debited'),
          isNot(fingerprint('INR 100 debited', sent: true)),
        );
      },
    );
    test(
      'transfer candidates span midnight and exclude the same mapped account',
      () {
        final debit = payment(
          'd',
          date: DateTime(2026, 10, 1, 23, 59),
          accountId: 'a',
        );
        final credit = payment(
          'c',
          date: DateTime(2026, 10, 2, 0, 1),
          type: TransactionType.credit,
          sender: 'OTHER',
          accountId: 'b',
        );
        expect(
          TransferService.detectPotentialTransfers([debit, credit]),
          hasLength(1),
        );
        expect(
          TransferService.detectPotentialTransfers([
            debit,
            credit.copyWith(accountId: 'a'),
          ]),
          isEmpty,
        );
        expect(
          TransferService.detectPotentialTransfers([
            debit.copyWith(isIgnored: true),
            credit,
          ]),
          isEmpty,
        );
      },
    );
    test('anomaly results and IDs do not depend on input order', () {
      final now = DateTime.now();
      final rows = [
        for (var i = 1; i <= 5; i++)
          payment('$i', date: now.subtract(Duration(days: i * 8)), amount: 100),
        payment(
          'recent',
          date: now.subtract(const Duration(days: 1)),
          amount: 1000,
        ),
      ];
      final first = AnomalyService.detectAnomalies(rows);
      expect(first, isNotEmpty);
      expect(
        AnomalyService.detectAnomalies(rows.reversed.toList()).map((a) => a.id),
        first.map((a) => a.id),
      );
      expect(
        AnomalyService.detectAnomalies(
          rows.reversed.toList(),
        ).map((a) => a.message),
        first.map((a) => a.message),
      );
    });
    test('salary day 31 clamps to February without omitting its last day', () {
      final period = AppDateUtils.salaryPeriod(DateTime(2026, 2, 28, 10), 31);
      expect(period.$1, DateTime(2026, 2, 28));
      expect(period.$2, DateTime(2026, 3, 31));
      final previous = AppDateUtils.salaryPeriod(DateTime(2026, 2, 27, 23), 31);
      expect(previous.$1, DateTime(2026, 1, 31));
      expect(previous.$2, DateTime(2026, 2, 28));
    });
    test('large currency displays preserve paise', () {
      expect(FormatUtils.formatAmount(1234.56), '1,234.56');
      expect(FormatUtils.formatAmount(100000.12), '1,00,000.12');
    });
  });
}
