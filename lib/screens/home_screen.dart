// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sms_service.dart';
import '../models/transaction.dart';
import '../widgets/transaction_card.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import '../widgets/new_transactions_review_sheet.dart';
import '../widgets/tracking_onboarding_sheet.dart';
import 'all_transactions_screen.dart';
import 'settings_screen.dart';
import 'alerts_screen.dart';
import 'transaction_review_screen.dart';
import '../services/local_storage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.isActive = true,
    this.refreshToken = 0,
    this.onSeeAll,
    this.onOpenSettings,
    this.onOpenReview,
  });

  final bool isActive;
  final int refreshToken;
  final ValueChanged<int>? onSeeAll;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenReview;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedFilter = 0; // 0=All, 1=In, 2=Out
  final _filters = ['All', 'Money In', 'Money Out'];
  int _unreadAlertCount = 0;
  int _reviewCount = 0;
  final _scrollController = ScrollController();
  String? _selectedBank; // null = All Banks

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sms = context.read<SmsService>();

      // Check if user has completed onboarding (tracking start point)
      final hasOnboarded = await LocalStorageService.hasCompletedOnboarding();
      if (!hasOnboarded && mounted) {
        // Show onboarding sheet before parsing any messages
        await TrackingOnboardingSheet.show(context);
      }

      if (!mounted) return;
      await sms.loadTransactions();
      _loadHomeCounts();
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

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.isActive && widget.isActive) ||
        oldWidget.refreshToken != widget.refreshToken) {
      _loadHomeCounts();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHomeCounts() async {
    try {
      final counts = await Future.wait<int>([
        LocalStorageService.getUnreadAlerts().then((rows) => rows.length),
        LocalStorageService.getTransactionReviews().then((rows) => rows.length),
      ]);
      if (mounted) {
        setState(() {
          _unreadAlertCount = counts[0];
          _reviewCount = counts[1];
        });
      }
    } catch (_) {
      // Keep the last known counts if the local read cannot complete.
    }
  }

  Future<void> _openAlerts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlertsScreen()),
    );
    if (mounted) await _loadHomeCounts();
  }

  Future<void> _scanMessages() async {
    await context.read<SmsService>().loadTransactions();
    if (mounted) await _loadHomeCounts();
  }

  Future<void> _openReview() async {
    if (widget.onOpenReview != null) {
      widget.onOpenReview!();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransactionReviewScreen()),
    );
    if (!mounted) return;
    await context.read<SmsService>().reloadFromCache();
    if (mounted) await _loadHomeCounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Consumer<SmsService>(
        builder: (context, sms, _) {
          if (sms.isLoading && sms.transactions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    sms.loadingStatus.isNotEmpty
                        ? sms.loadingStatus
                        : 'Reading your messages...',
                  ),
                  if (sms.cachedCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${sms.cachedCount} cached transactions loaded',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            );
          }

          if (sms.error != null && sms.transactions.isEmpty) {
            return _ErrorView(message: sms.error!, onRetry: _scanMessages);
          }

          final filtered = _getFiltered(sms);
          final recent = filtered.take(5).toList();

          return RefreshIndicator(
            onRefresh: _scanMessages,
            child: CustomScrollView(
              key: const PageStorageKey('home-scroll'),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (sms.error != null)
                  SliverToBoxAdapter(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(sms.error!),
                      trailing: TextButton(
                        onPressed: _scanMessages,
                        child: const Text('Retry'),
                      ),
                    ),
                  ),
                if (sms.isLoading)
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const LinearProgressIndicator(minHeight: 2),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(sms.loadingStatus),
                        ),
                      ],
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SummaryCard(
                    title: sms.currentCycleLabel,
                    totalIn: sms.currentCycleCredits,
                    totalOut: sms.currentCycleDebits,
                    txCount: sms.currentCycleTransactions.length,
                    subtitle: sms.currentCycleSubtitle,
                  ),
                ),
                if (_unreadAlertCount > 0 || _reviewCount > 0)
                  SliverToBoxAdapter(child: _buildAttentionShortcuts()),
                SliverToBoxAdapter(child: _buildFilterRow(sms)),
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
                            sms.currentCycleLabel,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          TextButton(
                            onPressed: () {
                              if (widget.onSeeAll != null) {
                                widget.onSeeAll!(_selectedFilter);
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AllTransactionsScreen(
                                      filter: _selectedFilter,
                                    ),
                                  ),
                                );
                              }
                            },
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
                        accountDisplayName: sms.getAccountDisplayName(
                          recent[i].accountId,
                          recent[i].accountLast4,
                        ),
                        onTap: () =>
                            TransactionDetailSheet.show(context, recent[i]),
                        onSwipeIgnore: (tx) => _handleSwipeIgnore(context, tx),
                        onSwipeToggleType: (tx) =>
                            _handleSwipeToggleType(context, tx),
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

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text(
        'Payment Tracker',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          tooltip: 'Scan messages',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _scanMessages,
        ),
        IconButton(
          tooltip: 'Alerts',
          icon: Badge(
            isLabelVisible: _unreadAlertCount > 0,
            label: Text(_unreadAlertCount > 9 ? '9+' : '$_unreadAlertCount'),
            child: const Icon(Icons.notifications_outlined),
          ),
          onPressed: _openAlerts,
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed:
              widget.onOpenSettings ??
              () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                if (!context.mounted) return;
                await context.read<SmsService>().loadTransactions();
                if (mounted) await _loadHomeCounts();
              },
        ),
      ],
    );
  }

  Widget _buildAttentionShortcuts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            if (_reviewCount > 0)
              ListTile(
                leading: const Icon(Icons.rule_folder_outlined),
                title: Text(
                  '$_reviewCount ${_reviewCount == 1 ? 'transaction needs' : 'transactions need'} review',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openReview,
              ),
            if (_reviewCount > 0 && _unreadAlertCount > 0)
              const Divider(height: 1),
            if (_unreadAlertCount > 0)
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(
                  '$_unreadAlertCount unread ${_unreadAlertCount == 1 ? 'alert' : 'alerts'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openAlerts,
              ),
          ],
        ),
      ),
    );
  }

  /// Extract unique bank/sender names from current cycle transactions
  List<String> _getUniqueBanks(SmsService sms) {
    final banks = <String>{};
    for (final tx in sms.currentCycleTransactions) {
      final name = tx.sender.trim();
      if (name.isNotEmpty) banks.add(name);
    }
    final sorted = banks.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  Widget _buildFilterRow(SmsService sms) {
    final banks = _getUniqueBanks(sms);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type filters (All / Money In / Money Out)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(_filters.length, (i) {
              final selected = i == _selectedFilter;
              return Padding(
                padding: EdgeInsets.zero,
                child: FilterChip(
                  label: Text(_filters[i]),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedFilter = i),
                ),
              );
            }),
          ),
          if (banks.length > 1) ...[
            const SizedBox(height: 8),
            // Bank filter chips (horizontal scroll)
            SizedBox(
              height: 24 + MediaQuery.textScalerOf(context).scale(24),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: const Icon(Icons.account_balance, size: 16),
                      label: const Text('All Banks'),
                      selected: _selectedBank == null,
                      onSelected: (_) => setState(() => _selectedBank = null),
                    ),
                  ),
                  ...banks.map(
                    (bank) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          bank.length > 14
                              ? '${bank.substring(0, 14)}...'
                              : bank,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _selectedBank == bank,
                        onSelected: (_) => setState(() {
                          _selectedBank = _selectedBank == bank ? null : bank;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Transaction> _getFiltered(SmsService sms) {
    // Base is current cycle transactions (salary cycle or calendar month fallback)
    List<Transaction> base = sms.currentCycleTransactions;

    // Apply bank filter
    if (_selectedBank != null) {
      base = base.where((t) => t.sender == _selectedBank).toList();
    }

    switch (_selectedFilter) {
      case 1:
        return base.where((t) => t.isCredit).toList();
      case 2:
        return base.where((t) => t.isDebit).toList();
      default:
        return base;
    }
  }

  /// Swipe right → Ignore transaction
  Future<void> _handleSwipeIgnore(BuildContext ctx, Transaction tx) async {
    await LocalStorageService.updateTransactionIgnored(tx.id, true);
    if (ctx.mounted) {
      ctx.read<SmsService>().reloadFromCache();
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: const Text('Transaction ignored'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Undo',
            textColor: Colors.white,
            onPressed: () async {
              await LocalStorageService.updateTransactionIgnored(tx.id, false);
              if (ctx.mounted) {
                ctx.read<SmsService>().reloadFromCache();
              }
            },
          ),
        ),
      );
    }
  }

  /// Swipe left → Toggle credit ↔ debit
  Future<void> _handleSwipeToggleType(BuildContext ctx, Transaction tx) async {
    final newType = tx.isCredit
        ? TransactionType.debit
        : TransactionType.credit;
    await LocalStorageService.updateTransactionType(tx.id, newType);
    if (ctx.mounted) {
      ctx.read<SmsService>().reloadFromCache();
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            'Changed to ${newType == TransactionType.credit ? 'Money In' : 'Money Out'}',
          ),
          backgroundColor: newType == TransactionType.credit
              ? Colors.green
              : Colors.red,
          action: SnackBarAction(
            label: 'Undo',
            textColor: Colors.white,
            onPressed: () async {
              await LocalStorageService.updateTransactionType(tx.id, tx.type);
              if (tx.isSalary) {
                await LocalStorageService.markAsSalary(tx.id, true);
              }
              if (ctx.mounted) {
                ctx.read<SmsService>().reloadFromCache();
              }
            },
          ),
        ),
      );
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
