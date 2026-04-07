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
        return 'Travel & Fuel';
      case shopping:
        return 'Shopping';
      case rentHousing:
        return 'Rent & Housing';
      case emiLoans:
        return 'EMIs & Loans';
      case entertainment:
        return 'Entertainment';
      case billsUtilities:
        return 'Bills & Utilities';
      case healthMedical:
        return 'Health';
      case education:
        return 'Education';
      case salaryIncome:
        return 'Salary';
      case transfer:
        return 'Transfer';
      case cashback:
        return 'Cashback';
      case investment:
        return 'Long-Term Investments';
      case other:
        return 'Misc / Other';
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

  String get standardCategoryId {
    switch (this) {
      case foodDining:
        return 'food_dining';
      case travelTransport:
        return 'travel_fuel';
      case shopping:
        return 'shopping';
      case rentHousing:
        return 'rent_housing';
      case emiLoans:
        return 'emi_loans';
      case entertainment:
        return 'entertainment';
      case billsUtilities:
        return 'bills_utilities';
      case healthMedical:
        return 'health';
      case education:
        return 'education';
      case salaryIncome:
        return 'salary';
      case transfer:
        return 'transfer';
      case cashback:
        return 'cashback';
      case investment:
        return 'long_term_investments';
      case other:
        return 'other';
      case uncategorized:
        return 'uncategorized';
    }
  }

  static TransactionCategory? fromStandardCategoryId(String? id) {
    if (id == null || id.isEmpty) return null;

    for (final category in TransactionCategory.values) {
      if (category.standardCategoryId == id) {
        return category;
      }
    }

    return null;
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
  final TransactionCategory?
      category; // Auto or manually tagged category (deprecated - for backward compatibility)
  final String? standardCategoryId; // New: References standard_categories table
  final String? note; // User-added personal note
  final String?
      tag; // Feature 1: User-defined label (e.g. "reimbursable", "split")
  final bool isIgnored; // Feature 2: If true, excluded from all summaries
  final String?
      customCategoryId; // Feature 3: Links to a user-created custom category

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
    this.category, // Kept for backward compatibility
    this.standardCategoryId,
    this.note,
    this.tag,
    this.isIgnored = false,
    this.customCategoryId,
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

  /// Get the effective category (prioritizes standardCategoryId over deprecated category enum)
  String? get effectiveCategoryId => effectiveStandardCategoryId;

  /// Get the effective standard category ID, falling back to the legacy enum.
  String? get effectiveStandardCategoryId =>
      standardCategoryId ?? category?.standardCategoryId;

  /// Get the closest legacy enum representation when possible.
  TransactionCategory? get effectiveLegacyCategory =>
      category ??
      TransactionCategory.fromStandardCategoryId(standardCategoryId);

  /// Check if transaction has any category assigned
  bool get hasCategory =>
      effectiveStandardCategoryId != null || customCategoryId != null;

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
    String? standardCategoryId,
    String? note,
    String? tag,
    bool? isIgnored,
    String? customCategoryId,
    // Transfer fields
    String? transferGroupId,
    String? transferPartnerId,
    bool? isTransferSource,
    bool? isTransferDestination,
    // Sentinels to explicitly clear nullable fields
    bool clearCategory = false,
    bool clearNote = false,
    bool clearTag = false,
    bool clearCustomCategory = false,
    bool clearStandardCategory = false,
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
      category: clearCategory ? null : (category ?? this.category),
      standardCategoryId: clearStandardCategory
          ? null
          : (standardCategoryId ?? this.standardCategoryId),
      note: clearNote ? null : (note ?? this.note),
      tag: clearTag ? null : (tag ?? this.tag),
      isIgnored: isIgnored ?? this.isIgnored,
      customCategoryId: clearCustomCategory
          ? null
          : (customCategoryId ?? this.customCategoryId),
      transferGroupId:
          clearTransferGroup ? null : (transferGroupId ?? this.transferGroupId),
      transferPartnerId: clearTransferPartner
          ? null
          : (transferPartnerId ?? this.transferPartnerId),
      isTransferSource: isTransferSource ?? this.isTransferSource,
      isTransferDestination:
          isTransferDestination ?? this.isTransferDestination,
    );
  }
}
