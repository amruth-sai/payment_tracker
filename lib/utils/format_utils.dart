// lib/utils/format_utils.dart

import 'package:intl/intl.dart';

/// Utility class for common formatting operations
class FormatUtils {
  FormatUtils._(); // Private constructor to prevent instantiation

  /// Format an exact amount without dropping paise
  static String formatAmount(double amount) {
    return NumberFormat('#,##,##0.##', 'en_IN').format(amount);
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
