class AppDateUtils {
  /// Half-open salary-day period. Short months clamp the requested day.
  static (DateTime, DateTime) salaryPeriod(DateTime now, int salaryDay) {
    if (salaryDay < 1 || salaryDay > 31) {
      throw ArgumentError('Salary day must be 1-31.');
    }
    DateTime boundary(int year, int month) {
      final first = DateTime(year, month);
      final lastDay = DateTime(first.year, first.month + 1, 0).day;
      return DateTime(first.year, first.month, salaryDay.clamp(1, lastDay));
    }

    final thisMonth = boundary(now.year, now.month);
    final start = now.isBefore(thisMonth)
        ? boundary(now.year, now.month - 1)
        : thisMonth;
    return (start, boundary(start.year, start.month + 1));
  }

  /// Common month abbreviations used across the app
  static const List<String> months = [
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
    'Dec',
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
