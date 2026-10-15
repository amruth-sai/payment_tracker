import 'package:flutter_test/flutter_test.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/models/local_backup.dart';
import 'package:payment_tracker/models/salary_cycle.dart';
import 'package:payment_tracker/models/transaction_review.dart';
import 'package:payment_tracker/models/sms_processing_record.dart';
import 'package:payment_tracker/services/category_service.dart';
import 'package:payment_tracker/services/budget_service.dart';
import 'package:payment_tracker/services/salary_closeout_service.dart';
import 'package:payment_tracker/services/sms_parser.dart';
import 'package:payment_tracker/services/sms_processing_service.dart';
import 'package:payment_tracker/services/transaction_export_service.dart';
import 'package:payment_tracker/services/transfer_service.dart';
import 'package:payment_tracker/services/transaction_window_service.dart';

void main() {
  group('Message decisions', () {
    test(
      'nonpayment SMS has an explained skip without retaining its body',
      () async {
        final processor = SmsProcessingService();
        final result = await processor.process(
          id: 'sms-nonpayment',
          sender: 'SHOP',
          body: 'Your order is ready.',
          date: DateTime(2026, 10, 6),
        );
        expect(result.transaction, isNull);
        expect(result.review, isNull);
        expect(result.record.outcome, SmsProcessingOutcome.skipped);
        expect(result.record.reason, 'sender_not_recognized');
        expect(result.record.rawMessage, isNull);
      },
    );

    test('sent personal messages are not treated as bank alerts', () async {
      final processor = SmsProcessingService();
      final result = await processor.process(
        id: 'sms-sent',
        sender: '9876543210',
        body: 'I paid Rs.500 for lunch.',
        date: DateTime(2026, 10, 6),
        isSent: true,
      );
      expect(result.transaction, isNull);
      expect(result.record.reason, 'sent_unrecognized');
      expect(result.record.rawMessage, isNull);
    });

    test('personal inbox messages with an amount are not retained', () async {
      final processor = SmsProcessingService();
      final result = await processor.process(
        id: 'sms-personal',
        sender: '9876543210',
        body: 'I paid Rs.500 for lunch.',
        date: DateTime(2026, 10, 6),
      );
      expect(result.transaction, isNull);
      expect(result.review, isNull);
      expect(result.record.rawMessage, isNull);
    });

    test(
      'payment OTP messages are skipped without storing their body',
      () async {
        final processor = SmsProcessingService();
        final result = await processor.process(
          id: 'sms-otp',
          sender: 'HDFCBK',
          body: 'OTP 123456 for your Rs.500 payment. Do not share this code.',
          date: DateTime(2026, 10, 6),
        );
        expect(result.transaction, isNull);
        expect(result.review, isNull);
        expect(result.record.reason, 'security_message');
        expect(result.record.rawMessage, isNull);
      },
    );

    test('an unfamiliar payment sender is eligible for parsing', () {
      expect(
        SmsParser.isLikelyPaymentMessage(
          'NEWBANK',
          'INR 500 debited from your account for UPI payment.',
        ),
        isTrue,
      );
      expect(
        SmsParser.isLikelyPaymentMessage('SHOP', 'Your order is ready.'),
        isFalse,
      );
    });

    test('amount detection accepts rupees without matching ordinary words', () {
      expect(SmsParser.hasAmountIndicator('First reminder'), isFalse);
      expect(SmsParser.hasAmountIndicator('₹500 transaction alert'), isTrue);
      expect(
        SmsParser.buildReviewCandidate(
          '₹500 transaction alert for your account.',
          'NEWBANK',
          DateTime(2026, 10, 6),
          'rupee-review',
        ),
        isNotNull,
      );
    });

    test('scan outcomes retain a reason and an optional message body', () {
      final record = SmsProcessingRecord(
        smsId: 'sms-1',
        sender: 'NEWBANK',
        date: DateTime(2026, 10, 6),
        outcome: SmsProcessingOutcome.skipped,
        reason: 'amount_not_found',
        folder: 'inbox',
        rawMessage: 'Amount Rs. unclear',
      );
      final restored = SmsProcessingRecord.fromMap(record.toMap());
      expect(restored.outcome, SmsProcessingOutcome.skipped);
      expect(restored.reason, 'amount_not_found');
      expect(restored.folder, 'inbox');
      expect(restored.rawMessage, 'Amount Rs. unclear');
    });

    test('an ignored review item remains restorable', () {
      final review = TransactionReview(
        id: 'review-ignored',
        amount: 500,
        source: PaymentSource.bank,
        sender: 'BANK',
        date: DateTime(2026, 10, 6),
        rawMessage: 'INR 500 transaction alert.',
        categoryId: 'shopping',
        categorySource: 'merchant_rule',
        createdAt: DateTime(2026, 10, 6),
        isIgnored: true,
      );
      final restored = TransactionReview.fromMap(review.toMap());
      expect(restored.isIgnored, isTrue);
      expect(restored.categorySource, 'merchant_rule');
      expect(restored.copyWith(isIgnored: false).isIgnored, isFalse);
    });
  });

  group('Category precedence', () {
    test(
      'processing applies a merchant rule to a parsed transaction',
      () async {
        final rule = MerchantRule(
          id: 'merchant-rule',
          matchText: 'coffee shop',
          merchant: 'My Cafe',
          categoryId: 'dining',
          tag: 'weekday',
          createdAt: DateTime(2026, 10, 6),
        );
        final processor = SmsProcessingService(
          merchantRules: [rule],
          transactionParser: (body, sender, date, id) async => _transaction(
            id: id,
            amount: 150,
            type: TransactionType.debit,
            sender: sender,
            accountLast4: '1234',
            date: date,
            rawMessage: body,
          ),
        );
        final result = await processor.process(
          id: 'sms-cafe',
          sender: 'NEWBANK',
          body: 'INR 150 debited from account at coffee shop.',
          date: DateTime(2026, 10, 6),
        );
        expect(result.transaction?.merchant, 'My Cafe');
        expect(result.transaction?.categoryId, 'dining');
        expect(result.transaction?.categorySource, 'merchant_rule');
        expect(result.transaction?.tag, 'weekday');
        expect(result.record.outcome, SmsProcessingOutcome.transaction);
      },
    );

    test(
      'an ambiguous message goes to review with its merchant rule',
      () async {
        final rule = MerchantRule(
          id: 'review-rule',
          matchText: 'tea stall',
          merchant: 'Tea Stall',
          categoryId: 'dining',
          createdAt: DateTime(2026, 10, 6),
        );
        final processor = SmsProcessingService(
          merchantRules: [rule],
          transactionParser: (body, sender, date, id) async => null,
        );
        final result = await processor.process(
          id: 'sms-tea',
          sender: 'NEWBANK',
          body: 'INR 50 transaction alert for account at tea stall.',
          date: DateTime(2026, 10, 6),
        );
        expect(result.review?.merchant, 'Tea Stall');
        expect(result.review?.categoryId, 'dining');
        expect(result.review?.categorySource, 'merchant_rule');
        expect(result.record.outcome, SmsProcessingOutcome.needsReview);
      },
    );

    test('the most specific matching merchant rule wins', () {
      final older = DateTime(2026, 10, 1);
      final rules = [
        MerchantRule(
          id: 'generic',
          matchText: 'coffee',
          merchant: 'Coffee',
          createdAt: older,
        ),
        MerchantRule(
          id: 'specific',
          matchText: 'coffee shop',
          merchant: 'Coffee Shop',
          createdAt: older,
        ),
      ];
      expect(
        CategoryService.matchingMerchantRule(rules, 'Paid at COFFEE SHOP')?.id,
        'specific',
      );
    });

    test('a disabled rule never matches, even when it is more specific', () {
      final rules = [
        MerchantRule(
          id: 'suggested',
          matchText: 'coffee shop',
          merchant: 'Suggested Cafe',
          isEnabled: false,
          createdAt: DateTime(2026, 10, 6),
        ),
        MerchantRule(
          id: 'active',
          matchText: 'coffee',
          merchant: 'Coffee',
          createdAt: DateTime(2026, 10, 6),
        ),
      ];
      expect(
        CategoryService.matchingMerchantRule(rules, 'Paid at coffee shop')?.id,
        'active',
      );
      expect(
        CategoryService.matchingMerchantRule([
          rules.first,
        ], 'Paid at coffee shop'),
        isNull,
      );
    });

    test('only user rules assign categories', () {
      final transaction = _transaction(
        id: 'category-1',
        amount: 150,
        type: TransactionType.debit,
        sender: 'HDFC',
        accountLast4: '1234',
        date: DateTime(2026, 10, 6),
        rawMessage: 'Rs.150 spent at a cafe',
      );
      final rule = MerchantRule(
        id: 'rule-1',
        matchText: 'cafe',
        merchant: 'Cafe',
        categoryId: 'shopping',
        createdAt: DateTime(2026, 10, 6),
      );
      final automatic = CategoryService.assign(transaction);
      final withRule = CategoryService.assign(transaction, merchantRule: rule);
      expect(automatic.source, isNull);
      expect(withRule.categoryId, 'shopping');
      expect(withRule.source, 'merchant_rule');
    });
  });

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
        categoryId: 'food_dining',
        tag: 'Dining',
        createdAt: DateTime(2026, 8, 30),
      );

      final restored = MerchantRule.fromMap(rule.toMap());

      expect(restored.matchText, 'tea stall');
      expect(restored.merchant, 'Tea Stall');
      expect(restored.categoryId, 'food_dining');
      expect(restored.tag, 'Dining');
      expect(restored.isEnabled, isTrue);
    });

    test('disabled state is persisted', () {
      final rule = MerchantRule(
        id: 'suggested-youtube',
        matchText: 'Youtube',
        merchant: 'YouTube',
        createdAt: DateTime(2026, 10, 6),
        isEnabled: false,
      );
      expect(MerchantRule.fromMap(rule.toMap()).isEnabled, isFalse);
      expect(rule.copyWith(isEnabled: true).isEnabled, isTrue);
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
        databaseVersion: 1,
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

      expect(restored.databaseVersion, 1);
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
          ).copyWith(categoryId: 'food_dining'),
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
          ).copyWith(categoryId: 'food_dining'),
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
    test(
      'pairs matching debit and credit transactions from different accounts',
      () {
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
      },
    );
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

  group('TransactionWindowService', () {
    Transaction payment(String id, DateTime date) => _transaction(
      id: id,
      amount: 100,
      type: TransactionType.debit,
      sender: 'HDFC',
      accountLast4: '1234',
      date: date,
      rawMessage: 'payment',
    );

    test('date range includes the entire first and last day', () {
      final rows = [
        payment('before', DateTime(2026, 10, 6, 23, 59)),
        payment('first', DateTime(2026, 10, 7)),
        payment('last', DateTime(2026, 10, 8, 23, 59, 59, 999)),
        payment('after', DateTime(2026, 10, 9)),
      ];
      final selected = TransactionWindowService.byDateRange(
        rows,
        DateTime(2026, 10, 7),
        DateTime(2026, 10, 8),
      );
      expect(selected.map((tx) => tx.id), ['first', 'last']);
    });

    test('transaction boundaries are inclusive with stable timestamp ties', () {
      final time = DateTime(2026, 10, 7, 12);
      final rows = [
        payment('c', time),
        payment('a', time),
        payment('d', time.add(const Duration(minutes: 1))),
        payment('b', time),
      ];
      final selected = TransactionWindowService.betweenTransactions(
        rows,
        'c',
        'a',
      );
      expect(selected.map((tx) => tx.id), ['a', 'b', 'c']);
    });
  });

  group('Budget coverage', () {
    Transaction payment(String id, DateTime date) => _transaction(
      id: id,
      amount: 100,
      type: TransactionType.debit,
      sender: 'HDFC',
      accountLast4: '1234',
      date: date,
      rawMessage: 'payment',
    );

    test('one category is used consistently for budgets', () {
      final trip = payment(
        'trip',
        DateTime(2026, 10, 7),
      ).copyWith(categoryId: 'holiday');
      expect(BudgetService.categoryIdForTransaction(trip), 'holiday');
      expect(
        BudgetService.outsideBudgetTransactions(
          transactions: [trip],
          budgetCategoryIds: {'shopping'},
        ).map((tx) => tx.id),
        ['trip'],
      );
      expect(
        BudgetService.outsideBudgetTransactions(
          transactions: [trip],
          budgetCategoryIds: {'holiday'},
        ),
        isEmpty,
      );
    });

    test('lists only uncovered spending inside the selected period', () {
      final firstDay = DateTime(2026, 10, 1);
      final lastDay = DateTime(2026, 10, 31, 23, 59, 59, 999);
      final rows = [
        payment('earlier', DateTime(2026, 9, 30)),
        payment('covered', firstDay).copyWith(categoryId: 'shopping'),
        payment('uncategorized', lastDay),
        payment('rent', firstDay).copyWith(categoryId: 'rent'),
        payment('ignored', firstDay).copyWith(isIgnored: true),
        payment('transfer', firstDay).copyWith(transferGroupId: 'pair'),
        payment('salary', firstDay).copyWith(isSalary: true),
        _transaction(
          id: 'credit',
          amount: 100,
          type: TransactionType.credit,
          sender: 'HDFC',
          accountLast4: '1234',
          date: firstDay,
          rawMessage: 'credit',
        ),
      ];
      final uncovered = BudgetService.outsideBudgetTransactions(
        transactions: rows,
        budgetCategoryIds: {'shopping'},
        start: firstDay,
        end: lastDay,
      );
      expect(uncovered.map((tx) => tx.id), ['uncategorized', 'rent']);
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
