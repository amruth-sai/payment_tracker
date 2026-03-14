// lib/widgets/transaction_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';

class TransactionCard extends StatelessWidget {
  final Transaction tx;
  final VoidCallback? onTap;
  final Function(Transaction)? onSwipeIgnore;
  final Function(Transaction)? onSwipeToggleType;

  const TransactionCard({
    super.key,
    required this.tx,
    this.onTap,
    this.onSwipeIgnore,
    this.onSwipeToggleType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit = tx.isCredit;
    final color = isCredit ? const Color(0xFF1DB954) : const Color(0xFFE53935);
    final bgColor = isCredit
        ? const Color(0xFF1DB954).withValues(alpha: 0.08)
        : const Color(0xFFE53935).withValues(alpha: 0.08);

    final cardContent = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isCredit
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Name + source + date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _Chip(
                            label: tx.sourceLabel,
                            color: theme.colorScheme.primary),
                        if (tx.accountLast4 != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '••${tx.accountLast4}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('dd MMM, hh:mm a').format(tx.date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isCredit ? '+' : '-'}₹${_formatAmount(tx.amount)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (tx.balance != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Bal: ₹${_formatAmount(tx.balance!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // If no swipe callbacks provided, return plain card
    if (onSwipeIgnore == null && onSwipeToggleType == null) {
      return cardContent;
    }

    // Wrap with Dismissible for swipe actions
    return Dismissible(
      key: ValueKey('tx_swipe_${tx.id}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd && onSwipeIgnore != null) {
          // Swipe right → Ignore
          onSwipeIgnore!(tx);
          return false; // Don't actually remove from list; we handle it
        } else if (direction == DismissDirection.endToStart &&
            onSwipeToggleType != null) {
          // Swipe left → Toggle credit/debit
          onSwipeToggleType!(tx);
          return false;
        }
        return false;
      },
      background: // Swipe right background (Ignore)
          Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Ignore',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: // Swipe left background (Toggle type)
          Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: isCredit ? const Color(0xFFE53935) : const Color(0xFF1DB954),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isCredit ? 'Money Out' : 'Money In',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isCredit
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: Colors.white,
              size: 22,
            ),
          ],
        ),
      ),
      child: cardContent,
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      final formatter = NumberFormat('#,##,###');
      return formatter.format(amount.toInt());
    }
    return amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
