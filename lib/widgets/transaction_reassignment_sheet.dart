// lib/widgets/transaction_reassignment_sheet.dart
// Widget for manually reassigning transactions between accounts

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/account.dart';

class TransactionReassignmentSheet extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  final Function(List<Transaction>, String) onReassignment;

  const TransactionReassignmentSheet({
    super.key,
    required this.transactions,
    required this.accounts,
    required this.onReassignment,
  });

  @override
  State<TransactionReassignmentSheet> createState() => _TransactionReassignmentSheetState();
}

class _TransactionReassignmentSheetState extends State<TransactionReassignmentSheet> {
  final Set<String> _selectedTransactionIds = {};
  String? _targetAccountId;
  bool _selectAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedTransactions = widget.transactions
        .where((tx) => _selectedTransactionIds.contains(tx.id))
        .toList();

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
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.swap_horiz,
                        size: 22,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reassign Transactions',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Select transactions to move to a different account',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Selection controls
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Checkbox(
                            value: _selectAll,
                            onChanged: (value) {
                              setState(() {
                                _selectAll = value ?? false;
                                if (_selectAll) {
                                  _selectedTransactionIds.addAll(
                                    widget.transactions.map((tx) => tx.id),
                                  );
                                } else {
                                  _selectedTransactionIds.clear();
                                }
                              });
                            },
                          ),
                          Text(
                            'Select All (${widget.transactions.length})',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (selectedTransactions.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${selectedTransactions.length} selected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),

                if (selectedTransactions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  // Target account dropdown
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance, size: 20),
                        const SizedBox(width: 12),
                        const Text('Move to: '),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            value: _targetAccountId,
                            hint: const Text('Select account'),
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: widget.accounts.map((account) {
                              return DropdownMenuItem<String>(
                                value: account.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      account.type == AccountType.creditCard
                                          ? Icons.credit_card
                                          : Icons.account_balance,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(account.displayName)),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (accountId) {
                              setState(() => _targetAccountId = accountId);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Transactions list
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.transactions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final transaction = widget.transactions[index];
                final isSelected = _selectedTransactionIds.contains(transaction.id);

                return _TransactionTile(
                  transaction: transaction,
                  isSelected: isSelected,
                  onSelectionChanged: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTransactionIds.add(transaction.id);
                      } else {
                        _selectedTransactionIds.remove(transaction.id);
                        if (_selectAll) _selectAll = false;
                      }
                    });
                  },
                );
              },
            ),
          ),

          // Bottom action
          if (selectedTransactions.isNotEmpty && _targetAccountId != null) ...[
            const Divider(height: 1),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      widget.onReassignment(selectedTransactions, _targetAccountId!);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(
                      'Move ${selectedTransactions.length} Transaction${selectedTransactions.length > 1 ? 's' : ''}',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
            ),
          ] else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  selectedTransactions.isEmpty
                      ? 'Select transactions to reassign'
                      : 'Choose target account',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final bool isSelected;
  final Function(bool) onSelectionChanged;

  const _TransactionTile({
    required this.transaction,
    required this.isSelected,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = transaction;
    final amountColor = tx.isCredit ? Colors.green : Colors.red;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : amountColor.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: () => onSelectionChanged(!isSelected),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (val) => onSelectionChanged(val ?? false),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 18,
              backgroundColor: amountColor.withValues(alpha: 0.15),
              child: Icon(
                tx.isCredit ? Icons.add : Icons.remove,
                color: amountColor,
                size: 18,
              ),
            ),
          ],
        ),
        title: Text(
          tx.merchant ?? tx.sender,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isSelected ? theme.colorScheme.onPrimaryContainer : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('dd MMM yyyy, hh:mm a').format(tx.date),
              style: const TextStyle(fontSize: 11),
            ),
            if (tx.rawMessage.isNotEmpty) ...[
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tx.rawMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${tx.isCredit ? '+' : '-'}₹${NumberFormat('#,##,###').format(tx.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: amountColor,
                fontSize: 13,
              ),
            ),
            if (tx.accountLast4 != null) ...[
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '••••${tx.accountLast4}',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}