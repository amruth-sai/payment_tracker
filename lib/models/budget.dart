import '../utils/money.dart';

class Budget {
  Budget({
    required this.id,
    required this.categoryId,
    required this.monthlyLimit,
    DateTime? createdAt,
    this.isSuggested = false,
  }) : createdAt = createdAt ?? DateTime.now();
  final String id;
  final String categoryId;
  final double monthlyLimit;
  final bool isSuggested;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'category_id': categoryId,
    'monthly_limit': Money.toPaise(monthlyLimit),
    'is_suggested': isSuggested ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Budget.fromMap(Map<String, dynamic> map) => Budget(
    id: map['id'] as String,
    categoryId: map['category_id'] as String,
    monthlyLimit: Money.fromPaise(map['monthly_limit']!),
    isSuggested: map['is_suggested'] == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );

  Budget copyWith({
    String? categoryId,
    double? monthlyLimit,
    bool? isSuggested,
  }) => Budget(
    id: id,
    categoryId: categoryId ?? this.categoryId,
    monthlyLimit: monthlyLimit ?? this.monthlyLimit,
    isSuggested: isSuggested ?? this.isSuggested,
    createdAt: createdAt,
  );
}
