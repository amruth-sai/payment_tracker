// lib/services/budget_service.dart

import 'dart:math';
import '../models/budget.dart';
import '../models/transaction.dart';
import 'local_storage_service.dart';

/// Manages budgets and generates AI-powered budget suggestions.
class BudgetService {
  /// Suggest budgets based on spending patterns and income.
  static Map<TransactionCategory, double> suggestBudgets({
    required List<Transaction> transactions,
    required double monthlyIncome,
  }) {
    // Calculate average monthly spending per category
    final categoryMonthly = _getMonthlyAverages(transactions);
    final suggestions = <TransactionCategory, double>{};

    // Apply 50/30/20 rule as baseline:
    // 50% needs (rent, bills, food, health, EMI)
    // 30% wants (shopping, entertainment, travel)
    // 20% savings/investment
    final needs = [
      TransactionCategory.rentHousing,
      TransactionCategory.billsUtilities,
      TransactionCategory.foodDining,
      TransactionCategory.healthMedical,
      TransactionCategory.emiLoans,
    ];
    final wants = [
      TransactionCategory.shopping,
      TransactionCategory.entertainment,
      TransactionCategory.travelTransport,
      TransactionCategory.education,
    ];

    final needsBudget = monthlyIncome * 0.50;
    final wantsBudget = monthlyIncome * 0.30;

    // Distribute needs budget proportionally based on actual spending
    final totalNeedsSpent = needs.fold(
        0.0, (sum, cat) => sum + (categoryMonthly[cat] ?? 0));
    for (final cat in needs) {
      final actual = categoryMonthly[cat] ?? 0;
      if (actual > 0) {
        final proportion =
            totalNeedsSpent > 0 ? actual / totalNeedsSpent : 1.0 / needs.length;
        final suggested = needsBudget * proportion;
        // Set 20% above actual or proportional, whichever is reasonable
        suggestions[cat] = max(suggested, actual * 1.1);
      } else {
        suggestions[cat] = needsBudget / needs.length;
      }
    }

    // Distribute wants budget
    final totalWantsSpent = wants.fold(
        0.0, (sum, cat) => sum + (categoryMonthly[cat] ?? 0));
    for (final cat in wants) {
      final actual = categoryMonthly[cat] ?? 0;
      if (actual > 0) {
        final proportion =
            totalWantsSpent > 0 ? actual / totalWantsSpent : 1.0 / wants.length;
        final suggested = wantsBudget * proportion;
        suggestions[cat] = max(suggested, actual * 0.9); // Slightly tighter
      } else {
        suggestions[cat] = wantsBudget / wants.length;
      }
    }

    // Round to nearest 500
    return suggestions.map(
      (cat, amount) => MapEntry(cat, (amount / 500).round() * 500.0),
    );
  }

  /// Get monthly average spending per category.
  static Map<TransactionCategory, double> _getMonthlyAverages(
      List<Transaction> transactions) {
    final debits = transactions.where((t) => t.isDebit).toList();
    if (debits.isEmpty) return {};

    // Group by month
    final monthlyTotals = <String, Map<TransactionCategory, double>>{};
    for (final tx in debits) {
      final monthKey = '${tx.date.year}-${tx.date.month}';
      final cat = tx.category ?? TransactionCategory.uncategorized;
      monthlyTotals.putIfAbsent(monthKey, () => {});
      monthlyTotals[monthKey]![cat] =
          (monthlyTotals[monthKey]![cat] ?? 0) + tx.amount;
    }

    if (monthlyTotals.isEmpty) return {};

    // Average across months
    final numMonths = monthlyTotals.length;
    final averages = <TransactionCategory, double>{};
    for (final monthly in monthlyTotals.values) {
      for (final entry in monthly.entries) {
        averages[entry.key] = (averages[entry.key] ?? 0) + entry.value;
      }
    }
    return averages.map((k, v) => MapEntry(k, v / numMonths));
  }

  /// Check budget usage for current month.
  static Future<Map<TransactionCategory, BudgetStatus>> checkBudgets() async {
    final budgets = await LocalStorageService.getAllBudgets();
    if (budgets.isEmpty) return {};

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final transactions =
        await LocalStorageService.getTransactionsByDateRange(
            monthStart, now);

    // Sum spending per category this month
    final categorySpent = <TransactionCategory, double>{};
    for (final tx in transactions.where((t) => t.isDebit)) {
      final cat = tx.category ?? TransactionCategory.uncategorized;
      categorySpent[cat] = (categorySpent[cat] ?? 0) + tx.amount;
    }

    final result = <TransactionCategory, BudgetStatus>{};
    for (final budget in budgets) {
      final spent = categorySpent[budget.category] ?? 0;
      final percentage = budget.monthlyLimit > 0
          ? (spent / budget.monthlyLimit * 100)
          : 0.0;
      result[budget.category] = BudgetStatus(
        budget: budget,
        spent: spent,
        percentage: percentage,
      );
    }

    return result;
  }

  /// Get categories that are over 80% of budget.
  static Future<List<BudgetStatus>> getOverBudgetAlerts() async {
    final statuses = await checkBudgets();
    return statuses.values
        .where((s) => s.percentage >= 80)
        .toList()
      ..sort((a, b) => b.percentage.compareTo(a.percentage));
  }
}

class BudgetStatus {
  final Budget budget;
  final double spent;
  final double percentage;

  BudgetStatus({
    required this.budget,
    required this.spent,
    required this.percentage,
  });

  bool get isOverBudget => percentage >= 100;
  bool get isWarning => percentage >= 80 && percentage < 100;
  bool get isHealthy => percentage < 80;

  double get remaining =>
      (budget.monthlyLimit - spent).clamp(0, budget.monthlyLimit);
}
