// lib/services/budget_service.dart

import '../models/budget.dart';
import '../models/custom_category.dart';
import '../models/standard_category.dart';
import '../models/transaction.dart';
import 'local_storage_service.dart';

/// Manages budgets and generates spending-based budget suggestions.
class BudgetService {
  static const String customCategoryPrefix = Budget.customCategoryPrefix;
  static const Set<String> _nonBudgetableCategoryIds = {
    'salary',
    'cashback',
    'transfer',
    'uncategorized',
  };

  static Future<Map<String, StandardCategory>> loadBudgetCategories() async {
    final categories = await LocalStorageService.getAllStandardCategories();
    final customCategories = await LocalStorageService.getAllCustomCategories();
    return {
      for (final category in StandardCategory.defaultCategories)
        category.id: category,
      for (final category in categories) category.id: category,
      for (var index = 0; index < customCategories.length; index++)
        '$customCategoryPrefix${customCategories[index].id}':
            _customBudgetCategory(customCategories[index], index),
    };
  }

  static StandardCategory _customBudgetCategory(
      CustomCategory category, int index) {
    return StandardCategory(
      id: '$customCategoryPrefix${category.id}',
      name: category.name,
      displayName: 'My: ${category.name}',
      emoji: category.emoji,
      colorValue: category.colorValue,
      sortOrder: 10000 + index,
      createdAt: category.createdAt,
    );
  }

  /// A My Category takes precedence over the underlying standard category.
  static String categoryIdForTransaction(Transaction transaction) {
    final customId = transaction.customCategoryId;
    if (customId != null && customId.isNotEmpty) {
      return '$customCategoryPrefix$customId';
    }
    return transaction.effectiveStandardCategoryId ?? 'uncategorized';
  }

  static bool isBudgetExpense(Transaction transaction) {
    if (!transaction.isDebit ||
        transaction.isIgnored ||
        transaction.isPartOfTransfer ||
        transaction.isSalary) {
      return false;
    }
    const excludedStandardCategories = {'salary', 'cashback', 'transfer'};
    return !excludedStandardCategories
        .contains(transaction.effectiveStandardCategoryId);
  }

