// lib/widgets/sender_grouped_review_sheet.dart
// Enhanced review sheet that groups transactions by sender and allows type confirmation

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/local_storage_service.dart';
import '../services/sms_parser.dart';

/// Shows a bottom sheet with transactions grouped by sender for review.
/// Users can confirm transaction types for each sender group.
class SenderGroupedReviewSheet extends StatefulWidget {
  final List<Transaction> transactions;
  final VoidCallback onDone;

  const SenderGroupedReviewSheet({
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
      builder: (_) => SenderGroupedReviewSheet(
        transactions: transactions,
        onDone: onDone,
      ),
    );
  }

  @override
  State<SenderGroupedReviewSheet> createState() =>
      _SenderGroupedReviewSheetState();
}

class _SenderGroupedReviewSheetState extends State<SenderGroupedReviewSheet> {
  Map<String, List<Transaction>> _groupedTransactions = {};
  final Set<String> _toIgnore = {};
  final Map<String, TransactionType> _typeOverrides = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groupedTransactions = SmsParser.groupTransactionsBySender(widget.transactions);
  }

  Future<void> _confirmAll() async {
    setState(() => _saving = true);

    // Apply ignore flags
    for (final txId in _toIgnore) {
      await LocalStorageService.updateTransactionIgnored(txId, true);
    }

    // Apply type overrides
    for (final entry in _typeOverrides.entries) {
      final senderId = entry.key;
      final newType = entry.value;

      // Update all transactions for this sender
      final transactions = _groupedTransactions[senderId] ?? [];
      for (final tx in transactions) {
        if (!_toIgnore.contains(tx.id)) {
          await LocalStorageService.updateTransactionType(tx.id, newType);
        }
      }
    }

    setState(() => _saving = false);
    if (mounted) Navigator.pop(context);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalTransactions = widget.transactions.length;
    final senderCount = _groupedTransactions.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.account_balance_rounded,
                      size: 22, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$totalTransactions Transactions from $senderCount Bank${senderCount > 1 ? 's' : ''}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Review and confirm transaction types for each bank',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Sender groups list
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _groupedTransactions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final senderName = _groupedTransactions.keys.elementAt(index);
                final transactions = _groupedTransactions[senderName]!;
                return _SenderGroupTile(
                  senderName: senderName,
                  transactions: transactions,
                  ignoredTransactionIds: _toIgnore,
                  currentTypeOverride: _typeOverrides[senderName],
                  onToggleIgnoreTransaction: (txId) {
                    setState(() {
                      if (_toIgnore.contains(txId)) {
                        _toIgnore.remove(txId);
                      } else {
                        _toIgnore.add(txId);
                      }
                    });
                  },
                  onTypeChanged: (newType) {
                    setState(() {
                      if (newType != null) {
                        _typeOverrides[senderName] = newType;
                      } else {
                        _typeOverrides.remove(senderName);
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
                                _toIgnore.addAll(widget.transactions.map((t) => t.id));
                              });
                              _confirmAll();
                            },
                      child: const Text('Ignore All'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _confirmAll,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text('Confirm All'),
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

class _SenderGroupTile extends StatefulWidget {
  final String senderName;
  final List<Transaction> transactions;
  final Set<String> ignoredTransactionIds;
  final TransactionType? currentTypeOverride;
  final Function(String) onToggleIgnoreTransaction;
  final Function(TransactionType?) onTypeChanged;

  const _SenderGroupTile({
    required this.senderName,
    required this.transactions,
    required this.ignoredTransactionIds,
    required this.currentTypeOverride,
    required this.onToggleIgnoreTransaction,
    required this.onTypeChanged,
  });

  @override
  State<_SenderGroupTile> createState() => _SenderGroupTileState();
}

class _SenderGroupTileState extends State<_SenderGroupTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accountType = SmsParser.getAccountTypeSync(widget.senderName);
    final isUserBank = SmsParser.isUserBankSync(widget.senderName);

    final totalAmount = widget.transactions
        .where((tx) => !widget.ignoredTransactionIds.contains(tx.id))
        .fold<double>(0, (sum, tx) => sum + (tx.isCredit ? tx.amount : -tx.amount));

    final activeTransactions = widget.transactions
        .where((tx) => !widget.ignoredTransactionIds.contains(tx.id))
        .length;

    return Container(
      decoration: BoxDecoration(
        color: isUserBank
            ? theme.colorScheme.primaryContainer.withOpacity(0.3)
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUserBank
              ? theme.colorScheme.primary.withOpacity(0.5)
              : theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          // Header
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isUserBank
                    ? theme.colorScheme.primary.withOpacity(0.15)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                accountType == 'Credit Card'
                    ? Icons.credit_card
                    : Icons.account_balance,
                size: 20,
                color: isUserBank
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.senderName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isUserBank
                          ? theme.colorScheme.primary
                          : theme.textTheme.titleSmall?.color,
                    ),
                  ),
                ),
                if (isUserBank)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'YOUR BANK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$activeTransactions transaction${activeTransactions > 1 ? 's' : ''} • $accountType',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Total: ',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      '${totalAmount >= 0 ? '+' : ''}₹${NumberFormat('#,##,###').format(totalAmount.abs())}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: totalAmount >= 0 ? Colors.green : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Transaction type selector
                _TypeSelector(
                  currentType: widget.currentTypeOverride,
                  onChanged: widget.onTypeChanged,
                ),
                const SizedBox(width: 8),
                // Expand/collapse button
                IconButton(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  icon: AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
              ],
            ),
          ),

          // Transaction details (expandable)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 0),
            secondChild: Column(
              children: [
                const Divider(height: 1),
                ...widget.transactions.map((tx) => _TransactionTile(
                  transaction: tx,
                  isIgnored: widget.ignoredTransactionIds.contains(tx.id),
                  onToggleIgnore: () => widget.onToggleIgnoreTransaction(tx.id),
                )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  final TransactionType? currentType;
  final Function(TransactionType?) onChanged;

  const _TypeSelector({
    required this.currentType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopupMenuButton<TransactionType?>(
      onSelected: onChanged,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: null,
          child: Row(
            children: [
              Icon(Icons.auto_fix_high, size: 16,
                   color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              const Text('Auto-detect'),
            ],
          ),
        ),
        PopupMenuItem(
          value: TransactionType.credit,
          child: Row(
            children: [
              Icon(Icons.add_circle, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              const Text('Credit (Money In)'),
            ],
          ),
        ),
        PopupMenuItem(
          value: TransactionType.debit,
          child: Row(
            children: [
              Icon(Icons.remove_circle, size: 16, color: Colors.red),
              const SizedBox(width: 8),
              const Text('Debit (Money Out)'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: currentType == null
              ? theme.colorScheme.surfaceContainerHighest
              : (currentType == TransactionType.credit
                  ? Colors.green.withOpacity(0.15)
                  : Colors.red.withOpacity(0.15)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              currentType == null
                  ? Icons.auto_fix_high
                  : (currentType == TransactionType.credit
                      ? Icons.add_circle
                      : Icons.remove_circle),
              size: 14,
              color: currentType == null
                  ? theme.colorScheme.onSurfaceVariant
                  : (currentType == TransactionType.credit ? Colors.green : Colors.red),
            ),
            const SizedBox(width: 4),
            Text(
              currentType == null ? 'Auto' : (currentType == TransactionType.credit ? 'Credit' : 'Debit'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: currentType == null
                    ? theme.colorScheme.onSurfaceVariant
                    : (currentType == TransactionType.credit ? Colors.green : Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final bool isIgnored;
  final VoidCallback onToggleIgnore;

  const _TransactionTile({
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
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: isIgnored
              ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              tx.isCredit ? Icons.add : Icons.remove,
              size: 14,
              color: amountColor,
            ),
          ),
          title: Text(
            tx.merchant ?? 'Transaction',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
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
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onToggleIgnore,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isIgnored
                        ? Colors.orange.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    isIgnored ? Icons.visibility_off : Icons.visibility,
                    size: 14,
                    color: isIgnored ? Colors.orange : Colors.grey,
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