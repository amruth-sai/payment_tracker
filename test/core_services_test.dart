import 'package:flutter_test/flutter_test.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/services/sms_parser.dart';
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
