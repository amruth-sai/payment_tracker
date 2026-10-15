import '../models/transaction.dart';

/// Selects active transactions for a user-approved bulk label change.
class TransactionWindowService {
  static int compareByDateAndId(Transaction a, Transaction b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }

  /// Includes every transaction on both selected calendar days.
  static List<Transaction> byDateRange(
    Iterable<Transaction> transactions,
    DateTime start,
    DateTime end,
  ) {
    final firstDay = DateTime(start.year, start.month, start.day);
    final afterLastDay = DateTime(end.year, end.month, end.day + 1);
    if (!firstDay.isBefore(afterLastDay)) {
      throw ArgumentError('The end date must be on or after the start date.');
    }
    return transactions
        .where(
          (tx) => !tx.date.isBefore(firstDay) && tx.date.isBefore(afterLastDay),
        )
        .toList()
      ..sort(compareByDateAndId);
  }

  /// Includes both selected transactions and everything between them in time.
  /// IDs settle the order of payments that have the same timestamp.
  static List<Transaction> betweenTransactions(
    Iterable<Transaction> transactions,
    String firstId,
    String lastId,
  ) {
    final sorted = transactions.toList()..sort(compareByDateAndId);
    final firstIndex = sorted.indexWhere((tx) => tx.id == firstId);
    final lastIndex = sorted.indexWhere((tx) => tx.id == lastId);
    if (firstIndex < 0 || lastIndex < 0) return const [];
    final start = firstIndex < lastIndex ? firstIndex : lastIndex;
    final end = firstIndex < lastIndex ? lastIndex : firstIndex;
    return sorted.sublist(start, end + 1);
  }
}
