// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sms_service.dart';
import '../models/transaction.dart';
import '../widgets/transaction_card.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import 'all_transactions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedFilter = 0; // 0=All, 1=In, 2=Out
  final _filters = ['All', 'Money In', 'Money Out'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SmsService>().loadTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<SmsService>(
        builder: (context, sms, _) {
          if (sms.isLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Reading your messages...'),
                ],
              ),
            );
          }

          if (sms.error != null) {
            return _ErrorView(
              message: sms.error!,
              onRetry: () => sms.loadTransactions(),
            );
          }

          final filtered = _getFiltered(sms);
          final recent = filtered.take(5).toList();

          return RefreshIndicator(
            onRefresh: () => sms.loadTransactions(),
            child: CustomScrollView(
              slivers: [
                _buildAppBar(context),
                SliverToBoxAdapter(
                  child: SummaryCard(
                    totalIn: sms.totalCredits,
                    totalOut: sms.totalDebits,
                    txCount: sms.transactions.length,
                  ),
                ),
                SliverToBoxAdapter(child: _buildFilterRow()),
                if (sms.transactions.isEmpty)
                  const SliverFillRemaining(
                    child: Center(child: Text('No payment messages found.')),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Transactions',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AllTransactionsScreen(filter: _selectedFilter),
                              ),
                            ),
                            child: const Text('See All'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => TransactionCard(
                        tx: recent[i],
                        onTap: () => TransactionDetailSheet.show(context, recent[i]),
                      ),
                      childCount: recent.length,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      floating: true,
      snap: true,
      title: const Text(
        'Payment Tracker',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => context.read<SmsService>().loadTransactions(),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(_filters.length, (i) {
          final selected = i == _selectedFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_filters[i]),
              selected: selected,
              onSelected: (_) => setState(() => _selectedFilter = i),
            ),
          );
        }),
      ),
    );
  }

  List<Transaction> _getFiltered(SmsService sms) {
    switch (_selectedFilter) {
      case 1:
        return sms.credits;
      case 2:
        return sms.debits;
      default:
        return sms.transactions;
    }
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sms_failed_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
