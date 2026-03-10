// lib/models/budget.dart

import 'transaction.dart';

class Budget {
  final String id;
  final TransactionCategory category;
  final double monthlyLimit;
  final bool isAiSuggested;
  final DateTime createdAt;

  Budget({
    required this.id,
    required this.category,
    required this.monthlyLimit,
    this.isAiSuggested = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category.name,
      'monthly_limit': monthlyLimit,
      'is_ai_suggested': isAiSuggested ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'] as String,
      category: TransactionCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => TransactionCategory.other,
      ),
      monthlyLimit: (map['monthly_limit'] as num).toDouble(),
      isAiSuggested: (map['is_ai_suggested'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Budget copyWith({
    String? id,
    TransactionCategory? category,
    double? monthlyLimit,
    bool? isAiSuggested,
    DateTime? createdAt,
  }) {
    return Budget(
      id: id ?? this.id,
      category: category ?? this.category,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      isAiSuggested: isAiSuggested ?? this.isAiSuggested,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
