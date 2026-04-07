// lib/models/standard_category.dart

import 'package:flutter/material.dart';

class StandardCategoryGroup {
  final String title;
  final String subtitle;
  final List<String> categoryIds;

  const StandardCategoryGroup({
    required this.title,
    required this.subtitle,
    required this.categoryIds,
  });
}

/// A standard category that can be dynamically managed by the user.
class StandardCategory {
  final String id;
  final String name;
  final String displayName;
  final String emoji;
  final int colorValue;
  final bool isDefault;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;

  StandardCategory({
    required this.id,
    required this.name,
    required this.displayName,
    required this.emoji,
    required this.colorValue,
    this.isDefault = false,
    this.isActive = true,
    required this.sortOrder,
    required this.createdAt,
  });

  Color get color => Color(colorValue);

  static const Map<String, String> legacyIdRemap = {
    'travel_transport': 'travel_fuel',
    'health_medical': 'health',
    'salary_income': 'salary',
    'investment': 'long_term_investments',
  };

  static const Set<String> newlyAddedDefaultIds = {
    'chitti_commitments',
    'insurance',
    'family_support',
    'goal_based_savings',
    'emergency_fund',
  };

  static List<StandardCategoryGroup> get defaultGroups => const [
        StandardCategoryGroup(
          title: 'Fixed Expenses',
          subtitle: 'Non-negotiable',
          categoryIds: [
            'rent_housing',
            'emi_loans',
            'chitti_commitments',
            'insurance',
            'family_support',
          ],
        ),
        StandardCategoryGroup(
          title: 'Variable Expenses',
          subtitle: 'Control zone',
          categoryIds: [
            'food_dining',
            'travel_fuel',
            'shopping',
            'entertainment',
            'bills_utilities',
            'health',
          ],
        ),
        StandardCategoryGroup(
          title: 'Wealth & Future',
          subtitle: 'Most important',
          categoryIds: [
            'long_term_investments',
            'goal_based_savings',
            'emergency_fund',
          ],
        ),
        StandardCategoryGroup(
          title: 'Income & Adjustments',
          subtitle: 'Keep as is',
          categoryIds: [
            'salary',
            'cashback',
            'transfer',
          ],
        ),
        StandardCategoryGroup(
          title: 'Optional',
          subtitle: 'Advanced but useful',
          categoryIds: [
            'education',
            'other',
            'uncategorized',
          ],
        ),
      ];

