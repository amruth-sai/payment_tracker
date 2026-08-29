import 'package:flutter_test/flutter_test.dart';
import 'package:payment_tracker/models/transaction.dart';
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
