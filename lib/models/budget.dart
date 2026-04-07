// lib/models/budget.dart

import 'standard_category.dart';
import 'transaction.dart';

class Budget {
  final String id;
  final String standardCategoryId;
  final double monthlyLimit;
  final bool isAiSuggested;
  final DateTime createdAt;

  Budget({
    required this.id,
    required this.standardCategoryId,
    required this.monthlyLimit,
    this.isAiSuggested = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static String _normalizeStoredCategory(dynamic storedValue) {
    final raw = storedValue as String?;
    if (raw == null || raw.isEmpty) {
      return TransactionCategory.other.standardCategoryId;
    }

    final legacyCategory =
        TransactionCategory.values.cast<TransactionCategory?>().firstWhere(
              (category) => category?.name == raw,
              orElse: () => null,
            );
    if (legacyCategory != null) {
      return legacyCategory.standardCategoryId;
    }

    return StandardCategory.legacyIdRemap[raw] ?? raw;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': standardCategoryId,
      'monthly_limit': monthlyLimit,
      'is_ai_suggested': isAiSuggested ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'] as String,
      standardCategoryId: _normalizeStoredCategory(map['category']),
      monthlyLimit: (map['monthly_limit'] as num).toDouble(),
      isAiSuggested: (map['is_ai_suggested'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Budget copyWith({
    String? id,
    String? standardCategoryId,
    double? monthlyLimit,
    bool? isAiSuggested,
    DateTime? createdAt,
  }) {
    return Budget(
      id: id ?? this.id,
      standardCategoryId: standardCategoryId ?? this.standardCategoryId,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      isAiSuggested: isAiSuggested ?? this.isAiSuggested,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