  static List<StandardCategory> get defaultCategories {
    final now = DateTime.now();
    return [
      StandardCategory(
        id: 'rent_housing',
        name: 'rentHousing',
        displayName: 'Rent & Housing',
        emoji: '🏠',
        colorValue: Colors.brown.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 0,
        createdAt: now,
      ),
      StandardCategory(
        id: 'emi_loans',
        name: 'emiLoans',
        displayName: 'EMIs & Loans',
        emoji: '💳',
        colorValue: Colors.red.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 1,
        createdAt: now,
      ),
      StandardCategory(
        id: 'chitti_commitments',
        name: 'chittiCommitments',
        displayName: 'Chitti / Commitments',
        emoji: '🏦',
        colorValue: Colors.indigo.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 2,
        createdAt: now,
      ),
      StandardCategory(
        id: 'insurance',
        name: 'insurance',
        displayName: 'Insurance',
        emoji: '🛡',
        colorValue: Colors.lightBlue.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 3,
        createdAt: now,
      ),
      StandardCategory(
        id: 'family_support',
        name: 'familySupport',
        displayName: 'Family Support',
        emoji: '👨‍👩‍👦',
        colorValue: Colors.deepOrange.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 4,
        createdAt: now,
      ),
      StandardCategory(
        id: 'food_dining',
        name: 'foodDining',
        displayName: 'Food & Dining',
        emoji: '🍕',
        colorValue: Colors.orange.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 5,
        createdAt: now,
      ),
      StandardCategory(
        id: 'travel_fuel',
        name: 'travelFuel',
        displayName: 'Travel & Fuel',
        emoji: '🚗',
        colorValue: Colors.blue.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 6,
        createdAt: now,
      ),
      StandardCategory(
        id: 'shopping',
        name: 'shopping',
        displayName: 'Shopping',
        emoji: '🛍',
        colorValue: Colors.purple.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 7,
        createdAt: now,
      ),
      StandardCategory(
        id: 'entertainment',
        name: 'entertainment',
        displayName: 'Entertainment',
        emoji: '🎬',
        colorValue: Colors.pink.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 8,
        createdAt: now,
      ),
      StandardCategory(
        id: 'bills_utilities',
        name: 'billsUtilities',
        displayName: 'Bills & Utilities',
        emoji: '💡',
        colorValue: Colors.amber.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 9,
        createdAt: now,
      ),
      StandardCategory(
        id: 'health',
        name: 'health',
        displayName: 'Health',
        emoji: '🏥',
        colorValue: Colors.green.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 10,
        createdAt: now,
      ),
      StandardCategory(
        id: 'long_term_investments',
        name: 'longTermInvestments',
        displayName: 'Long-Term Investments',
        emoji: '📈',
        colorValue: Colors.teal.shade700.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 11,
        createdAt: now,
      ),
      StandardCategory(
        id: 'goal_based_savings',
        name: 'goalBasedSavings',
        displayName: 'Goal-Based Savings',
        emoji: '🎯',
        colorValue: Colors.orange.shade700.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 12,
        createdAt: now,
      ),
      StandardCategory(
        id: 'emergency_fund',
        name: 'emergencyFund',
        displayName: 'Emergency Fund',
        emoji: '💰',
        colorValue: Colors.red.shade700.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 13,
        createdAt: now,
      ),
      StandardCategory(
        id: 'salary',
        name: 'salary',
        displayName: 'Salary',
        emoji: '💰',
        colorValue: Colors.green.shade700.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 14,
        createdAt: now,
      ),
      StandardCategory(
        id: 'cashback',
        name: 'cashback',
        displayName: 'Cashback',
        emoji: '🎁',
        colorValue: Colors.teal.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 15,
        createdAt: now,
      ),
      StandardCategory(
        id: 'transfer',
        name: 'transfer',
        displayName: 'Transfer',
        emoji: '🔄',
        colorValue: Colors.grey.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 16,
        createdAt: now,
      ),
      StandardCategory(
        id: 'education',
        name: 'education',
        displayName: 'Education',
        emoji: '📚',
        colorValue: Colors.deepPurple.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 17,
        createdAt: now,
      ),
      StandardCategory(
        id: 'other',
        name: 'other',
        displayName: 'Misc / Other',
        emoji: '📌',
        colorValue: Colors.blueGrey.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 18,
        createdAt: now,
      ),
      StandardCategory(
        id: 'uncategorized',
        name: 'uncategorized',
        displayName: 'Uncategorized',
        emoji: '❓',
        colorValue: Colors.grey.shade500.toARGB32(),
        isDefault: true,
        isActive: true,
        sortOrder: 19,
        createdAt: now,
      ),
    ];
  }

  static StandardCategory? getByName(String name) {
    try {
      return defaultCategories.firstWhere((cat) => cat.name == name);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'display_name': displayName,
        'emoji': emoji,
        'color_value': colorValue,
        'is_default': isDefault ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory StandardCategory.fromMap(Map<String, dynamic> map) =>
      StandardCategory(
        id: map['id'] as String,
        name: map['name'] as String,
        displayName: map['display_name'] as String? ?? map['name'] as String,
        emoji: map['emoji'] as String? ?? '🏷️',
        colorValue: map['color_value'] as int? ?? Colors.teal.toARGB32(),
        isDefault: (map['is_default'] as int? ?? 0) == 1,
        isActive: (map['is_active'] as int? ?? 1) == 1,
        sortOrder: map['sort_order'] as int? ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  StandardCategory copyWith({
    String? name,
    String? displayName,
    String? emoji,
    int? colorValue,
    bool? isActive,
    int? sortOrder,
  }) =>
      StandardCategory(
        id: id,
        name: name ?? this.name,
        displayName: displayName ?? this.displayName,
        emoji: emoji ?? this.emoji,
        colorValue: colorValue ?? this.colorValue,
        isDefault: isDefault,
        isActive: isActive ?? this.isActive,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StandardCategory &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
