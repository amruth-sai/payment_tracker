// lib/models/category_preferences.dart

import 'standard_category.dart';

/// Manages which standard categories are visible/enabled for the user
class CategoryPreferences {
  final Set<String> enabledCategoryIds;

  CategoryPreferences({
    required this.enabledCategoryIds,
  });

  /// Default: all categories enabled
  factory CategoryPreferences.defaultPreferences() {
    return CategoryPreferences(
      enabledCategoryIds: Set.from(StandardCategory.defaultCategories.map((c) => c.id)),
    );
  }

  bool isEnabled(String categoryId) {
    return enabledCategoryIds.contains(categoryId);
  }

  /// Get enabled categories filtered from a list of all categories
  List<StandardCategory> getEnabledCategories(List<StandardCategory> allCategories) {
    return allCategories.where((cat) => enabledCategoryIds.contains(cat.id)).toList();
  }

  Map<String, dynamic> toMap() => {
        'enabled_category_ids': enabledCategoryIds.toList(),
      };

  factory CategoryPreferences.fromMap(Map<String, dynamic> map) {
    final enabledIds = (map['enabled_category_ids'] as List<dynamic>?)
            ?.cast<String>()
            .toSet() ??
        {};

    // If no preferences are saved or the set is empty, return default preferences
    if (enabledIds.isEmpty) {
      return CategoryPreferences.defaultPreferences();
    }

    return CategoryPreferences(enabledCategoryIds: enabledIds);
  }

  CategoryPreferences copyWith({
    Set<String>? enabledCategoryIds,
  }) {
    return CategoryPreferences(
      enabledCategoryIds: enabledCategoryIds ?? this.enabledCategoryIds,
    );
  }

  /// Enable a category
  CategoryPreferences enableCategory(String categoryId) {
    return copyWith(
      enabledCategoryIds: Set.from(enabledCategoryIds)..add(categoryId),
    );
  }

  /// Disable a category
  CategoryPreferences disableCategory(String categoryId) {
    return copyWith(
      enabledCategoryIds: Set.from(enabledCategoryIds)..remove(categoryId),
    );
  }

  /// Toggle category enabled status
  CategoryPreferences toggleCategory(String categoryId) {
    if (isEnabled(categoryId)) {
      return disableCategory(categoryId);
    } else {
      return enableCategory(categoryId);
    }
  }
}
