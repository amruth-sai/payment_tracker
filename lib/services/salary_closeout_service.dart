import '../utils/money.dart';
import '../models/emi.dart';
import '../models/salary_cycle.dart';
import '../models/transaction.dart';
import 'emi_service.dart';

class SalaryCloseout {
  const SalaryCloseout({
    required this.cycle,
    required this.periodEnd,
    required this.income,
    required this.spending,
    required this.savings,
    required this.categoryChanges,
    required this.recurringPayments,
    required this.reimbursableTransactions,
    required this.firstWeekSpending,
    required this.lastWeekSpending,
    required this.lowestNetCashFlow,
    required this.lowestNetCashFlowDate,
  });

  final SalaryCycle cycle;
  final DateTime periodEnd;
  final double income;
  final double spending;
  final double savings;
  final List<CategorySpendChange> categoryChanges;
  final List<DetectedEMI> recurringPayments;
  final List<Transaction> reimbursableTransactions;
  final double firstWeekSpending;
  final double lastWeekSpending;
  final double lowestNetCashFlow;
  final DateTime lowestNetCashFlowDate;

  bool get isComplete => cycle.endDate != null;

  double get reimbursableAmount => reimbursableTransactions.totalAmount;
}

class CategorySpendChange {
  const CategorySpendChange({
    required this.categoryId,
    required this.currentAmount,
    required this.previousAmount,
  });

  final String categoryId;
  final double currentAmount;
  final double previousAmount;

  double get difference => currentAmount - previousAmount;
}

/// Calculates one salary-cycle summary from data already stored on-device.
class SalaryCloseoutService {
  static SalaryCloseout build({
    required SalaryCycle cycle,
    SalaryCycle? previousCycle,
    required List<Transaction> allTransactions,
  }) {
    final periodEnd = cycle.endDate ?? DateTime.now();
    final currentTransactions = cycle.transactions
        .where((tx) => _isRelevant(tx) && cycle.contains(tx.date))
        .toList();
    final previousTransactions =
        previousCycle?.transactions.where(_isRelevant).toList() ?? const [];
    final spendingTransactions = currentTransactions
        .where(_isSpending)
        .toList(growable: false);

    final income = currentTransactions
        .where((transaction) => transaction.isCredit)
        .totalAmount;
    final spending = spendingTransactions.totalAmount;
    final currentCategories = _categoryTotals(spendingTransactions);
    final previousCategories = _categoryTotals(
      previousTransactions.where(_isSpending),
    );

    final categoryChanges =
        {...currentCategories.keys, ...previousCategories.keys}
            .map((categoryId) {
              return CategorySpendChange(
                categoryId: categoryId,
                currentAmount: currentCategories[categoryId] ?? 0,
                previousAmount: previousCategories[categoryId] ?? 0,
              );
            })
            .where((change) => change.difference.abs() > 0.01)
            .toList()
          ..sort(
            (first, second) =>
                second.difference.abs().compareTo(first.difference.abs()),
          );

    final recurringPayments =
        EMIService.detectEMIs(
          allTransactions.where(_isRelevant).toList(),
        ).where((payment) {
          return payment.isActive &&
              payment.occurrences.any(
                (date) => _isInRange(date, cycle.startDate, periodEnd),
              );
        }).toList();

    final reimbursableTransactions = spendingTransactions
        .where(
          (transaction) =>
              transaction.tag?.trim().toLowerCase() == 'reimbursable',
        )
        .toList(growable: false);
    final timing = _cashFlowTiming(
      currentTransactions,
      cycle.startDate,
      periodEnd,
    );

    return SalaryCloseout(
      cycle: cycle,
      periodEnd: periodEnd,
      income: income,
      spending: spending,
      savings: Money.sum([income, -spending]),
      categoryChanges: categoryChanges,
      recurringPayments: recurringPayments,
      reimbursableTransactions: reimbursableTransactions,
      firstWeekSpending: _spendingInRange(
        spendingTransactions,
        cycle.startDate,
        _earlierOf(cycle.startDate.add(const Duration(days: 7)), periodEnd),
      ),
      lastWeekSpending: _spendingInRange(
        spendingTransactions,
        _laterOf(periodEnd.subtract(const Duration(days: 7)), cycle.startDate),
        periodEnd,
      ),
      lowestNetCashFlow: timing.$1,
      lowestNetCashFlowDate: timing.$2,
    );
  }

  static bool _isRelevant(Transaction transaction) {
    return !transaction.isIgnored && !transaction.isPartOfTransfer;
  }

  static bool _isSpending(Transaction transaction) => transaction.isExpense;

  static Map<String, double> _categoryTotals(
    Iterable<Transaction> transactions,
  ) {
    final totals = <String, double>{};
    for (final transaction in transactions) {
      final categoryId = transaction.categoryId ?? '';
      totals[categoryId] = Money.sum([
        totals[categoryId] ?? 0,
        transaction.amount,
      ]);
    }
    return totals;
  }

  static (double, DateTime) _cashFlowTiming(
    List<Transaction> transactions,
    DateTime start,
    DateTime end,
  ) {
    final ordered = [...transactions]
      ..sort((first, second) => first.date.compareTo(second.date));
    var runningTotal = 0.0;
    var lowestTotal = 0.0;
    var lowestDate = start;

    for (final transaction in ordered) {
      runningTotal += transaction.isCredit
          ? transaction.amount
          : -transaction.amount;
      if (runningTotal < lowestTotal) {
        lowestTotal = runningTotal;
        lowestDate = transaction.date;
      }
    }

    return (lowestTotal, lowestDate);
  }

  static double _spendingInRange(
    Iterable<Transaction> transactions,
    DateTime start,
    DateTime end,
  ) {
    return transactions
        .where((transaction) => _isInRange(transaction.date, start, end))
        .totalAmount;
  }

  static bool _isInRange(DateTime date, DateTime start, DateTime end) {
    return !date.isBefore(start) && date.isBefore(end);
  }

  static DateTime _earlierOf(DateTime first, DateTime second) {
    return first.isBefore(second) ? first : second;
  }

  static DateTime _laterOf(DateTime first, DateTime second) {
    return first.isAfter(second) ? first : second;
  }
}
