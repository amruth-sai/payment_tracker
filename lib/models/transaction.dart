// lib/models/transaction.dart

enum TransactionType { credit, debit, unknown }

enum PaymentSource { upi, bank, card, wallet, unknown }

class Transaction {
  final String id;
  final double amount;
  final TransactionType type;
  final PaymentSource source;
  final String sender;       // bank/UPI sender name
  final String? merchant;    // merchant name if available
  final String? accountLast4;
  final DateTime date;
  final String rawMessage;
  final String? referenceId;
  final double? balance;     // available balance after txn

  Transaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.source,
    required this.sender,
    this.merchant,
    this.accountLast4,
    required this.date,
    required this.rawMessage,
    this.referenceId,
    this.balance,
  });

  bool get isCredit => type == TransactionType.credit;
  bool get isDebit => type == TransactionType.debit;

  String get typeLabel => isCredit ? 'Received' : 'Paid';

  String get sourceLabel {
    switch (source) {
      case PaymentSource.upi:
        return 'UPI';
      case PaymentSource.bank:
        return 'Bank Transfer';
      case PaymentSource.card:
        return 'Card';
      case PaymentSource.wallet:
        return 'Wallet';
      default:
        return 'Payment';
    }
  }

  String get displayName => merchant ?? sender;
}
