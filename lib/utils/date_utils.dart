class AppDateUtils {
  /// Common month abbreviations used across the app
  static const List<String> months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// Format a DateTime as a display string (e.g., "23 Mar 2024", "Today", "Yesterday")
  static String formatDateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  /// Parse a date key back to DateTime for sorting purposes
  static DateTime parseDateKey(String dateKey) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (dateKey == 'Today') return today;
    if (dateKey == 'Yesterday') return today.subtract(const Duration(days: 1));

    // Parse date from format "23 Mar 2024"
    final parts = dateKey.split(' ');
    if (parts.length != 3) return today; // Fallback

    final day = int.tryParse(parts[0]) ?? 1;
    final year = int.tryParse(parts[2]) ?? now.year;

    final monthIndex = months.indexOf(parts[1]);
    final month = monthIndex >= 0 ? monthIndex + 1 : now.month;

    return DateTime(year, month, day);
  }
}