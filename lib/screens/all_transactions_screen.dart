// lib/screens/all_transactions_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sms_service.dart';
import '../services/local_storage_service.dart';
import '../models/transaction.dart';
import '../models/salary_cycle.dart';
import '../models/custom_category.dart';
import '../widgets/transaction_card.dart';
import '../widgets/transaction_detail_sheet.dart';

class AllTransactionsScreen extends StatefulWidget {
  final int filter;
  const AllTransactionsScreen({super.key, this.filter = 0});

  @override
  State<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

enum SortOrder { none, ascending, descending }

class _AllTransactionsScreenState extends State<AllTransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';
  String? _selectedBank;
  TransactionCategory? _selectedCategory;
  SortOrder _sortOrder = SortOrder.none;
  List<SalaryCycle> _salaryCycles = [];
  SalaryCycle? _selectedCycle;
  bool _cyclesLoaded = false;
  List<CustomCategory> _customCategories = [];
  CustomCategory? _selectedCustomCategory;
  bool _customCategoriesLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.filter,
    );
    _loadSalaryCycles();
    _loadCustomCategories();
  }

  Future<void> _loadSalaryCycles() async {
    final cycles = await LocalStorageService.getAllSalaryCycles();
    if (mounted) {
      setState(() {
        _salaryCycles = cycles;
        // Set current cycle as default
        _selectedCycle = cycles.isEmpty
            ? null
            : cycles.firstWhere(
                (c) => c.isCurrent,
                orElse: () => cycles.first,
              );
        _cyclesLoaded = true;
      });
    }
  }

  Future<void> _loadCustomCategories() async {
    final categories = await LocalStorageService.getAllCustomCategories();
    if (mounted) {
      setState(() {
        _customCategories = categories;
        _customCategoriesLoaded = true;
      });
    }
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
        title: const Text('All Transactions',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          PopupMenuButton<SortOrder>(
            icon: Icon(
              _sortOrder == SortOrder.ascending
                  ? Icons.arrow_upward_rounded
                  : _sortOrder == SortOrder.descending
                      ? Icons.arrow_downward_rounded
                      : Icons.sort_rounded,
            ),
            tooltip: 'Sort by amount',
            onSelected: (order) {
              setState(() => _sortOrder = order);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: SortOrder.none,
                child: Row(
                  children: [
                    Icon(Icons.sort_rounded),
                    SizedBox(width: 12),
                    Text('Default (by date)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: SortOrder.ascending,
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward_rounded),
                    SizedBox(width: 12),
                    Text('Amount: Low to High'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: SortOrder.descending,
                child: Row(
                  children: [
                    Icon(Icons.arrow_downward_rounded),
                    SizedBox(width: 12),
                    Text('Amount: High to Low'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Money In'),
            Tab(text: 'Money Out'),
          ],
        ),
      ),
      body: Consumer<SmsService>(
        builder: (context, sms, _) {
          final allTxs = sms.transactions;
          final banks = _getUniqueBanks(allTxs);
          final categories = _getUniqueCategories(allTxs);

          return Column(
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

              // Bank filter chips
              if (banks.length > 1)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: const Icon(Icons.account_balance, size: 16),
                          label: const Text('All Banks'),
                          selected: _selectedBank == null,
                          onSelected: (_) =>
                              setState(() => _selectedBank = null),
                        ),
                      ),
                      ...banks.map((bank) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(bank, style: const TextStyle(fontSize: 12)),
                              selected: _selectedBank == bank,
                              onSelected: (_) => setState(() {
                                _selectedBank =
                                    _selectedBank == bank ? null : bank;
                              }),
                            ),
                          )),
                    ],
                  ),
                ),

              // Category filter chips
              if (categories.length > 1)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: const Icon(Icons.category_outlined, size: 16),
                          label: const Text('All Categories'),
                          selected: _selectedCategory == null,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = null),
                        ),
                      ),
                      ...categories.map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              avatar: Text(cat.emoji,
                                  style: const TextStyle(fontSize: 14)),
                              label: Text(cat.displayName,
                                  style: const TextStyle(fontSize: 12)),
                              selected: _selectedCategory == cat,
                              onSelected: (_) => setState(() {
                                _selectedCategory =
                                    _selectedCategory == cat ? null : cat;
                              }),
                            ),
                          )),
                    ],
                  ),
                ),

              // My Categories (Custom labels) filter chips
              if (_customCategoriesLoaded && _customCategories.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: const Icon(Icons.label_outline, size: 16),
                          label: const Text('All Labels'),
                          selected: _selectedCustomCategory == null,
                          onSelected: (_) =>
                              setState(() => _selectedCustomCategory = null),
                        ),
                      ),
                      ..._customCategories.map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              avatar: Text(cat.emoji,
                                  style: const TextStyle(fontSize: 14)),
                              label: Text(cat.name,
                                  style: const TextStyle(fontSize: 12)),
                              selected: _selectedCustomCategory == cat,
                              backgroundColor: cat.color.withValues(alpha: 0.1),
                              selectedColor: cat.color.withValues(alpha: 0.25),
                              onSelected: (_) => setState(() {
                                _selectedCustomCategory =
                                    _selectedCustomCategory == cat ? null : cat;
                              }),
                            ),
                          )),
                    ],
                  ),
                ),

              // Salary cycle filter chips
              if (_cyclesLoaded && _salaryCycles.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: const Icon(Icons.calendar_month, size: 16),
                          label: const Text('All Time'),
                          selected: _selectedCycle == null,
                          onSelected: (_) =>
                              setState(() => _selectedCycle = null),
                        ),
                      ),
                      ..._salaryCycles.map((cycle) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              avatar: cycle.isCurrent
                                  ? const Icon(Icons.circle, size: 8, color: Colors.green)
                                  : null,
                              label: Text(cycle.cycleLabel,
                                  style: const TextStyle(fontSize: 12)),
                              selected: _selectedCycle == cycle,
                              onSelected: (_) => setState(() {
                                _selectedCycle =
                                    _selectedCycle == cycle ? null : cycle;
                              }),
                            ),
                          )),
                    ],
                  ),
                ),

              // Transaction list tabs
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _TxList(
                        transactions: _filter(sms.transactions),
                        search: _search,
                        onSwipeIgnore: (tx) =>
                            _handleSwipeIgnore(context, tx),
                        onSwipeToggleType: (tx) =>
                            _handleSwipeToggleType(context, tx)),
                    _TxList(
                        transactions: _filter(sms.credits),
                        search: _search,
                        onSwipeIgnore: (tx) =>
                            _handleSwipeIgnore(context, tx),
                        onSwipeToggleType: (tx) =>
                            _handleSwipeToggleType(context, tx)),
                    _TxList(
                        transactions: _filter(sms.debits),
                        search: _search,
                        onSwipeIgnore: (tx) =>
                            _handleSwipeIgnore(context, tx),
                        onSwipeToggleType: (tx) =>
                            _handleSwipeToggleType(context, tx)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Transaction> _filter(List<Transaction> list) {
    var result = list;

    // Salary cycle filter
    if (_selectedCycle != null) {
      final start = _selectedCycle!.startDate;
      final end = _selectedCycle!.endDate ?? DateTime.now();
      result = result
          .where((t) => !t.date.isBefore(start) && !t.date.isAfter(end))
          .toList();
    }

    // Text search
    if (_search.isNotEmpty) {
      result = result.where((t) {
        return t.displayName.toLowerCase().contains(_search) ||
            (t.merchant?.toLowerCase().contains(_search) ?? false) ||
            t.sender.toLowerCase().contains(_search);
      }).toList();
    }

    // Bank filter
    if (_selectedBank != null) {
      result = result.where((t) => t.sender == _selectedBank).toList();
    }

    // Category filter
    if (_selectedCategory != null) {
      result = result.where((t) => t.category == _selectedCategory).toList();
    }

    // Custom category (My Categories) filter
    if (_selectedCustomCategory != null) {
      result = result
          .where((t) => t.customCategoryId == _selectedCustomCategory!.id)
          .toList();
    }

    // Sort by amount
    if (_sortOrder == SortOrder.ascending) {
      result.sort((a, b) => a.amount.compareTo(b.amount));
    } else if (_sortOrder == SortOrder.descending) {
      result.sort((a, b) => b.amount.compareTo(a.amount));
    }

    return result;
  }

  List<String> _getUniqueBanks(List<Transaction> txs) {
    final banks = <String>{};
    for (final tx in txs) {
      final name = tx.sender.trim();
      if (name.isNotEmpty) banks.add(name);
    }
    final sorted = banks.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  List<TransactionCategory> _getUniqueCategories(List<Transaction> txs) {
    final cats = <TransactionCategory>{};
    for (final tx in txs) {
      if (tx.category != null) cats.add(tx.category!);
    }
    final sorted = cats.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return sorted;
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
  Future<void> _handleSwipeToggleType(
      BuildContext ctx, Transaction tx) async {
    final newType =
        tx.isCredit ? TransactionType.debit : TransactionType.credit;
    final corrected = tx.copyWith(type: newType, isUserCorrected: true);
    await LocalStorageService.updateTransaction(corrected);
    if (ctx.mounted) {
      ctx.read<SmsService>().reloadFromCache();
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            'Changed to ${newType == TransactionType.credit ? 'Money In' : 'Money Out'}',
          ),
          backgroundColor:
              newType == TransactionType.credit ? Colors.green : Colors.red,
          action: SnackBarAction(
            label: 'Undo',
            textColor: Colors.white,
            onPressed: () async {
              final reverted = corrected.copyWith(
                  type: tx.type, isUserCorrected: tx.isUserCorrected);
              await LocalStorageService.updateTransaction(reverted);
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

class _TxList extends StatelessWidget {
  final List<Transaction> transactions;
  final String search;
  final Function(Transaction)? onSwipeIgnore;
  final Function(Transaction)? onSwipeToggleType;

  const _TxList({
    required this.transactions,
    required this.search,
    this.onSwipeIgnore,
    this.onSwipeToggleType,
  });

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
              search.isNotEmpty
                  ? 'No results for "$search"'
                  : 'No transactions',
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
                accountDisplayName: context.read<SmsService>().getAccountDisplayName(
                    tx.accountId, tx.accountLast4),
                onTap: () => TransactionDetailSheet.show(context, tx),
                onSwipeIgnore: onSwipeIgnore,
                onSwipeToggleType: onSwipeToggleType,
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
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
