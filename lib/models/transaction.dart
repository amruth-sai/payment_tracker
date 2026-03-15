// lib/models/transaction.dart

enum TransactionType { credit, debit, unknown }

enum PaymentSource { upi, bank, card, wallet, unknown }

enum TransactionCategory {
  foodDining,
  travelTransport,
  shopping,
  rentHousing,
  emiLoans,
  entertainment,
  billsUtilities,
  healthMedical,
  education,
  salaryIncome,
  transfer,
  cashback,
  investment,
  other,
  uncategorized;

  String get displayName {
    switch (this) {
      case foodDining:
        return 'Food & Dining';
      case travelTransport:
        return 'Travel & Transport';
      case shopping:
        return 'Shopping';
      case rentHousing:
        return 'Rent & Housing';
      case emiLoans:
        return 'EMI & Loans';
      case entertainment:
        return 'Entertainment';
      case billsUtilities:
        return 'Bills & Utilities';
      case healthMedical:
        return 'Health & Medical';
      case education:
        return 'Education';
      case salaryIncome:
        return 'Salary & Income';
      case transfer:
        return 'Transfer';
      case cashback:
        return 'Cashback';
      case investment:
        return 'Investment';
      case other:
        return 'Other';
      case uncategorized:
        return 'Uncategorized';
    }
  }

  String get emoji {
    switch (this) {
      case foodDining:
        return '🍕';
      case travelTransport:
        return '🚗';
      case shopping:
        return '🛍️';
      case rentHousing:
        return '🏠';
      case emiLoans:
        return '💳';
      case entertainment:
        return '🎬';
      case billsUtilities:
        return '💡';
      case healthMedical:
        return '🏥';
      case education:
        return '📚';
      case salaryIncome:
        return '💰';
      case transfer:
        return '🔄';
      case cashback:
        return '🎁';
      case investment:
        return '📈';
      case other:
        return '📌';
      case uncategorized:
        return '❓';
    }
  }
}

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
  final TransactionCategory? category; // Auto or manually tagged category
  final String? note; // User-added personal note
  final String? tag; // Feature 1: User-defined label (e.g. "reimbursable", "split")
  final bool isIgnored; // Feature 2: If true, excluded from all summaries
  final String? customCategoryId; // Feature 3: Links to a user-created custom category

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
    this.category,
    this.note,
    this.tag,
    this.isIgnored = false,
    this.customCategoryId,
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
    TransactionCategory? category,
    String? note,
    String? tag,
    bool? isIgnored,
    String? customCategoryId,
    // Sentinels to explicitly clear nullable fields
    bool clearNote = false,
    bool clearTag = false,
    bool clearCustomCategory = false,
    bool clearAccountId = false,
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
      category: category ?? this.category,
      note: clearNote ? null : (note ?? this.note),
      tag: clearTag ? null : (tag ?? this.tag),
      isIgnored: isIgnored ?? this.isIgnored,
      customCategoryId: clearCustomCategory ? null : (customCategoryId ?? this.customCategoryId),
    );
  }
}
