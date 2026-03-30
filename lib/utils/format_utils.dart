// lib/utils/format_utils.dart

import 'package:intl/intl.dart';

/// Utility class for common formatting operations
class FormatUtils {
  FormatUtils._(); // Private constructor to prevent instantiation

  /// Format amount with K/L notation for large numbers
  static String formatAmount(double amount) {
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      final formatter = NumberFormat('#,##,###');
      return formatter.format(amount.toInt());
    }
    return amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2);
  }

  /// Format amount with currency symbol
  static String formatCurrency(double amount) {
    return '₹${formatAmount(amount)}';
  }

  /// Format date and time for UI display
  static String formatDateTime(DateTime date) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(date);
  }

  /// Format date for display in lists
  static String formatDateShort(DateTime date) {
    return DateFormat('dd MMM, hh:mm a').format(date);
  }
}