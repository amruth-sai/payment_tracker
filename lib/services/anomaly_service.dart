// lib/services/anomaly_service.dart

import 'dart:math';
import '../models/app_alert.dart';
import '../models/transaction.dart';

/// Detects spending anomalies and duplicate transactions.
class AnomalyService {
  /// Detect unusual spending patterns.
  /// Compares recent 7-day merchant spending vs historical weekly average.
  static List<AppAlert> detectAnomalies(List<Transaction> transactions) {
    final alerts = <AppAlert>[];
    if (transactions.length < 5) return alerts;

    final debits = transactions.where((t) => t.isDebit).toList();
    if (debits.isEmpty) return alerts;

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = now.subtract(const Duration(days: 30));

    // Group by merchant
    final merchantHistory = <String, List<Transaction>>{};
    for (final tx in debits) {
      final key = (tx.merchant ?? tx.sender).toLowerCase().trim();
      merchantHistory.putIfAbsent(key, () => []).add(tx);
    }

    for (final entry in merchantHistory.entries) {
      final merchant = entry.key;
      final allTxs = entry.value;
      if (allTxs.length < 3) continue; // Need history

      final recentTxs = allTxs.where((t) => t.date.isAfter(weekAgo)).toList();
      final historicalTxs =
          allTxs.where((t) => t.date.isBefore(weekAgo)).toList();

      if (recentTxs.isEmpty || historicalTxs.isEmpty) continue;

      // Calculate weekly averages
      final recentTotal = recentTxs.fold(0.0, (sum, t) => sum + t.amount);
      final historicalWeeks = max(
          1.0,
          historicalTxs.last.date.difference(historicalTxs.first.date).inDays /
              7.0);
      final historicalWeeklyAvg =
          historicalTxs.fold(0.0, (sum, t) => sum + t.amount) / historicalWeeks;

      if (historicalWeeklyAvg <= 0) continue;

      final ratio = recentTotal / historicalWeeklyAvg;

      // Flag if spending is 2x or more than usual
      if (ratio >= 2.0) {
        final displayName = _capitalize(merchant);
        alerts.add(AppAlert(
          id: 'anomaly_${merchant}_${now.millisecondsSinceEpoch}',
          type: AlertType.anomaly,
          title: 'Unusual Spending: $displayName',
          message:
              'You spent ₹${recentTotal.toStringAsFixed(0)} at $displayName this week — '
              '${ratio.toStringAsFixed(1)}x more than your usual weekly average of '
              '₹${historicalWeeklyAvg.toStringAsFixed(0)}.',
          severity:
              ratio >= 3.0 ? AlertSeverity.critical : AlertSeverity.warning,
        ));
      }
    }

    // Detect unknown/new merchants with high amounts
    final recentDebits = debits.where((t) => t.date.isAfter(monthAgo)).toList();
    for (final tx in recentDebits) {
      final key = (tx.merchant ?? tx.sender).toLowerCase().trim();
      final history = merchantHistory[key] ?? [];
      if (history.length == 1 && tx.amount > 5000) {
        alerts.add(AppAlert(
          id: 'new_merchant_${tx.id}',
          type: AlertType.anomaly,
          title: 'New Merchant Charge',
          message: 'First-time charge of ₹${tx.amount.toStringAsFixed(0)} from '
              '${_capitalize(key)}.',
          severity: AlertSeverity.info,
          transactionId: tx.id,
        ));
      }
    }

    return alerts;
  }

  /// Detect potential duplicate transactions.
  /// Same amount + same sender within 5 minutes.
  static List<AppAlert> detectDuplicates(List<Transaction> transactions) {
    final alerts = <AppAlert>[];
    final sorted = [...transactions]..sort((a, b) => a.date.compareTo(b.date));
    final seen = <String>{};

    for (int i = 0; i < sorted.length; i++) {
      for (int j = i + 1; j < sorted.length; j++) {
        final diff = sorted[j].date.difference(sorted[i].date);
        if (diff.inMinutes > 5) break;

        if (sorted[i].amount == sorted[j].amount &&
            sorted[i].sender.toLowerCase() == sorted[j].sender.toLowerCase() &&
            sorted[i].type == sorted[j].type) {
          final pairKey = '${sorted[i].id}_${sorted[j].id}';
          if (seen.contains(pairKey)) continue;
          seen.add(pairKey);

          alerts.add(AppAlert(
            id: 'dup_$pairKey',
            type: AlertType.duplicate,
            title: 'Possible Duplicate',
            message:
                '₹${sorted[i].amount.toStringAsFixed(0)} from ${sorted[i].sender} '
                'appeared twice within ${diff.inMinutes} minutes.',
            severity: AlertSeverity.warning,
            transactionId: sorted[i].id,
          ));
        }
      }
    }

    return alerts;
  }

  /// Generate daily digest summary.
  static AppAlert? generateDailyDigest(
    List<Transaction> transactions,
    double? monthlyBudgetTotal,
    double? monthlyBudgetSpent,
  ) {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final yesterdayEnd = DateTime(now.year, now.month, now.day);

    final yesterdayTxs = transactions
        .where(
            (t) => t.date.isAfter(yesterday) && t.date.isBefore(yesterdayEnd))
        .toList();

    final totalSpent = yesterdayTxs
        .where((t) => t.isDebit)
        .fold(0.0, (sum, t) => sum + t.amount);

    if (totalSpent <= 0) return null;

    String budgetInfo = '';
    if (monthlyBudgetTotal != null && monthlyBudgetTotal > 0) {
      final usedPct =
          ((monthlyBudgetSpent ?? 0) / monthlyBudgetTotal * 100).clamp(0, 999);
      budgetInfo =
          ' This month you have used ${usedPct.toStringAsFixed(0)}% of your total budget.';
    }

    return AppAlert(
      id: 'digest_${yesterday.millisecondsSinceEpoch}',
      type: AlertType.dailyDigest,
      title: 'Daily Digest',
      message: 'Yesterday you spent ₹${totalSpent.toStringAsFixed(0)} across '
          '${yesterdayTxs.where((t) => t.isDebit).length} transactions.$budgetInfo',
      severity: AlertSeverity.info,
    );
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
