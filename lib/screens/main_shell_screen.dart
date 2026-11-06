import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sms_service.dart';
import '../widgets/navigation_hub.dart';
import 'accounts_screen.dart';
import 'all_transactions_screen.dart';
import 'budget_screen.dart';
import 'categories_screen.dart';
import 'category_breakdown_screen.dart';
import 'emi_tracker_screen.dart';
import 'home_screen.dart';
import 'ignored_messages_screen.dart';
import 'ignored_transactions_screen.dart';
import 'import_message_screen.dart';
import 'merchant_rankings_screen.dart';
import 'salary_cycle_screen.dart';
import 'settings_screen.dart';
import 'spending_breakdown_screen.dart';
import 'spending_heatmap_screen.dart';
import 'transaction_review_screen.dart';
import 'transfer_management_screen.dart';

enum _ReturnRefresh { none, cache, scan }

/// Keeps visited primary destinations alive; detail routes use the root Navigator.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});
  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _index = 0;
  int _homeRefreshToken = 0;
  int _activityFilter = 0;
  int _activityFilterRequest = 0;
  final _visited = <int>{0};

  void _select(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  void _seeAll(int direction) {
    setState(() {
      _activityFilter = direction;
      _activityFilterRequest++;
    });
    _select(1);
  }

  Future<void> _open(
    Widget screen, {
    _ReturnRefresh refresh = _ReturnRefresh.none,
  }) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (!mounted) return;
    final sms = context.read<SmsService>();
    if (refresh == _ReturnRefresh.cache) await sms.reloadFromCache();
    if (refresh == _ReturnRefresh.scan) await sms.loadTransactions();
    if (mounted) setState(() => _homeRefreshToken++);
  }

  void _settings() =>
      _open(const SettingsScreen(), refresh: _ReturnRefresh.scan);
  void _review() =>
      _open(const TransactionReviewScreen(), refresh: _ReturnRefresh.cache);

  Widget _activityTools(
    VoidCallback manageCategories,
    VoidCallback categorizeWindow,
  ) {
    return PopupMenuButton<String>(
      tooltip: 'Activity tools',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'review':
            _review();
          case 'ignored':
            _open(const IgnoredTransactionsScreen());
          case 'messages':
            _open(const IgnoredMessagesScreen());
          case 'transfers':
            _open(const TransferManagementScreen());
          case 'paste':
            _open(const ImportMessageScreen());
          case 'categories':
            manageCategories();
          case 'window':
            categorizeWindow();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'review', child: Text('Review Inbox')),
        PopupMenuItem(value: 'ignored', child: Text('Ignored Transactions')),
        PopupMenuItem(
          value: 'messages',
          child: Text('Skipped / Ignored Messages'),
        ),
        PopupMenuItem(value: 'transfers', child: Text('Transfer Management')),
        PopupMenuItem(value: 'paste', child: Text('Paste Payment Message')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'categories', child: Text('Manage categories')),
        PopupMenuItem(
          value: 'window',
          child: Text('Categorize a date or transaction window'),
        ),
      ],
    );
  }

  Widget _insights() => NavigationHub(
    title: 'Insights',
    description: 'Understand where your money goes.',
    onOpenSettings: _settings,
    sections: [
      HubSection('Spending reports', [
        HubLink(
          id: 'spending',
          title: 'Spending Breakdown',
          subtitle: 'Explore spending by account and payment source.',
          icon: Icons.donut_large_outlined,
          onTap: () => _open(const SpendingBreakdownScreen()),
        ),
        HubLink(
          id: 'category-breakdown',
          title: 'Category Breakdown',
          subtitle: 'Compare spending across your categories.',
          icon: Icons.category_outlined,
          onTap: () => _open(const CategoryBreakdownScreen()),
        ),
        HubLink(
          id: 'heatmap',
          title: 'Spending Heatmap',
          subtitle: 'See daily spending patterns on the calendar.',
          icon: Icons.calendar_view_month_outlined,
          onTap: () => _open(const SpendingHeatmapScreen()),
        ),
        HubLink(
          id: 'merchants',
          title: 'Merchant Rankings',
          subtitle: 'See the merchants you spend with most.',
          icon: Icons.storefront_outlined,
          onTap: () => _open(const MerchantRankingsScreen()),
        ),
      ]),
    ],
  );

  Widget _plan() => NavigationHub(
    title: 'Plan',
    description: 'Manage your accounts, budgets and commitments.',
    onOpenSettings: _settings,
    sections: [
      HubSection('Accounts and income', [
        HubLink(
          id: 'accounts',
          title: 'Accounts',
          subtitle: 'Manage accounts and their sender mappings.',
          icon: Icons.account_balance_outlined,
          onTap: () => _open(const AccountsScreen()),
        ),
        HubLink(
          id: 'salary',
          title: 'Salary Cycles',
          subtitle: 'Review salary periods and month closeouts.',
          icon: Icons.calendar_month_outlined,
          onTap: () =>
              _open(const SalaryCycleScreen(), refresh: _ReturnRefresh.cache),
        ),
      ]),
      HubSection('Budgets and commitments', [
        HubLink(
          id: 'budgets',
          title: 'Budgets',
          subtitle: 'Track category budgets and net spending.',
          icon: Icons.savings_outlined,
          onTap: () => _open(const BudgetScreen()),
        ),
        HubLink(
          id: 'emis',
          title: 'EMI Tracker',
          subtitle: 'Review detected recurring instalments.',
          icon: Icons.event_repeat_outlined,
          onTap: () => _open(const EMITrackerScreen()),
        ),
      ]),
      HubSection('Organization', [
        HubLink(
          id: 'categories',
          title: 'Categories',
          subtitle: 'Create and edit your category names, emojis and colors.',
          icon: Icons.label_outline,
          onTap: () => _open(const CategoriesScreen()),
        ),
      ]),
    ],
  );

  Widget _page(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => HomeScreen(
        key: const ValueKey('home-tab'),
        isActive: _index == 0,
        refreshToken: _homeRefreshToken,
        onSeeAll: _seeAll,
        onOpenSettings: _settings,
        onOpenReview: _review,
      ),
      1 => AllTransactionsScreen(
        key: const ValueKey('activity-tab'),
        filter: _activityFilter,
        filterRequest: _activityFilterRequest,
        refreshToken: _homeRefreshToken,
        isActive: _index == 1,
        onBackToHome: () => _select(0),
        toolsMenuBuilder: _activityTools,
        settingsAction: IconButton(
          tooltip: 'Settings',
          onPressed: _settings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ),
      2 => _insights(),
      _ => _plan(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0 || _index == 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && (_index == 2 || _index == 3)) _select(0);
      },
      child: Scaffold(
        // Feature Scaffolds handle keyboard insets once, within the shell.
        resizeToAvoidBottomInset: false,
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < 4; i++)
              TickerMode(enabled: _index == i, child: _page(i)),
          ],
        ),
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: const [
                  NavigationDestination(
                    key: ValueKey('tab-home'),
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    key: ValueKey('tab-activity'),
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: 'Activity',
                  ),
                  NavigationDestination(
                    key: ValueKey('tab-insights'),
                    icon: Icon(Icons.bar_chart_outlined),
                    selectedIcon: Icon(Icons.bar_chart),
                    label: 'Insights',
                  ),
                  NavigationDestination(
                    key: ValueKey('tab-plan'),
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    selectedIcon: Icon(Icons.account_balance_wallet),
                    label: 'Plan',
                  ),
                ],
              ),
      ),
    );
  }
}
