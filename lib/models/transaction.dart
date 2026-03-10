// lib/models/transaction.dart

enum TransactionType { credit, debit, unknown }

enum PaymentSource { upi, bank, card, wallet, unknown }

class Transaction {
  final String id;
  final double amount;
  final TransactionType type;
  final PaymentSource source;
  final String sender; // bank/UPI sender name
  final String? merchant; // merchant name if available
  final String? accountLast4;
  final DateTime date;
  final String rawMessage;
  final String? referenceId;
  final double? balance; // available balance after txn
  final String? accountId; // Link to Account
  final bool isUserCorrected; // User manually corrected this transaction
  final bool isSalary; // Marked as salary by user

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
    this.accountId,
    this.isUserCorrected = false,
    this.isSalary = false,
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

  Transaction copyWith({
    String? id,
    double? amount,
    TransactionType? type,
    PaymentSource? source,
    String? sender,
    String? merchant,
    String? accountLast4,
    DateTime? date,
    String? rawMessage,
    String? referenceId,
    double? balance,
    String? accountId,
    bool? isUserCorrected,
    bool? isSalary,
  }) {
    return Transaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      source: source ?? this.source,
      sender: sender ?? this.sender,
      merchant: merchant ?? this.merchant,
      accountLast4: accountLast4 ?? this.accountLast4,
      date: date ?? this.date,
      rawMessage: rawMessage ?? this.rawMessage,
      referenceId: referenceId ?? this.referenceId,
      balance: balance ?? this.balance,
      accountId: accountId ?? this.accountId,
      isUserCorrected: isUserCorrected ?? this.isUserCorrected,
      isSalary: isSalary ?? this.isSalary,
    );
  }
}
