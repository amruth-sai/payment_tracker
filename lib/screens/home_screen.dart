// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/sms_service.dart';
import '../services/ai_sms_parser.dart';
import '../models/transaction.dart';
import '../widgets/transaction_card.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import '../widgets/new_transactions_review_sheet.dart';
import 'all_transactions_screen.dart';
import 'settings_screen.dart';
import 'accounts_screen.dart';
import 'spending_breakdown_screen.dart';
import 'salary_cycle_screen.dart';
import 'category_breakdown_screen.dart';
import 'budget_screen.dart';
import 'spending_heatmap_screen.dart';
import 'merchant_rankings_screen.dart';
import 'emi_tracker_screen.dart';
import 'alerts_screen.dart';
import 'custom_categories_screen.dart';
import 'tracking_settings_screen.dart';
import '../services/local_storage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedFilter = 0; // 0=All, 1=In, 2=Out
  final _filters = ['All', 'Money In', 'Money Out'];
  int _unreadAlertCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sms = context.read<SmsService>();
      await sms.initializeAI(); // Load AI if API key exists
      await sms.loadTransactions();
      _loadAlertCount();
      // Feature 6: show review popup if new transactions were found
      if (mounted && sms.newlyFoundTransactions.isNotEmpty) {
        await NewTransactionsReviewSheet.show(
          context,
          transactions: sms.newlyFoundTransactions,
          onDone: () {
            sms.clearNewlyFoundTransactions();
            sms.reloadFromCache();
          },
        );
      }
    });
  }

  Future<void> _loadAlertCount() async {
    final unread = await LocalStorageService.getUnreadAlerts();
    if (mounted) {
      setState(() => _unreadAlertCount = unread.length);
    }
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
                    totalIn: sms.currentMonthCredits,
                    totalOut: sms.currentMonthDebits,
                    txCount: sms.currentMonthTransactions.length,
                    subtitle: DateFormat('MMMM yyyy').format(DateTime.now()),
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
                            'This Month',
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
                color: Colors.amber.withValues(alpha: 0.2),
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
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlertsScreen()),
                );
                _loadAlertCount();
              },
            ),
            if (_unreadAlertCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _unreadAlertCount > 9 ? '9+' : '$_unreadAlertCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
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
      child: Column(
        children: [
          // Row 1 - Original buttons
          Row(
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
              const SizedBox(width: 8),
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
              const SizedBox(width: 8),
              _QuickActionButton(
                icon: Icons.calendar_month,
                label: 'Salary',
                color: Colors.green,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SalaryCycleScreen()),
                ),
              ),
              const SizedBox(width: 8),
              _QuickActionButton(
                icon: Icons.category,
                label: 'Categories',
                color: Colors.teal,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CategoryBreakdownScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2 - New feature buttons
          Row(
            children: [
              _QuickActionButton(
                icon: Icons.savings,
                label: 'Budgets',
                color: Colors.orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BudgetScreen()),
                ),
              ),
              const SizedBox(width: 8),
              _QuickActionButton(
                icon: Icons.grid_on,
                label: 'Heatmap',
                color: Colors.red,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SpendingHeatmapScreen()),
                ),
              ),
              const SizedBox(width: 8),
              _QuickActionButton(
                icon: Icons.bar_chart,
                label: 'Merchants',
                color: Colors.indigo,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const MerchantRankingsScreen()),
                ),
              ),
              const SizedBox(width: 8),
              _QuickActionButton(
                icon: Icons.event_repeat,
                label: 'EMIs',
                color: Colors.amber,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EMITrackerScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 3 - New feature buttons (Features 3 & 4)
          Row(
            children: [
              _QuickActionButton(
                icon: Icons.label_outline,
                label: 'My Labels',
                color: Colors.teal,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CustomCategoriesScreen()),
                ),
              ),
              const SizedBox(width: 8),
              _QuickActionButton(
                icon: Icons.history_toggle_off_outlined,
                label: 'Tracking',
                color: Colors.blueGrey,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TrackingSettingsScreen()),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()), // spacer
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()), // spacer
            ],
          ),
          // Alerts banner
          if (_unreadAlertCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AlertsScreen()),
                  );
                  _loadAlertCount();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '$_unreadAlertCount unread alert${_unreadAlertCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios,
                          size: 14, color: Colors.orange),
                    ],
                  ),
                ),
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
    // Feature 5: base is current month transactions
    final base = sms.currentMonthTransactions;
    switch (_selectedFilter) {
      case 1:
        return base.where((t) => t.isCredit).toList();
      case 2:
        return base.where((t) => t.isDebit).toList();
      default:
        return base;
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
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
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
