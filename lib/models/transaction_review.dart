import 'transaction.dart';

/// A payment-like SMS whose direction could not be determined from local rules.
/// It remains outside summaries until the user confirms it as debit or credit.
class TransactionReview {
  const TransactionReview({
    required this.id,
    required this.amount,
    required this.source,
    required this.sender,
    required this.date,
    required this.rawMessage,
    required this.createdAt,
    this.merchant,
    this.accountLast4,
    this.referenceId,
    this.balance,
    this.standardCategoryId,
  });

  final String id;
  final double amount;
  final PaymentSource source;
  final String sender;
  final String? merchant;
  final String? accountLast4;
  final DateTime date;
  final String rawMessage;
  final String? referenceId;
  final double? balance;
  final String? standardCategoryId;
  final DateTime createdAt;

  TransactionReview copyWith({
    String? merchant,
    String? standardCategoryId,
  }) {
    return TransactionReview(
      id: id,
      amount: amount,
      source: source,
      sender: sender,
      merchant: merchant ?? this.merchant,
      accountLast4: accountLast4,
      date: date,
      rawMessage: rawMessage,
      referenceId: referenceId,
      balance: balance,
      standardCategoryId: standardCategoryId ?? this.standardCategoryId,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'source': source.name,
      'sender': sender,
      'merchant': merchant,
      'account_last4': accountLast4,
      'date': date.millisecondsSinceEpoch,
      'raw_message': rawMessage,
      'reference_id': referenceId,
      'balance': balance,
      'standard_category_id': standardCategoryId,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory TransactionReview.fromMap(Map<String, dynamic> map) {
    return TransactionReview(
      id: map['id'] as String,
      amount: (map['amount'] as num).toDouble(),
      source: PaymentSource.values.firstWhere(
        (source) => source.name == map['source'],
        orElse: () => PaymentSource.bank,
      ),
      sender: map['sender'] as String,
      merchant: map['merchant'] as String?,
      accountLast4: map['account_last4'] as String?,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      rawMessage: map['raw_message'] as String,
      referenceId: map['reference_id'] as String?,
      balance: (map['balance'] as num?)?.toDouble(),
      standardCategoryId: map['standard_category_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

/// A user-defined, local rule for normalizing a merchant in matching SMS text.
class MerchantRule {
  const MerchantRule({
    required this.id,
    required this.matchText,
    required this.merchant,
    required this.createdAt,
    this.standardCategoryId,
  });

  final String id;
  final String matchText;
  final String merchant;
  final String? standardCategoryId;
  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'match_text': matchText,
      'merchant': merchant,
      'standard_category_id': standardCategoryId,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory MerchantRule.fromMap(Map<String, dynamic> map) {
    return MerchantRule(
      id: map['id'] as String,
      matchText: map['match_text'] as String,
      merchant: map['merchant'] as String,
      standardCategoryId: map['standard_category_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}
