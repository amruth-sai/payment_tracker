// lib/screens/all_transactions_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sms_service.dart';
import '../models/transaction.dart';
import '../widgets/transaction_card.dart';
import '../widgets/transaction_detail_sheet.dart';

class AllTransactionsScreen extends StatefulWidget {
  final int filter;
  const AllTransactionsScreen({super.key, this.filter = 0});

  @override
  State<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends State<AllTransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.filter,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Transactions', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Money In'),
            Tab(text: 'Money Out'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              hintText: 'Search merchant, bank...',
              leading: const Icon(Icons.search_rounded),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),

          Expanded(
            child: Consumer<SmsService>(
              builder: (context, sms, _) {
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _TxList(transactions: _filter(sms.transactions), search: _search),
                    _TxList(transactions: _filter(sms.credits), search: _search),
                    _TxList(transactions: _filter(sms.debits), search: _search),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Transaction> _filter(List<Transaction> list) {
    if (_search.isEmpty) return list;
    return list.where((t) {
      return t.displayName.toLowerCase().contains(_search) ||
          (t.merchant?.toLowerCase().contains(_search) ?? false) ||
          t.sender.toLowerCase().contains(_search);
    }).toList();
  }
}

class _TxList extends StatelessWidget {
  final List<Transaction> transactions;
  final String search;

  const _TxList({required this.transactions, required this.search});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              search.isNotEmpty ? 'No results for "$search"' : 'No transactions',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Group by date
    final grouped = <String, List<Transaction>>{};
    for (final tx in transactions) {
      final key = _dateKey(tx.date);
      grouped.putIfAbsent(key, () => []).add(tx);
    }

    final keys = grouped.keys.toList();

    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key = keys[i];
        final txs = grouped[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                key,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...txs.map(
              (tx) => TransactionCard(
                tx: tx,
                onTap: () => TransactionDetailSheet.show(context, tx),
              ),
            ),
          ],
        );
      },
    );
  }

  String _dateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
