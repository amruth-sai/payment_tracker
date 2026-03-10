// lib/models/emi.dart

class DetectedEMI {
  final String id;
  final String merchant;
  final double amount;
  final int dayOfMonth;
  final List<DateTime> occurrences;
  final int totalDetected;
  final int? estimatedTotal; // null = unknown
  final bool isActive;

  DetectedEMI({
    required this.id,
    required this.merchant,
    required this.amount,
    required this.dayOfMonth,
    required this.occurrences,
    required this.totalDetected,
    this.estimatedTotal,
    this.isActive = true,
  });

  int? get remainingCount {
    if (estimatedTotal == null) return null;
    return (estimatedTotal! - totalDetected).clamp(0, estimatedTotal!);
  }

  double get monthlyBurden => amount;

  String get frequencyLabel => 'Monthly (Day $dayOfMonth)';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'merchant': merchant,
      'amount': amount,
      'day_of_month': dayOfMonth,
      'occurrences': occurrences
          .map((d) => d.millisecondsSinceEpoch)
          .toList()
          .join(','),
      'total_detected': totalDetected,
      'estimated_total': estimatedTotal,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory DetectedEMI.fromMap(Map<String, dynamic> map) {
    final occStr = (map['occurrences'] as String?) ?? '';
    final occurrences = occStr.isEmpty
        ? <DateTime>[]
        : occStr
            .split(',')
            .map((s) =>
                DateTime.fromMillisecondsSinceEpoch(int.tryParse(s) ?? 0))
            .toList();

    return DetectedEMI(
      id: map['id'] as String,
      merchant: map['merchant'] as String,
      amount: (map['amount'] as num).toDouble(),
      dayOfMonth: map['day_of_month'] as int,
      occurrences: occurrences,
      totalDetected: map['total_detected'] as int,
      estimatedTotal: map['estimated_total'] as int?,
      isActive: (map['is_active'] as int?) == 1,
    );
  }

  DetectedEMI copyWith({
    String? id,
    String? merchant,
    double? amount,
    int? dayOfMonth,
    List<DateTime>? occurrences,
    int? totalDetected,
    int? estimatedTotal,
    bool? isActive,
  }) {
    return DetectedEMI(
      id: id ?? this.id,
      merchant: merchant ?? this.merchant,
      amount: amount ?? this.amount,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      occurrences: occurrences ?? this.occurrences,
      totalDetected: totalDetected ?? this.totalDetected,
      estimatedTotal: estimatedTotal ?? this.estimatedTotal,
      isActive: isActive ?? this.isActive,
    );
  }
}
