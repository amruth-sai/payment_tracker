import '../models/salary_cycle.dart';
import '../models/transaction.dart';

/// Shared matching rules for Activity and the heatmap. Empty sets mean all.
List<Transaction> filterTransactions(
  Iterable<Transaction> transactions, {
  int direction = 0,
  Set<String> senders = const {},
  Set<String> categories = const {},
  Set<String> tags = const {},
  SalaryCycle? cycle,
  String search = '',
}) {
  final query = search.toLowerCase().trim();
  return transactions.where((tx) {
    if (direction == 1 && !tx.isCredit || direction == 2 && !tx.isDebit) {
      return false;
    }
    if (senders.isNotEmpty && !senders.contains(tx.sender)) return false;
    if (categories.isNotEmpty && !categories.contains(tx.categoryId ?? '')) {
      return false;
    }
    if (tags.isNotEmpty && !tags.contains(tx.tag)) return false;
    if (cycle != null && !cycle.contains(tx.date)) return false;
    final text =
        '${tx.displayName} ${tx.sender} ${tx.note ?? ''} ${tx.tag ?? ''} ${tx.amount} ${tx.referenceId ?? ''}'
            .toLowerCase();
    return text.contains(query);
  }).toList();
}
