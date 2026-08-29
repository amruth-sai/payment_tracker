import 'package:flutter_test/flutter_test.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/models/local_backup.dart';
import 'package:payment_tracker/models/salary_cycle.dart';
import 'package:payment_tracker/models/transaction_review.dart';
import 'package:payment_tracker/services/salary_closeout_service.dart';
import 'package:payment_tracker/services/sms_parser.dart';
import 'package:payment_tracker/services/transaction_export_service.dart';
import 'package:payment_tracker/services/transfer_service.dart';

void main() {
  group('SmsParser.parseSync', () {
    test('extracts a debited UPI transaction', () {
      final transaction = SmsParser.parseSync(
        'Rs.1,250.50 debited from A/C XX1234 for UPI payment to SHOP. Ref 123456789012.',
        'HDFCBK',
        DateTime(2026, 8, 30, 10),
        'sms-1',
      );

      expect(transaction, isNotNull);
      expect(transaction!.amount, 1250.50);
      expect(transaction.type, TransactionType.debit);
      expect(transaction.source, PaymentSource.upi);
      expect(transaction.accountLast4, '1234');
      expect(transaction.referenceId, '123456789012');
    });

    test('ignores messages without a transaction amount', () {
      expect(
        SmsParser.parseSync(
          'Your bank statement is ready to view.',
          'HDFCBK',
          DateTime(2026, 8, 30),
          'sms-2',
        ),
        isNull,
      );
    });

    test('creates a review item when the transaction direction is unclear', () {
      final review = SmsParser.buildReviewCandidate(
        'INR 500 transaction alert for your account.',
        'HDFCBK',
        DateTime(2026, 8, 30, 10),
        'sms-review',
      );

      expect(review, isNotNull);
      expect(review!.amount, 500);
      expect(review.source, PaymentSource.bank);
    });

    test('does not create a review item for a clear debit', () {
      final review = SmsParser.buildReviewCandidate(
        'Rs.500 debited from A/C XX1234 for payment to SHOP.',
        'HDFCBK',
        DateTime(2026, 8, 30, 10),
        'sms-debit',
      );

      expect(review, isNull);
    });
  });

  group('MerchantRule', () {
    test('round-trips its locally stored values', () {
      final rule = MerchantRule(
        id: 'rule-1',
        matchText: 'tea stall',
        merchant: 'Tea Stall',
        standardCategoryId: 'food_dining',
        tag: 'Dining',
        createdAt: DateTime(2026, 8, 30),
      );

      final restored = MerchantRule.fromMap(rule.toMap());

      expect(restored.matchText, 'tea stall');
      expect(restored.merchant, 'Tea Stall');
      expect(restored.standardCategoryId, 'food_dining');
      expect(restored.tag, 'Dining');
    });
  });

  group('TransactionReview', () {
    test('round-trips its optional tag', () {
      final review = TransactionReview(
        id: 'review-1',
        amount: 500,
        source: PaymentSource.bank,
        sender: 'HDFCBK',
        date: DateTime(2026, 8, 30),
        rawMessage: 'INR 500 transaction alert.',
        tag: 'Dining',
        createdAt: DateTime(2026, 8, 30),
      );

      final restored = TransactionReview.fromMap(review.toMap());

      expect(restored.tag, 'Dining');
      expect(restored.copyWith(clearTag: true).tag, isNull);
    });
  });

  group('LocalBackup', () {
    test('round-trips a versioned backup snapshot', () {
      final backup = LocalBackup(
        createdAt: DateTime.utc(2026, 8, 30, 10),
        databaseVersion: 10,
        tables: {
          'transactions': [
            {'id': 'transaction-1', 'amount': 500},
          ],
          'user_settings': [
            {'key': 'currency', 'value': 'INR'},
          ],
        },
      );

      final restored = LocalBackup.fromJson(backup.toJson());

      expect(restored.databaseVersion, 10);
      expect(restored.transactionCount, 1);
      expect(restored.recordCount, 2);
      expect(restored.tables['user_settings']!.single['value'], 'INR');
    });

    test('rejects a backup with an unsupported format', () {
      expect(
        () => LocalBackup.fromJson({
          'format': 'unknown',
          'format_version': 1,
          'created_at': DateTime.utc(2026, 8, 30).toIso8601String(),
          'database_version': 10,
          'tables': <String, dynamic>{},
        }),
        throwsFormatException,
      );
    });
  });

  group('SalaryCloseoutService', () {
    test('summarizes a cycle without ignored expenses or transfers', () {
      final previousCycle = SalaryCycle(
        id: 'september',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 30, 23, 59, 59),
        salaryAmount: 1000,
        salaryTransactionId: 'salary-september',
        transactions: [
          _transaction(
            id: 'salary-september',
            amount: 1000,
            type: TransactionType.credit,
            sender: 'Employer',
            accountLast4: '1111',
            date: DateTime(2026, 9, 1),
            rawMessage: 'Salary',
          ).copyWith(isSalary: true),
          _transaction(
            id: 'food-september',
            amount: 100,
            type: TransactionType.debit,
            sender: 'Cafe',
            accountLast4: '1111',
            date: DateTime(2026, 9, 4),
            rawMessage: 'Cafe payment',
          ).copyWith(category: TransactionCategory.foodDining),
          _transaction(
            id: 'subscription-september',
            amount: 80,
            type: TransactionType.debit,
            sender: 'StreamBox',
            accountLast4: '1111',
            date: DateTime(2026, 9, 5),
            rawMessage: 'Subscription',
          ),
        ],
      );
      final targetCycle = SalaryCycle(
        id: 'october',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31, 23, 59, 59),
        salaryAmount: 1000,
        salaryTransactionId: 'salary-october',
        transactions: [
          _transaction(
            id: 'salary-october',
            amount: 1000,
            type: TransactionType.credit,
            sender: 'Employer',
            accountLast4: '1111',
            date: DateTime(2026, 10, 1),
            rawMessage: 'Salary',
          ).copyWith(isSalary: true),
          _transaction(
            id: 'food-october',
            amount: 300,
            type: TransactionType.debit,
            sender: 'Cafe',
            accountLast4: '1111',
            date: DateTime(2026, 10, 4),
            rawMessage: 'Cafe payment',
          ).copyWith(category: TransactionCategory.foodDining),
          _transaction(
            id: 'reimbursable-october',
            amount: 75,
            type: TransactionType.debit,
            sender: 'Office Shop',
            accountLast4: '1111',
            date: DateTime(2026, 10, 6),
            rawMessage: 'Office supplies',
          ).copyWith(tag: 'reimbursable'),
          _transaction(
            id: 'subscription-october',
            amount: 80,
            type: TransactionType.debit,
            sender: 'StreamBox',
            accountLast4: '1111',
            date: DateTime(2026, 10, 5),
            rawMessage: 'Subscription',
          ),
          _transaction(
            id: 'ignored-october',
            amount: 900,
            type: TransactionType.debit,
            sender: 'Ignored Shop',
            accountLast4: '1111',
            date: DateTime(2026, 10, 7),
            rawMessage: 'Ignored',
          ).copyWith(isIgnored: true),
        ],
      );
      final olderSubscription = _transaction(
        id: 'subscription-august',
        amount: 80,
        type: TransactionType.debit,
        sender: 'StreamBox',
        accountLast4: '1111',
        date: DateTime(2026, 8, 5),
        rawMessage: 'Subscription',
      );

      final closeout = SalaryCloseoutService.build(
        cycle: targetCycle,
        previousCycle: previousCycle,
        allTransactions: [
          ...previousCycle.transactions,
          ...targetCycle.transactions,
          olderSubscription,
        ],
      );

      expect(closeout.income, 1000);
      expect(closeout.spending, 455);
      expect(closeout.savings, 545);
      expect(closeout.reimbursableAmount, 75);
      expect(closeout.reimbursableTransactions, hasLength(1));
      expect(
        closeout.recurringPayments.map((payment) => payment.merchant),
        contains('StreamBox'),
      );
      expect(closeout.categoryChanges.first.categoryId, 'food_dining');
      expect(closeout.categoryChanges.first.difference, 200);
    });
  });

  group('TransferService.detectPotentialTransfers', () {
    test('pairs matching debit and credit transactions from different accounts', () {
      final date = DateTime(2026, 8, 30, 10);
      final debit = _transaction(
        id: 'debit',
        amount: 5000,
        type: TransactionType.debit,
        sender: 'HDFC Bank',
        accountLast4: '1111',
        date: date,
        rawMessage: 'IMPS transfer sent',
      );
      final credit = _transaction(
        id: 'credit',
        amount: 5000,
        type: TransactionType.credit,
        sender: 'ICICI Bank',
        accountLast4: '2222',
        date: date.add(const Duration(minutes: 2)),
        rawMessage: 'IMPS transfer received',
      );

      final pairs = TransferService.detectPotentialTransfers([debit, credit]);

      expect(pairs, hasLength(1));
      expect(pairs.single.debitTransaction.id, 'debit');
      expect(pairs.single.creditTransaction.id, 'credit');
    });
  });

  group('TransactionExportService.buildExport', () {
    test('includes tags and excludes ignored transactions', () {
      final included = _transaction(
        id: 'included',
        amount: 900,
        type: TransactionType.debit,
        sender: 'HDFC Bank',
        accountLast4: '1111',
        date: DateTime(2026, 8, 30),
        rawMessage: 'private message',
      ).copyWith(tag: 'reimbursable');
      final ignored = _transaction(
        id: 'ignored',
        amount: 250,
        type: TransactionType.debit,
        sender: 'HDFC Bank',
        accountLast4: '1111',
        date: DateTime(2026, 8, 30),
        rawMessage: 'private message',
      ).copyWith(isIgnored: true);

      final start = DateTime(2026, 8, 1);
      final end = DateTime(2026, 8, 31, 23, 59, 59, 999);
      final export = TransactionExportService.buildExport(
        [included, ignored],
        start: start,
        end: end,
        periodLabel: 'August 2026 salary month',
      );
      final transactions = export['transactions'] as List<dynamic>;
      final transaction = transactions.single as Map<String, dynamic>;
      final period = export['period'] as Map<String, dynamic>;

      expect(export['transaction_count'], 1);
      expect(period['label'], 'August 2026 salary month');
      expect(period['start'], start.toIso8601String());
      expect(period['end'], end.toIso8601String());
      expect(transaction['tag'], 'reimbursable');
      expect(transaction.containsKey('raw_message'), isFalse);
    });
  });
}

Transaction _transaction({
  required String id,
  required double amount,
  required TransactionType type,
  required String sender,
  required String accountLast4,
  required DateTime date,
  required String rawMessage,
}) {
  return Transaction(
    id: id,
    amount: amount,
    type: type,
    source: PaymentSource.bank,
    sender: sender,
    accountLast4: accountLast4,
    date: date,
    rawMessage: rawMessage,
  );
}
