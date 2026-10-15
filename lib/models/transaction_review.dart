import '../utils/money.dart';
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
    this.categoryId,
    this.categorySource,
    this.tag,
    this.isIgnored = false,
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
  final String? categoryId;
  final String? categorySource;
  final String? tag;
  final bool isIgnored;
  final DateTime createdAt;

  TransactionReview copyWith({
    String? merchant,
    String? categoryId,
    String? categorySource,
    String? tag,
    bool clearTag = false,
    bool clearCategory = false,
    bool? isIgnored,
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
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categorySource:
          categorySource ?? (clearCategory ? null : this.categorySource),
      tag: clearTag ? null : (tag ?? this.tag),
      isIgnored: isIgnored ?? this.isIgnored,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': Money.toPaise(amount),
      'source': source.name,
      'sender': sender,
      'merchant': merchant,
      'account_last4': accountLast4,
      'date': date.millisecondsSinceEpoch,
      'raw_message': rawMessage,
      'reference_id': referenceId,
      'balance': balance == null ? null : Money.toPaise(balance!),
      'category_id': categoryId,
      'category_source': categorySource,
      'tag': tag,
      'is_ignored': isIgnored ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory TransactionReview.fromMap(Map<String, dynamic> map) {
    return TransactionReview(
      id: map['id'] as String,
      amount: Money.fromPaise(map['amount']!),
      source: PaymentSource.values.firstWhere(
        (source) => source.name == map['source'],
      ),
      sender: map['sender'] as String,
      merchant: map['merchant'] as String?,
      accountLast4: map['account_last4'] as String?,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      rawMessage: map['raw_message'] as String,
      referenceId: map['reference_id'] as String?,
      balance: map['balance'] == null ? null : Money.fromPaise(map['balance']!),
      categoryId: map['category_id'] as String?,
      categorySource: map['category_source'] as String?,
      tag: map['tag'] as String?,
      isIgnored: (map['is_ignored'] as int?) == 1,
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
    this.categoryId,
    this.tag,
    this.isEnabled = true,
  });

  final String id;
  final String matchText;
  final String merchant;
  final String? categoryId;
  final String? tag;
  final DateTime createdAt;
  final bool isEnabled;

  MerchantRule copyWith({bool? isEnabled}) => MerchantRule(
    id: id,
    matchText: matchText,
    merchant: merchant,
    categoryId: categoryId,
    tag: tag,
    createdAt: createdAt,
    isEnabled: isEnabled ?? this.isEnabled,
  );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'match_text': matchText,
      'merchant': merchant,
      'category_id': categoryId,
      'tag': tag,
      'created_at': createdAt.millisecondsSinceEpoch,
      'is_enabled': isEnabled ? 1 : 0,
    };
  }

  factory MerchantRule.fromMap(Map<String, dynamic> map) {
    return MerchantRule(
      id: map['id'] as String,
      matchText: map['match_text'] as String,
      merchant: map['merchant'] as String,
      categoryId: map['category_id'] as String?,
      tag: map['tag'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      isEnabled: map['is_enabled'] == 1,
    );
  }
}
