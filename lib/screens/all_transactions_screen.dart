// lib/screens/all_transactions_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sms_service.dart';
import '../services/local_storage_service.dart';
import '../services/transfer_service.dart';
import '../models/transaction.dart';
import '../models/merged_transfer.dart';
import '../models/salary_cycle.dart';
import '../models/custom_category.dart';
import '../widgets/transaction_card.dart';
import '../widgets/merged_transfer_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import '../utils/date_utils.dart';
import '../utils/format_utils.dart';

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
                        sortOrder: _sortOrder,
                        onSwipeIgnore: (tx) =>
                            _handleSwipeIgnore(context, tx),
                        onSwipeToggleType: (tx) =>
                            _handleSwipeToggleType(context, tx)),
                    _TxList(
                        transactions: _filter(sms.credits),
                        search: _search,
                        sortOrder: _sortOrder,
                        onSwipeIgnore: (tx) =>
                            _handleSwipeIgnore(context, tx),
                        onSwipeToggleType: (tx) =>
                            _handleSwipeToggleType(context, tx)),
                    _TxList(
                        transactions: _filter(sms.debits),
                        search: _search,
                        sortOrder: _sortOrder,
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
  final SortOrder sortOrder;
  final Function(Transaction)? onSwipeIgnore;
  final Function(Transaction)? onSwipeToggleType;

  const _TxList({
    required this.transactions,
    required this.search,
    required this.sortOrder,
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

    // Process transactions using existing utilities
    final mergedTransfers = TransferService.getMergedTransfers(transactions);
    final standaloneTransactions = TransferService.getStandaloneTransactions(transactions);

    // Create unified display items list
    final displayItems = <dynamic>[];
    displayItems.addAll(mergedTransfers);
    displayItems.addAll(standaloneTransactions);

    // Sort according to the specified order
    if (sortOrder != SortOrder.none) {
      displayItems.sort((a, b) {
        try {
          final double amountA = a is MergedTransfer ? a.amount : (a as Transaction).amount;
          final double amountB = b is MergedTransfer ? b.amount : (b as Transaction).amount;

          return sortOrder == SortOrder.ascending
              ? amountA.compareTo(amountB)
              : amountB.compareTo(amountA);
        } catch (e) {
          return 0; // Treat as equal if comparison fails
        }
      });
    } else {
      // Sort by date (newest first)
      displayItems.sort((a, b) {
        try {
          final DateTime dateA = a is MergedTransfer ? a.date : (a as Transaction).date;
          final DateTime dateB = b is MergedTransfer ? b.date : (b as Transaction).date;
          return dateB.compareTo(dateA);
        } catch (e) {
          return 0; // Treat as equal if comparison fails
        }
      });
    }

    final processedData = _ProcessedTransactionData(
      mergedTransfers: mergedTransfers,
      standaloneTransactions: standaloneTransactions,
      displayItems: displayItems,
    );

    // Data consistency validation
    final totalOriginalCount = transactions.length;
    final mergedTransactionCount = processedData.mergedTransfers.length * 2;
    final standaloneCount = processedData.standaloneTransactions.length;
    final totalDisplayCount = mergedTransactionCount + standaloneCount;

    // Log inconsistencies for debugging
    if (totalDisplayCount != totalOriginalCount) {
      debugPrint('⚠️  Transaction display inconsistency detected:');
      debugPrint('   Original transactions: $totalOriginalCount');
      debugPrint('   Merged transfers: ${processedData.mergedTransfers.length} (representing $mergedTransactionCount transactions)');
      debugPrint('   Standalone transactions: $standaloneCount');
      debugPrint('   Total display items: ${processedData.mergedTransfers.length + standaloneCount}');
      debugPrint('   Expected total: $totalDisplayCount vs Actual: $totalOriginalCount');

      // Identify problematic transactions
      final mergedTransactionIds = <String>{};
      for (final mt in processedData.mergedTransfers) {
        mergedTransactionIds.add(mt.sourceTransaction.id);
        mergedTransactionIds.add(mt.destinationTransaction.id);
      }
      final standaloneTransactionIds = processedData.standaloneTransactions.map((t) => t.id).toSet();

      for (final tx in transactions) {
        final inMerged = mergedTransactionIds.contains(tx.id);
        final inStandalone = standaloneTransactionIds.contains(tx.id);

        if (!inMerged && !inStandalone) {
          debugPrint('   Missing transaction: ${tx.id} (${tx.type.name}, transferGroup: ${tx.transferGroupId})');
        } else if (inMerged && inStandalone) {
          debugPrint('   Duplicate transaction: ${tx.id} appears in both merged and standalone lists');
        }
      }
    }

    // Use pre-processed display items for better performance.
    // Keep the original `displayItems` list to avoid redefining it in the same scope.

    // For amount sorting, show flat list without daily grouping
    if (sortOrder != SortOrder.none) {
      return ListView.builder(
        itemCount: displayItems.length,
        itemBuilder: (context, i) {
          try {
            final item = displayItems[i];

            if (item is MergedTransfer) {
              return MergedTransferCard(
                mergedTransfer: item,
                onTap: () => _showMergedTransferDetail(context, item),
                onSwipeUnmerge: (mergedTransfer) => _handleUnmergeTransfer(context, mergedTransfer),
                onSwipeIgnore: (mergedTransfer) => _handleIgnoreTransfer(context, mergedTransfer),
              );
            } else if (item is Transaction) {
              final tx = item;
              return TransactionCard(
                tx: tx,
                accountDisplayName: context.read<SmsService>().getAccountDisplayName(
                    tx.accountId, tx.accountLast4),
                onTap: () => TransactionDetailSheet.show(context, tx),
                onSwipeIgnore: onSwipeIgnore,
                onSwipeToggleType: onSwipeToggleType,
              );
            } else {
              // Fallback for unknown item type
              debugPrint('⚠️  Unknown item type in display list at index $i: ${item.runtimeType}');
              return Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.red, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Error: Invalid transaction data',
                  style: TextStyle(color: Colors.red),
                ),
              );
            }
          } catch (e) {
            debugPrint('⚠️  Error rendering item at index $i: $e');
            return Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                border: Border.all(color: Colors.orange, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Error displaying transaction',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Index: $i\nError: $e',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }
        },
      );
    }

    // For default sorting, group by date while preserving sort order within each day
    final grouped = <String, List<dynamic>>{};
    for (final item in displayItems) {
      try {
        final DateTime date = item is MergedTransfer ? item.date : (item as Transaction).date;
        final key = AppDateUtils.formatDateKey(date);
        grouped.putIfAbsent(key, () => []).add(item);
      } catch (e) {
        debugPrint('⚠️  Error grouping item by date: $e');
        // Skip this item if date grouping fails
      }
    }

    // Sort the date keys chronologically (newest first)
    final keys = grouped.keys.toList();
    try {
      keys.sort((a, b) {
        try {
          final dateA = AppDateUtils.parseDateKey(a);
          final dateB = AppDateUtils.parseDateKey(b);
          return dateB.compareTo(dateA);
        } catch (e) {
          debugPrint('⚠️  Error parsing date keys for sorting: $e');
          return 0; // Treat as equal if parsing fails
        }
      });
    } catch (e) {
      debugPrint('⚠️  Error sorting date keys: $e');
      // Continue with unsorted keys
    }

    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key = keys[i];
        final items = grouped[key]!;

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
            ...items.map((item) {
              try {
                if (item is MergedTransfer) {
                  return MergedTransferCard(
                    mergedTransfer: item,
                    onTap: () => _showMergedTransferDetail(context, item),
                    onSwipeUnmerge: (mergedTransfer) => _handleUnmergeTransfer(context, mergedTransfer),
                    onSwipeIgnore: (mergedTransfer) => _handleIgnoreTransfer(context, mergedTransfer),
                  );
                } else if (item is Transaction) {
                  final tx = item;
                  return TransactionCard(
                    tx: tx,
                    accountDisplayName: context.read<SmsService>().getAccountDisplayName(
                        tx.accountId, tx.accountLast4),
                    onTap: () => TransactionDetailSheet.show(context, tx),
                    onSwipeIgnore: onSwipeIgnore,
                    onSwipeToggleType: onSwipeToggleType,
                  );
                } else {
                  debugPrint('⚠️  Unknown item type in grouped display: ${item.runtimeType}');
                  return Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.red, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Error: Invalid grouped transaction data',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('⚠️  Error rendering grouped item: $e');
                return Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.orange, width: 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Error in grouped transaction',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Error: $e',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }
            }),
          ],
        );
      },
    );
  }

  void _showMergedTransferDetail(BuildContext context, MergedTransfer mergedTransfer) {
    try {
      debugPrint('🔄 Opening merged transfer detail for group: ${mergedTransfer.transferGroupId}');

      // Show a custom detail sheet for merged transfers
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _MergedTransferDetailSheet(mergedTransfer: mergedTransfer),
      ).catchError((error) {
        if (!context.mounted) return;
        debugPrint('❌ Error showing merged transfer detail sheet: $error');
        // Fallback: show simple dialog
        _showSimpleMergedTransferDialog(context, mergedTransfer);
      });
    } catch (e) {
      debugPrint('❌ Error in _showMergedTransferDetail: $e');
      // Fallback to simple dialog
      _showSimpleMergedTransferDialog(context, mergedTransfer);
    }
  }

  void _showSimpleMergedTransferDialog(BuildContext context, MergedTransfer mergedTransfer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.swap_horiz_rounded, color: Color(0xFF1976D2)),
            SizedBox(width: 8),
            Text('Transfer Details'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              FormatUtils.formatCurrency(mergedTransfer.amount),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1976D2),
              ),
            ),
            const SizedBox(height: 16),
            Text('From: ${mergedTransfer.sourceAccountName}'),
            const SizedBox(height: 8),
            Text('To: ${mergedTransfer.destinationAccountName}'),
            const SizedBox(height: 8),
            Text('Date: ${FormatUtils.formatDateTime(mergedTransfer.date)}'),
            if (mergedTransfer.note != null) ...[
              const SizedBox(height: 8),
              Text('Note: ${mergedTransfer.note}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                Navigator.of(context).pop();
                await TransferService.unmergeTransfer(mergedTransfer.sourceTransaction);
                if (context.mounted) {
                  context.read<SmsService>().reloadFromCache();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Transfer unmerged successfully'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error unmerging transfer: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Unmerge'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUnmergeTransfer(BuildContext context, MergedTransfer mergedTransfer) async {
    try {
      // Unmerge the transfer
      await TransferService.unmergeTransfer(mergedTransfer.sourceTransaction);

      if (context.mounted) {
        context.read<SmsService>().reloadFromCache();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transfer unmerged successfully'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error unmerging transfer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleIgnoreTransfer(BuildContext context, MergedTransfer mergedTransfer) async {
    try {
      // Ignore both transactions in the transfer atomically
      final updatedSource = mergedTransfer.sourceTransaction.copyWith(isIgnored: true);
      final updatedDestination = mergedTransfer.destinationTransaction.copyWith(isIgnored: true);

      // Use atomic update to ensure both transactions are updated together
      await LocalStorageService.updateTransactionsAtomic([updatedSource, updatedDestination]);

      if (context.mounted) {
        context.read<SmsService>().reloadFromCache();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transfer ignored successfully'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ignoring transfer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Detail sheet for merged transfers
class _MergedTransferDetailSheet extends StatelessWidget {
  final MergedTransfer mergedTransfer;

  const _MergedTransferDetailSheet({required this.mergedTransfer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const transferColor = Color(0xFF1976D2);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Title
                    Row(
                      children: [
                        const Icon(Icons.swap_horiz_rounded, color: transferColor, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'Transfer Details',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: transferColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Amount
                    Center(
                      child: Column(
                        children: [
                          Text(
                            FormatUtils.formatCurrency(mergedTransfer.amount),
                            style: theme.textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: transferColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: transferColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Account Transfer',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: transferColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Transfer path
                    _buildTransferPath(context),
                    const SizedBox(height: 24),

                    // Debug info (only show if there are potential issues)
                    if (_hasDebugInfo(mergedTransfer)) ...[
                      _buildDebugInfo(context, mergedTransfer),
                      const SizedBox(height: 24),
                    ],

                    // Transaction details
                    _buildTransactionDetails(
                      context,
                      'From Account',
                      mergedTransfer.sourceTransaction,
                    ),
                    const SizedBox(height: 16),
                    _buildTransactionDetails(
                      context,
                      'To Account',
                      mergedTransfer.destinationTransaction,
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    _buildActionButtons(context),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _hasDebugInfo(MergedTransfer mergedTransfer) {
    // Show debug info if there are potential data integrity issues
    return mergedTransfer.sourceTransaction.transferPartnerId != mergedTransfer.destinationTransaction.id ||
           mergedTransfer.destinationTransaction.transferPartnerId != mergedTransfer.sourceTransaction.id ||
           !mergedTransfer.sourceTransaction.isTransferSource ||
           !mergedTransfer.destinationTransaction.isTransferDestination;
  }

  Widget _buildDebugInfo(BuildContext context, MergedTransfer mergedTransfer) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Text(
                'Debug Information',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Transfer Group: ${mergedTransfer.transferGroupId}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
          Text(
            'Source ID: ${mergedTransfer.sourceTransaction.id}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
          Text(
            'Dest ID: ${mergedTransfer.destinationTransaction.id}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
          if (mergedTransfer.sourceTransaction.transferPartnerId != mergedTransfer.destinationTransaction.id)
            const Text(
              '⚠️ Source partner ID mismatch',
              style: TextStyle(color: Colors.red, fontSize: 10),
            ),
          if (mergedTransfer.destinationTransaction.transferPartnerId != mergedTransfer.sourceTransaction.id)
            const Text(
              '⚠️ Destination partner ID mismatch',
              style: TextStyle(color: Colors.red, fontSize: 10),
            ),
        ],
      ),
    );
  }

  Widget _buildTransferPath(BuildContext context) {
    final theme = Theme.of(context);
    const transferColor = Color(0xFF1976D2);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: transferColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: transferColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mergedTransfer.sourceAccountName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            color: transferColor,
            size: 24,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'To',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mergedTransfer.destinationAccountName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.end,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionDetails(BuildContext context, String title, Transaction transaction) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Date', FormatUtils.formatDateTime(transaction.date)),
            if (transaction.referenceId != null)
              _buildDetailRow('Reference ID', transaction.referenceId!),
            _buildDetailRow('Payment Method', transaction.sourceLabel),
            if (transaction.balance != null)
              _buildDetailRow('Balance', FormatUtils.formatCurrency(transaction.balance!)),
            if (transaction.note != null && transaction.note!.isNotEmpty)
              _buildDetailRow('Note', transaction.note!),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        // Primary actions row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await TransferService.unmergeTransfer(mergedTransfer.sourceTransaction);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      context.read<SmsService>().reloadFromCache();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Transfer unmerged successfully'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error unmerging transfer: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.call_split_rounded),
                label: const Text('Unmerge'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Close'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // View individual transactions row
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => _showTransaction(context, mergedTransfer.sourceTransaction, 'From Account'),
                icon: const Icon(Icons.arrow_upward, size: 16),
                label: const Text('View From', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton.icon(
                onPressed: () => _showTransaction(context, mergedTransfer.destinationTransaction, 'To Account'),
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: const Text('View To', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showTransaction(BuildContext context, Transaction transaction, String title) {
    try {
      // Close current modal first
      Navigator.of(context).pop();
      // Then show transaction details
      TransactionDetailSheet.show(context, transaction);
    } catch (e) {
      // If there's an error, show a simple dialog with transaction info
      Navigator.of(context).pop(); // Close current modal

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$title Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount: ${FormatUtils.formatCurrency(transaction.amount)}'),
              const SizedBox(height: 8),
              Text('Date: ${FormatUtils.formatDateTime(transaction.date)}'),
              const SizedBox(height: 8),
              Text('Type: ${transaction.type.name.toUpperCase()}'),
              if (transaction.merchant != null) ...[
                const SizedBox(height: 8),
                Text('Merchant: ${transaction.merchant}'),
              ],
              if (transaction.referenceId != null) ...[
                const SizedBox(height: 8),
                Text('Reference: ${transaction.referenceId}'),
              ],
              if (transaction.balance != null) ...[
                const SizedBox(height: 8),
                Text('Balance: ${FormatUtils.formatCurrency(transaction.balance!)}'),
              ],
              const SizedBox(height: 16),
              Text(
                'Error loading full details: $e',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

}

/// Helper class to store processed transaction data
class _ProcessedTransactionData {
  final List<MergedTransfer> mergedTransfers;
  final List<Transaction> standaloneTransactions;
  final List<dynamic> displayItems;

  const _ProcessedTransactionData({
    required this.mergedTransfers,
    required this.standaloneTransactions,
    required this.displayItems,
  });
}
