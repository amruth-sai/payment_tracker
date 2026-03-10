// lib/models/salary_cycle.dart

import 'transaction.dart';

class SalaryCycle {
  final String id;
  final DateTime startDate; // Salary credit date
  final DateTime? endDate; // Next salary date (null if current cycle)
  final double salaryAmount;
  final String salaryTransactionId;
  final String? employer; // Extracted employer name
  final List<Transaction> transactions; // All transactions in this cycle

  SalaryCycle({
    required this.id,
    required this.startDate,
    this.endDate,
    required this.salaryAmount,
    required this.salaryTransactionId,
    this.employer,
    this.transactions = const [],
  });

  bool get isCurrent => endDate == null;

  int get daysInCycle {
    final end = endDate ?? DateTime.now();
    return end.difference(startDate).inDays;
  }

  double get totalSpent {
    return transactions
        .where((t) => t.type == TransactionType.debit)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double get totalReceived {
    return transactions
        .where((t) =>
            t.type == TransactionType.credit && t.id != salaryTransactionId)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double get savings {
    return salaryAmount + totalReceived - totalSpent;
  }

  double get savingsPercentage {
    if (salaryAmount == 0) return 0;
    return (savings / salaryAmount) * 100;
  }

  String get cycleLabel {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    if (endDate != null) {
      return '${months[startDate.month - 1]} ${startDate.year}';
    }
    return 'Current Cycle';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'start_date': startDate.millisecondsSinceEpoch,
      'end_date': endDate?.millisecondsSinceEpoch,
      'salary_amount': salaryAmount,
      'salary_transaction_id': salaryTransactionId,
      'employer': employer,
    };
  }

  factory SalaryCycle.fromMap(Map<String, dynamic> map,
      {List<Transaction>? transactions}) {
    return SalaryCycle(
      id: map['id'] as String,
      startDate: DateTime.fromMillisecondsSinceEpoch(map['start_date'] as int),
      endDate: map['end_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_date'] as int)
          : null,
      salaryAmount: map['salary_amount'] as double,
      salaryTransactionId: map['salary_transaction_id'] as String,
      employer: map['employer'] as String?,
      transactions: transactions ?? [],
    );
  }

  SalaryCycle copyWith({
    String? id,
    DateTime? startDate,
    DateTime? endDate,
    double? salaryAmount,
    String? salaryTransactionId,
    String? employer,
    List<Transaction>? transactions,
  }) {
    return SalaryCycle(
      id: id ?? this.id,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      salaryAmount: salaryAmount ?? this.salaryAmount,
      salaryTransactionId: salaryTransactionId ?? this.salaryTransactionId,
      employer: employer ?? this.employer,
      transactions: transactions ?? this.transactions,
    );
  }
}

/// Configuration for salary detection
class SalaryConfig {
  final List<String> employerKeywords;
  final double? minimumAmount;
  final List<int>
      expectedDays; // Expected salary days (e.g., [25, 26, 27, 28, 29, 30, 31, 1])

  const SalaryConfig({
    this.employerKeywords = const ['HCA GLOBAL SERVICES', 'HCA', 'SALARY'],
    this.minimumAmount,
    this.expectedDays = const [25, 26, 27, 28, 29, 30, 31, 1],
  });

  Map<String, dynamic> toMap() {
    return {
      'employer_keywords': employerKeywords.join(','),
      'minimum_amount': minimumAmount,
      'expected_days': expectedDays.join(','),
    };
  }

  factory SalaryConfig.fromMap(Map<String, dynamic> map) {
    return SalaryConfig(
      employerKeywords:
          (map['employer_keywords'] as String?)?.split(',') ?? ['SALARY'],
      minimumAmount: map['minimum_amount'] as double?,
      expectedDays: (map['expected_days'] as String?)
              ?.split(',')
              .map((e) => int.tryParse(e) ?? 1)
              .toList() ??
          [25, 26, 27, 28, 29, 30, 31, 1],
    );
  }
}