  /// Spending that has no budget for its effective category.
  static List<Transaction> outsideBudgetTransactions({
    required Iterable<Transaction> transactions,
    required Set<String> budgetCategoryIds,
    DateTime? start,
    DateTime? end,
  }) {
    return transactions
        .where(isBudgetExpense)
        .where((tx) => start == null || !tx.date.isBefore(start))
        .where((tx) => end == null || !tx.date.isAfter(end))
        .where(
            (tx) => !budgetCategoryIds.contains(categoryIdForTransaction(tx)))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  static Future<Map<String, double>> suggestBudgets({
    required List<Transaction> transactions,
    required double monthlyIncome,
  }) async {
    final categoryMonthly = _getMonthlyAverages(transactions);
    final suggestions = <String, double>{};

    for (final entry in categoryMonthly.entries) {
      if (_nonBudgetableCategoryIds.contains(entry.key) || entry.value <= 0) {
        continue;
      }

      final buffered = entry.value * 1.1;
      final capped =
          monthlyIncome > 0 ? buffered.clamp(500.0, monthlyIncome) : buffered;
      suggestions[entry.key] = ((capped / 500).round() * 500).toDouble();
    }

    return suggestions;
  }

  static Map<String, double> _getMonthlyAverages(
      List<Transaction> transactions) {
    final debits = transactions.where(isBudgetExpense).toList();
    if (debits.isEmpty) return {};

    final monthlyTotals = <String, Map<String, double>>{};
    for (final tx in debits) {
      final monthKey = '${tx.date.year}-${tx.date.month}';
      final categoryId = categoryIdForTransaction(tx);
      monthlyTotals.putIfAbsent(monthKey, () => {});
      monthlyTotals[monthKey]![categoryId] =
          (monthlyTotals[monthKey]![categoryId] ?? 0) + tx.amount;
    }

    if (monthlyTotals.isEmpty) return {};

    final averages = <String, double>{};
    final numMonths = monthlyTotals.length;
    for (final monthly in monthlyTotals.values) {
      for (final entry in monthly.entries) {
        averages[entry.key] = (averages[entry.key] ?? 0) + entry.value;
      }
    }

    return averages.map((key, value) => MapEntry(key, value / numMonths));
  }

  static Future<List<BudgetStatus>> checkBudgets({
    List<Transaction>? transactions,
    DateTime? start,
    DateTime? end,
  }) async {
    final budgets = await LocalStorageService.getAllBudgets();
    if (budgets.isEmpty) return [];

    final effectiveEnd = end ?? (start != null ? DateTime.now() : null);
    final baseTransactions = transactions ??
        await _loadTransactionsForRange(start: start, end: effectiveEnd);
    final currentTransactions = _filterToRange(
      baseTransactions,
      start: start,
      end: effectiveEnd,
    );
    final categoriesById = await loadBudgetCategories();

    final categorySpent = <String, double>{};
    for (final tx in currentTransactions.where(isBudgetExpense)) {
      final categoryId = categoryIdForTransaction(tx);
      categorySpent[categoryId] = (categorySpent[categoryId] ?? 0) + tx.amount;
    }

    final result = budgets
        .map((budget) {
          final category = categoriesById[budget.standardCategoryId];
          if (category == null) return null;

          final spent = categorySpent[budget.standardCategoryId] ?? 0;
          final percentage = budget.monthlyLimit > 0
              ? (spent / budget.monthlyLimit * 100)
              : 0.0;
          return BudgetStatus(
            budget: budget,
            standardCategory: category,
            spent: spent,
            percentage: percentage,
          );
        })
        .whereType<BudgetStatus>()
        .toList()
      ..sort((a, b) => b.percentage.compareTo(a.percentage));

    return result;
  }

  static Future<List<Transaction>> _loadTransactionsForRange({
    DateTime? start,
    DateTime? end,
  }) async {
    if (start == null && end == null) {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      return LocalStorageService.getTrackedTransactions(
        start: monthStart,
        end: now,
      );
    }

    final effectiveEnd = end ?? DateTime.now();
    return LocalStorageService.getTrackedTransactions(
      start: start,
      end: effectiveEnd,
    );
  }

  static List<Transaction> _filterToRange(
    List<Transaction> transactions, {
    DateTime? start,
    DateTime? end,
  }) {
    if (start == null && end == null) {
      return _filterToCurrentMonth(transactions);
    }

    final effectiveEnd = end ?? DateTime.now();
    return transactions
        .where((tx) => start == null || !tx.date.isBefore(start))
        .where((tx) => !tx.date.isAfter(effectiveEnd))
        .toList();
  }

  static List<Transaction> _filterToCurrentMonth(
      List<Transaction> transactions) {
    final now = DateTime.now();
    return transactions
        .where((tx) => tx.date.year == now.year && tx.date.month == now.month)
        .toList();
  }

  static Future<List<BudgetStatus>> getOverBudgetAlerts({
    List<Transaction>? transactions,
    DateTime? start,
    DateTime? end,
  }) async {
    final statuses = await checkBudgets(
      transactions: transactions,
      start: start,
      end: end,
    );
    return statuses.where((status) => status.percentage >= 80).toList()
      ..sort((a, b) => b.percentage.compareTo(a.percentage));
  }

  static bool isBudgetableCategory(StandardCategory category) {
    return !_nonBudgetableCategoryIds.contains(category.id);
  }
}

class BudgetStatus {
  final Budget budget;
  final StandardCategory standardCategory;
  final double spent;
  final double percentage;

  BudgetStatus({
    required this.budget,
    required this.standardCategory,
    required this.spent,
    required this.percentage,
  });

  bool get isOverBudget => percentage >= 100;
  bool get isWarning => percentage >= 80 && percentage < 100;
  bool get isHealthy => percentage < 80;

  double get remaining =>
      (budget.monthlyLimit - spent).clamp(0, budget.monthlyLimit);
}
