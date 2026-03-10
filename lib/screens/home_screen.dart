// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sms_service.dart';
import '../services/ai_sms_parser.dart';
import '../models/transaction.dart';
import '../widgets/transaction_card.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import 'all_transactions_screen.dart';
import 'settings_screen.dart';
import 'accounts_screen.dart';
import 'spending_breakdown_screen.dart';
import 'salary_cycle_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sms = context.read<SmsService>();
      await sms.initializeAI(); // Load AI if API key exists
      sms.loadTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<SmsService>(
        builder: (context, sms, _) {
          if (sms.isLoading) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(sms.loadingStatus.isNotEmpty
                      ? sms.loadingStatus
                      : 'Reading your messages...'),
                  if (sms.cachedCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${sms.cachedCount} cached transactions loaded',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
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
                SliverToBoxAdapter(child: _buildQuickActions()),
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
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AllTransactionsScreen(
                                    filter: _selectedFilter),
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
                        onTap: () =>
                            TransactionDetailSheet.show(context, recent[i]),
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
    // ignore: unused_local_variable
    final _ =
        context.watch<SmsService>(); // Trigger rebuild when AI status changes
    return SliverAppBar(
      floating: true,
      snap: true,
      title: Row(
        children: [
          const Text(
            'Payment Tracker',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          if (AiSmsParser.isInitialized) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 12, color: Colors.amber),
                  SizedBox(width: 2),
                  Text('AI',
                      style: TextStyle(fontSize: 10, color: Colors.amber)),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => context.read<SmsService>().loadTransactions(),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
            // Reload with potentially new AI settings
            if (context.mounted) {
              context.read<SmsService>().loadTransactions();
            }
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _QuickActionButton(
            icon: Icons.account_balance_wallet,
            label: 'Accounts',
            color: Colors.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountsScreen()),
            ),
          ),
          const SizedBox(width: 12),
          _QuickActionButton(
            icon: Icons.pie_chart,
            label: 'Breakdown',
            color: Colors.purple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SpendingBreakdownScreen()),
            ),
          ),
          const SizedBox(width: 12),
          _QuickActionButton(
            icon: Icons.calendar_month,
            label: 'Salary Cycles',
            color: Colors.green,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SalaryCycleScreen()),
            ),
          ),
        ],
      ),
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

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
