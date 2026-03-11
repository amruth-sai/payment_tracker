// lib/screens/tracking_settings_screen.dart
// Feature 4: Let user control which transactions are considered

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';

class TrackingSettingsScreen extends StatefulWidget {
  const TrackingSettingsScreen({super.key});

  @override
  State<TrackingSettingsScreen> createState() => _TrackingSettingsScreenState();
}

class _TrackingSettingsScreenState extends State<TrackingSettingsScreen> {
  bool _loading = true;
  DateTime? _trackFromDate;
  String? _trackFromTxId;
  List<Transaction> _allTransactions = [];
  Transaction? _anchorTransaction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final [date, txId, txs] = await Future.wait([
      LocalStorageService.getTrackFromDate(),
      LocalStorageService.getTrackFromTransactionId(),
      LocalStorageService.getAllTransactions(),
    ]);

    final allTxs = txs as List<Transaction>;
    final trackTxId = txId as String?;
    final trackDate = date as DateTime?;

    Transaction? anchor;
    if (trackTxId != null) {
      try {
        anchor = allTxs.firstWhere((t) => t.id == trackTxId);
      } catch (_) {}
    }

    setState(() {
      _trackFromDate = trackDate;
      _trackFromTxId = trackTxId;
      _allTransactions = allTxs;
      _anchorTransaction = anchor;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await LocalStorageService.setTrackFromDate(_trackFromDate);
    await LocalStorageService.setTrackFromTransactionId(_trackFromTxId);

    if (!mounted) return;
    // Refresh in-memory list
    await context.read<SmsService>().reloadFromCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Tracking settings saved'),
      backgroundColor: Colors.green,
    ));
    Navigator.pop(context);
  }

  Future<void> _clearAll() async {
    setState(() {
      _trackFromDate = null;
      _trackFromTxId = null;
      _anchorTransaction = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDate: _trackFromDate ?? now,
    );
    if (picked != null) {
      setState(() {
        _trackFromDate = picked;
        // Clear transaction anchor if date is set
        _trackFromTxId = null;
        _anchorTransaction = null;
      });
    }
  }

  Future<void> _pickTransaction() async {
    final selected = await showModalBottomSheet<Transaction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _TransactionPickerSheet(
          transactions: _allTransactions),
    );
    if (selected != null) {
      setState(() {
        _anchorTransaction = selected;
        _trackFromTxId = selected.id;
        // Use the transaction's date as the from-date too
        _trackFromDate = DateTime(
            selected.date.year, selected.date.month, selected.date.day);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSettings = _trackFromDate != null || _trackFromTxId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking Start Point'),
        actions: [
          if (hasSettings)
            TextButton(
              onPressed: _clearAll,
              child: const Text('Clear'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Old SMS messages can contain outdated transactions. '
                            'Set a start point so only relevant transactions are included in summaries.',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Current setting status
                  if (hasSettings) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              color: Colors.green, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Tracking from:',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        color: Colors.green)),
                                if (_anchorTransaction != null)
                                  Text(
                                    '${_anchorTransaction!.displayName} — '
                                    '${DateFormat('dd MMM yyyy').format(_anchorTransaction!.date)}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600),
                                  )
                                else if (_trackFromDate != null)
                                  Text(
                                    DateFormat('dd MMM yyyy')
                                        .format(_trackFromDate!),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Text('Option 1: Pick a date',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Only transactions on or after this date will be considered.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      _trackFromDate != null && _trackFromTxId == null
                          ? DateFormat('dd MMM yyyy').format(_trackFromDate!)
                          : 'Select start date',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: BorderSide(
                        color: _trackFromDate != null && _trackFromTxId == null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text('Option 2: Start from a transaction',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Select a specific transaction that marks your financial start point.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickTransaction,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(
                      _anchorTransaction != null
                          ? '${_anchorTransaction!.displayName} (${DateFormat('dd MMM yyyy').format(_anchorTransaction!.date)})'
                          : 'Select anchor transaction',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: BorderSide(
                        color: _anchorTransaction != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52)),
                    child: const Text('Save Settings',
                        style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TransactionPickerSheet extends StatefulWidget {
  final List<Transaction> transactions;
  const _TransactionPickerSheet({required this.transactions});

  @override
  State<_TransactionPickerSheet> createState() =>
      _TransactionPickerSheetState();
}

class _TransactionPickerSheetState extends State<_TransactionPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _query.isEmpty
        ? widget.transactions
        : widget.transactions
            .where((t) =>
                t.displayName.toLowerCase().contains(_query.toLowerCase()) ||
                DateFormat('dd MMM yyyy')
                    .format(t.date)
                    .contains(_query))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Select Start Transaction',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search transactions...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final tx = filtered[i];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      tx.isCredit ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                  child: Icon(
                    tx.isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 14,
                    color: tx.isCredit ? Colors.green : Colors.red,
                  ),
                ),
                title: Text(tx.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    DateFormat('dd MMM yyyy, hh:mm a').format(tx.date),
                    style: const TextStyle(fontSize: 11)),
                trailing: Text(
                  '₹${NumberFormat('#,##,###').format(tx.amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: tx.isCredit ? Colors.green : Colors.red,
                    fontSize: 13,
                  ),
                ),
                onTap: () => Navigator.pop(context, tx),
              );
            },
          ),
        ),
      ],
    );
  }
}
