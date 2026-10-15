import '../utils/money.dart';
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
  final String? categoryId;
  final String? categorySource; // merchant_rule or user
  final String? note; // User-added personal note
  final String?
  tag; // Feature 1: User-defined label (e.g. "reimbursable", "split")
  final bool isIgnored; // Feature 2: If true, excluded from all summaries

  // Transfer linking fields
  final String? transferGroupId; // Groups related transfer transactions
  final String? transferPartnerId; // Direct link to partner transaction ID
  final bool isTransferSource; // True if this is the debit side of a transfer
  final bool
  isTransferDestination; // True if this is the credit side of a transfer

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
    this.categoryId,
    this.categorySource,
    this.note,
    this.tag,
    this.isIgnored = false,
    // Transfer linking fields
    this.transferGroupId,
    this.transferPartnerId,
    this.isTransferSource = false,
    this.isTransferDestination = false,
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

  /// Check if this transaction is part of a transfer (either source or destination)
  bool get isPartOfTransfer => transferGroupId != null;

  /// Check if this transaction has a transfer partner
  bool get hasTransferPartner => transferPartnerId != null;

  /// Check if this is a complete transfer pair (has both group and partner)
  bool get isCompleteTransfer => isPartOfTransfer && hasTransferPartner;

  bool get hasCategory => categoryId != null;

  bool get isExpense => isDebit && !isIgnored && !isPartOfTransfer && !isSalary;
  bool get isIncome => isCredit && !isIgnored && !isPartOfTransfer;

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
    String? categoryId,
    String? categorySource,
    String? note,
    String? tag,
    bool? isIgnored,
    // Transfer fields
    String? transferGroupId,
    String? transferPartnerId,
    bool? isTransferSource,
    bool? isTransferDestination,
    // Sentinels to explicitly clear nullable fields
    bool clearNote = false,
    bool clearTag = false,
    bool clearCategory = false,
    bool clearAccountId = false,
    bool clearTransferGroup = false,
    bool clearTransferPartner = false,
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
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      isUserCorrected: isUserCorrected ?? this.isUserCorrected,
      isSalary: isSalary ?? this.isSalary,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categorySource:
          categorySource ?? (clearCategory ? null : this.categorySource),
      note: clearNote ? null : (note ?? this.note),
      tag: clearTag ? null : (tag ?? this.tag),
      isIgnored: isIgnored ?? this.isIgnored,
      transferGroupId: clearTransferGroup
          ? null
          : (transferGroupId ?? this.transferGroupId),
      transferPartnerId: clearTransferPartner
          ? null
          : (transferPartnerId ?? this.transferPartnerId),
      isTransferSource: isTransferSource ?? this.isTransferSource,
      isTransferDestination:
          isTransferDestination ?? this.isTransferDestination,
    );
  }
}

/// Sum money as integer paise, including report totals.
extension TransactionTotals on Iterable<Transaction> {
  double get totalAmount => Money.sum(map((tx) => tx.amount));
}
