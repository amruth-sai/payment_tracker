// lib/widgets/new_transactions_review_sheet.dart
// Feature 6: Review popup for newly detected transactions

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/local_storage_service.dart';

/// Shows a bottom sheet listing newly detected transactions.
/// Users can ignore individual items or confirm all at once.
class NewTransactionsReviewSheet extends StatefulWidget {
  final List<Transaction> transactions;
  final VoidCallback onDone;

  const NewTransactionsReviewSheet({
    super.key,
    required this.transactions,
    required this.onDone,
  });

  /// Convenience: show and await
  static Future<void> show(
    BuildContext context, {
    required List<Transaction> transactions,
    required VoidCallback onDone,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => NewTransactionsReviewSheet(
        transactions: transactions,
        onDone: onDone,
      ),
    );
  }

  @override
  State<NewTransactionsReviewSheet> createState() =>
      _NewTransactionsReviewSheetState();
}

class _NewTransactionsReviewSheetState
    extends State<NewTransactionsReviewSheet> {
  // Track which transaction IDs the user has marked to ignore
  final Set<String> _toIgnore = {};
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    // Apply ignore flag to selected transactions
    for (final txId in _toIgnore) {
      await LocalStorageService.updateTransactionIgnored(txId, true);
    }
    setState(() => _saving = false);
    if (mounted) Navigator.pop(context);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.transactions.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.mark_chat_unread_outlined,
                      size: 22, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count New Transaction${count > 1 ? 's' : ''} Found',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _toIgnore.isEmpty
                            ? 'Review and confirm, or ignore ones you don\'t need.'
                            : '${_toIgnore.length} marked to ignore',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _toIgnore.isEmpty
                              ? theme.colorScheme.onSurfaceVariant
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Transaction list
          Flexible(
            child: ListView.separated(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: widget.transactions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final tx = widget.transactions[index];
                final ignored = _toIgnore.contains(tx.id);
                return _ReviewTile(
                  transaction: tx,
                  isIgnored: ignored,
                  onToggleIgnore: () {
                    setState(() {
                      if (ignored) {
                        _toIgnore.remove(tx.id);
                      } else {
                        _toIgnore.add(tx.id);
                      }
                    });
                  },
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Bottom actions
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () {
                              // Ignore ALL
                              setState(() {
                                _toIgnore.addAll(
                                    widget.transactions.map((t) => t.id));
                              });
                              _confirm();
                            },
                      child: const Text('Ignore All'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _confirm,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : Text(_toIgnore.isEmpty
                              ? 'Confirm All'
                              : 'Confirm (ignore ${_toIgnore.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final Transaction transaction;
  final bool isIgnored;
  final VoidCallback onToggleIgnore;

  const _ReviewTile({
    required this.transaction,
    required this.isIgnored,
    required this.onToggleIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = transaction;
    final amountColor = tx.isCredit ? Colors.green : Colors.red;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isIgnored ? 0.45 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: isIgnored
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isIgnored
                ? theme.colorScheme.outline.withValues(alpha: 0.3)
                : amountColor.withValues(alpha: 0.25),
          ),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: amountColor.withValues(alpha: 0.15),
            child: Text(
              tx.category?.emoji ?? (tx.isCredit ? '💰' : '💸'),
              style: const TextStyle(fontSize: 18),
            ),
          ),
          title: Text(
            tx.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              decoration: isIgnored ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Text(
            DateFormat('dd MMM, hh:mm a').format(tx.date),
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${tx.isCredit ? '+' : '-'}₹${NumberFormat('#,##,###').format(tx.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: amountColor,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onToggleIgnore,
                child: Tooltip(
                  message: isIgnored ? 'Un-ignore' : 'Ignore',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isIgnored
                          ? Colors.orange.withValues(alpha: 0.15)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isIgnored
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: isIgnored ? Colors.orange : Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
