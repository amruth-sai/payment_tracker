// lib/widgets/transaction_detail_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/local_storage_service.dart';

class TransactionDetailSheet extends StatefulWidget {
  final Transaction tx;
  final Function(Transaction)? onTransactionUpdated;
  
  const TransactionDetailSheet({
    super.key, 
    required this.tx,
    this.onTransactionUpdated,
  });

  static void show(BuildContext context, Transaction tx, {Function(Transaction)? onUpdated}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransactionDetailSheet(
        tx: tx, 
        onTransactionUpdated: onUpdated,
      ),
    );
  }

  @override
  State<TransactionDetailSheet> createState() => _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<TransactionDetailSheet> {
  late Transaction _tx;

  @override
  void initState() {
    super.initState();
    _tx = widget.tx;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit = _tx.isCredit;
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
            '${isCredit ? '+' : '-'}₹${NumberFormat('#,##,###.##').format(_tx.amount)}',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _tx.typeLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_tx.isUserCorrected) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CORRECTED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Correction button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: _showCorrectionDialog,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Correct Transaction Type'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _DetailRow('Date & Time', DateFormat('dd MMM yyyy, hh:mm a').format(_tx.date), theme),
                _DetailRow('Via', _tx.sourceLabel, theme),
                if (_tx.merchant != null) _DetailRow('Merchant', _tx.merchant!, theme),
                if (_tx.accountLast4 != null) _DetailRow('Account', '••••${_tx.accountLast4}', theme),
                if (_tx.balance != null)
                  _DetailRow('Balance After', '₹${NumberFormat('#,##,###.##').format(_tx.balance!)}', theme),
                if (_tx.referenceId != null) _DetailRow('Reference ID', _tx.referenceId!, theme, copyable: true),
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
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _tx.rawMessage,
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

  void _showCorrectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct Transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This transaction was detected as:'),
            const SizedBox(height: 8),
            Chip(
              label: Text(_tx.isCredit ? 'Money In (Credit)' : 'Money Out (Debit)'),
              backgroundColor: _tx.isCredit 
                  ? Colors.green.withOpacity(0.2) 
                  : Colors.red.withOpacity(0.2),
            ),
            const SizedBox(height: 16),
            const Text('Change it to:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (_tx.isCredit)
            FilledButton.icon(
              onPressed: () => _correctType(TransactionType.debit),
              icon: const Icon(Icons.arrow_upward),
              label: const Text('Money Out'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
            )
          else
            FilledButton.icon(
              onPressed: () => _correctType(TransactionType.credit),
              icon: const Icon(Icons.arrow_downward),
              label: const Text('Money In'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
        ],
      ),
    );
  }

  Future<void> _correctType(TransactionType newType) async {
    Navigator.pop(context); // Close dialog
    
    final correctedTx = _tx.copyWith(
      type: newType,
      isUserCorrected: true,
    );
    
    await LocalStorageService.updateTransaction(correctedTx);
    
    setState(() {
      _tx = correctedTx;
    });
    
    widget.onTransactionUpdated?.call(correctedTx);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction corrected'),
          backgroundColor: Colors.green,
        ),
      );
    }
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
