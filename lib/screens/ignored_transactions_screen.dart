// lib/screens/ignored_transactions_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transaction.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';
import '../widgets/transaction_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import 'ignored_messages_screen.dart';

class IgnoredTransactionsScreen extends StatefulWidget {
  const IgnoredTransactionsScreen({super.key});

  @override
  State<IgnoredTransactionsScreen> createState() =>
      _IgnoredTransactionsScreenState();
}

class _IgnoredTransactionsScreenState extends State<IgnoredTransactionsScreen> {
  late Future<List<Transaction>> _ignoredFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _ignoredFuture = _loadIgnoredTransactions();
  }

  Future<List<Transaction>> _loadIgnoredTransactions() async {
    final transactions = await LocalStorageService.getAllTransactions();
    final ignored = transactions.where((tx) => tx.isIgnored).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return ignored;
  }

  Future<void> _restoreTransaction(Transaction tx) async {
    if (tx.transferPartnerId != null) {
      final all = await LocalStorageService.getAllTransactions();
      final partners = all
          .where((item) => item.id == tx.transferPartnerId)
          .toList();
      if (partners.isNotEmpty &&
          partners.first.isIgnored &&
          partners.first.transferGroupId == tx.transferGroupId) {
        await LocalStorageService.updateTransactionsAtomic([
          tx.copyWith(isIgnored: false),
          partners.first.copyWith(isIgnored: false),
        ]);
      } else {
        await LocalStorageService.updateTransactionIgnored(tx.id, false);
      }
    } else {
      await LocalStorageService.updateTransactionIgnored(tx.id, false);
    }
    if (!mounted) return;

    context.read<SmsService>().reloadFromCache();
    setState(_reload);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${tx.displayName} restored to summaries'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ignored Transactions'),
        actions: [
          IconButton(
            tooltip: 'Message decisions',
            icon: const Icon(Icons.sms_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IgnoredMessagesScreen()),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Transaction>>(
        future: _ignoredFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load ignored transactions:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final ignored = snapshot.data ?? const <Transaction>[];
          if (ignored.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                setState(_reload);
                await _ignoredFuture;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.visibility_off_outlined, size: 64),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No ignored transactions',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Ignored items will appear here so you can count them back in later.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _ignoredFuture;
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: ignored.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final tx = ignored[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TransactionCard(
                        tx: tx,
                        accountDisplayName: context
                            .read<SmsService>()
                            .getAccountDisplayName(
                              tx.accountId,
                              tx.accountLast4,
                            ),
                        onTap: () => TransactionDetailSheet.show(
                          context,
                          tx,
                          onUpdated: (_) => setState(_reload),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _restoreTransaction(tx),
                          icon: const Icon(Icons.visibility, size: 18),
                          label: const Text('Count it'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
