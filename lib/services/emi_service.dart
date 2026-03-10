// lib/services/emi_service.dart

import '../models/emi.dart';
import '../models/transaction.dart';

/// Detects recurring payments that look like EMIs.
class EMIService {
  /// Detect EMI-like recurring payments.
  /// Looks for same merchant + similar amount recurring monthly.
  static List<DetectedEMI> detectEMIs(List<Transaction> transactions) {
    final debits = transactions.where((t) => t.isDebit).toList();
    if (debits.length < 3) return [];

    // Group by merchant + round amount (within 2%)
    final groups = <String, List<Transaction>>{};
    for (final tx in debits) {
      final merchant = (tx.merchant ?? tx.sender).toLowerCase().trim();
      // Round amount to group similar amounts
      final roundedAmount = (tx.amount / 100).round() * 100;
      final key = '${merchant}_$roundedAmount';
      groups.putIfAbsent(key, () => []).add(tx);
    }

    final emis = <DetectedEMI>[];

    for (final entry in groups.entries) {
      final txs = entry.value;
      if (txs.length < 2) continue;

      // Sort by date
      txs.sort((a, b) => a.date.compareTo(b.date));

      // Check if dates are roughly monthly (25-40 day intervals)
      final intervals = <int>[];
      for (int i = 1; i < txs.length; i++) {
        final gap = txs[i].date.difference(txs[i - 1].date).inDays;
        intervals.add(gap);
      }

      // At least half the intervals should be monthly (25-40 days)
      final monthlyIntervals =
          intervals.where((d) => d >= 25 && d <= 40).length;
      if (monthlyIntervals < intervals.length * 0.5) continue;

      // This looks like an EMI
      final avgAmount =
          txs.fold(0.0, (sum, t) => sum + t.amount) / txs.length;
      final avgDay =
          txs.map((t) => t.date.day).reduce((a, b) => a + b) ~/ txs.length;
      final merchant = (txs.first.merchant ?? txs.first.sender).trim();

      // Check if amounts are consistent (within 5%)
      final amountVariance = txs
          .map((t) => (t.amount - avgAmount).abs() / avgAmount)
          .reduce((a, b) => a > b ? a : b);
      if (amountVariance > 0.10) continue; // Too much variance

      emis.add(DetectedEMI(
        id: 'emi_${merchant.toLowerCase().replaceAll(' ', '_')}_${avgAmount.toInt()}',
        merchant: merchant,
        amount: avgAmount,
        dayOfMonth: avgDay,
        occurrences: txs.map((t) => t.date).toList(),
        totalDetected: txs.length,
        isActive: _isRecentlyActive(txs),
      ));
    }

    // Sort by amount descending
    emis.sort((a, b) => b.amount.compareTo(a.amount));
    return emis;
  }

  /// Check if the last occurrence is within 45 days.
  static bool _isRecentlyActive(List<Transaction> txs) {
    if (txs.isEmpty) return false;
    final lastDate = txs.map((t) => t.date).reduce((a, b) => a.isAfter(b) ? a : b);
    return DateTime.now().difference(lastDate).inDays <= 45;
  }

  /// Calculate total monthly EMI burden.
  static double totalMonthlyBurden(List<DetectedEMI> emis) {
    return emis
        .where((e) => e.isActive)
        .fold(0.0, (sum, e) => sum + e.amount);
  }
}
