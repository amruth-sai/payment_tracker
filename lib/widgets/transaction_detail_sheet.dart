// lib/widgets/transaction_detail_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';

class TransactionDetailSheet extends StatelessWidget {
  final Transaction tx;
  const TransactionDetailSheet({super.key, required this.tx});

  static void show(BuildContext context, Transaction tx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransactionDetailSheet(tx: tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit = tx.isCredit;
    final color = isCredit ? const Color(0xFF1DB954) : const Color(0xFFE53935);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Amount hero
          Icon(
            isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            color: color, size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            '${isCredit ? '+' : '-'}₹${NumberFormat('#,##,###.##').format(tx.amount)}',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tx.typeLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _DetailRow('Date & Time', DateFormat('dd MMM yyyy, hh:mm a').format(tx.date), theme),
                _DetailRow('Via', tx.sourceLabel, theme),
                if (tx.merchant != null) _DetailRow('Merchant', tx.merchant!, theme),
                if (tx.accountLast4 != null) _DetailRow('Account', '••••${tx.accountLast4}', theme),
                if (tx.balance != null)
                  _DetailRow('Balance After', '₹${NumberFormat('#,##,###.##').format(tx.balance!)}', theme),
                if (tx.referenceId != null) _DetailRow('Reference ID', tx.referenceId!, theme, copyable: true),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Raw SMS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ExpansionTile(
              title: Text('Raw SMS', style: theme.textTheme.bodySmall),
              tilePadding: EdgeInsets.zero,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tx.rawMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  final bool copyable;

  const _DetailRow(this.label, this.value, this.theme, {this.copyable = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            children: [
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (copyable) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied!'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: Icon(Icons.copy_rounded, size: 14, color: theme.colorScheme.primary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
