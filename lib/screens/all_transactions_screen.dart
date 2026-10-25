import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../models/salary_cycle.dart';
import '../models/merged_transfer.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';
import '../services/transfer_service.dart';
import '../widgets/transaction_card.dart';
import '../widgets/merged_transfer_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import '../utils/date_utils.dart';
import '../utils/format_utils.dart';
import '../utils/money.dart';
import 'transaction_window_category_screen.dart';
import 'categories_screen.dart';

class AllTransactionsScreen extends StatefulWidget {
  const AllTransactionsScreen({super.key, this.filter = 0});
  final int filter;
  @override
  State<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends State<AllTransactionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _search = '';
  final Set<String> _senders = {};
  final Set<String> _categories = {};
  final Set<String> _tags = {};
  String? _cycleId;
  String _sort = 'date';
  List<SalaryCycle> _cycles = [];
  bool _selecting = false;
  bool _assigningCategory = false;
  bool _savingCategory = false;
  final Set<String> _selectedIds = {};

  void _startSelection([Iterable<String> ids = const []]) {
    if (_assigningCategory) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _selecting = true;
      _selectedIds.addAll(ids);
    });
  }

  void _setSelected(Iterable<String> ids, bool selected) {
    if (_assigningCategory) return;
    setState(() {
      if (selected) {
        _selectedIds.addAll(ids);
      } else {
        _selectedIds.removeAll(ids);
      }
    });
  }

  void _exitSelection() => setState(() {
    _selecting = false;
    _selectedIds.clear();
  });

  Future<void> _assignCategory() async {
    if (_assigningCategory || _selectedIds.isEmpty) return;
    setState(() => _assigningCategory = true);
    var saved = false;
    final sms = context.read<SmsService>();
    try {
      final categoryId = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _BulkCategoryPicker(count: _selectedIds.length),
      );
      if (!mounted || categoryId == null) return;
      final visibleIds = _filtered(
        sms.transactions,
        _tabs.index,
      ).map((tx) => tx.id).toSet();
      final ids = _selectedIds.intersection(visibleIds);
      if (ids.isEmpty) return;
      setState(() => _savingCategory = true);
      final count = await LocalStorageService.updateTransactionCategories(
        transactionIds: ids,
        categoryId: categoryId,
      );
      saved = true;
      if (mounted) _exitSelection();
      await sms.reloadFromCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Category assigned to $count ${count == 1 ? 'transaction' : 'transactions'}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Category saved. Reopen this screen to refresh the list.'
                : 'Could not assign the category. No changes were saved. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _assigningCategory = false;
          _savingCategory = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this, initialIndex: widget.filter);
    _tabs.addListener(_tabChanged);
    _loadCycles();
  }

  Future<void> _loadCycles() async {
    try {
      final cycles = await LocalStorageService.getAllSalaryCycles();
      if (mounted) {
        setState(() {
          _cycles = cycles;
          _cycleId = cycles.where((cycle) => cycle.isCurrent).firstOrNull?.id;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load salary periods.')),
        );
      }
    }
  }

  Future<void> _edit(Transaction tx, {bool ignore = false}) async {
    try {
      if (ignore) {
        await LocalStorageService.updateTransactionIgnored(tx.id, true);
      } else {
        if (tx.isPartOfTransfer) await TransferService.unmergeTransfer(tx);
        await LocalStorageService.updateTransactionType(
          tx.id,
          tx.isCredit ? TransactionType.debit : TransactionType.credit,
        );
      }
      if (!mounted) return;
      await context.read<SmsService>().reloadFromCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ignore ? 'Transaction ignored' : 'Direction updated'),
          action: ignore
              ? SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    await LocalStorageService.updateTransactionIgnored(
                      tx.id,
                      false,
                    );
                    if (mounted) {
                      await context.read<SmsService>().reloadFromCache();
                    }
                  },
                )
              : null,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this transaction.')),
        );
      }
    }
  }

  Future<void> _openTransfer(MergedTransfer transfer) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Transfer', style: Theme.of(context).textTheme.titleLarge),
              TransactionCard(
                tx: transfer.sourceTransaction,
                onTap: () => TransactionDetailSheet.show(
                  context,
                  transfer.sourceTransaction,
                ),
              ),
              TransactionCard(
                tx: transfer.destinationTransaction,
                onTap: () => TransactionDetailSheet.show(
                  context,
                  transfer.destinationTransaction,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await TransferService.unmergeTransfer(
                    transfer.sourceTransaction,
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  if (mounted) {
                    await context.read<SmsService>().reloadFromCache();
                  }
                },
                child: const Text('Unlink transfer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _tabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    super.dispose();
  }

  List<Transaction> _filtered(
    List<Transaction> all,
    int direction, {
    bool includeSenders = true,
    bool includeCategories = true,
    bool includeTags = true,
  }) {
    final cycle = _cycles.where((cycle) => cycle.id == _cycleId).firstOrNull;
    return all.where((tx) {
      if (direction == 1 && !tx.isCredit || direction == 2 && !tx.isDebit) {
        return false;
      }
      if (includeSenders &&
          _senders.isNotEmpty &&
          !_senders.contains(tx.sender)) {
        return false;
      }
      if (includeCategories &&
          _categories.isNotEmpty &&
          !_categories.contains(tx.categoryId ?? '')) {
        return false;
      }
      if (includeTags && _tags.isNotEmpty && !_tags.contains(tx.tag)) {
        return false;
      }
      if (cycle != null && !cycle.contains(tx.date)) return false;
      final text =
          '${tx.displayName} ${tx.sender} ${tx.note ?? ''} ${tx.tag ?? ''} ${tx.amount} ${tx.referenceId ?? ''}'
              .toLowerCase();
      return text.contains(_search);
    }).toList();
  }

  List<String> _options(
    Iterable<String> values,
    Set<String> selected, {
    String Function(String)? label,
  }) {
    final result = {...values, ...selected}.toList();
    result.sort(
      (a, b) => (label?.call(a) ?? a).toLowerCase().compareTo(
        (label?.call(b) ?? b).toLowerCase(),
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final sms = context.watch<SmsService>();
    final categories = sms.categoriesById;
    final all = sms.transactions;
    final visibleIds = _filtered(all, _tabs.index).map((tx) => tx.id).toSet();
    // Keep selection scoped to the current results, including provider refreshes.
    _selectedIds.retainAll(visibleIds);
    String categoryLabel(String id) => id.isEmpty
        ? 'Uncategorized'
        : categories[id]?.name ?? 'Deleted category';
    final senders = _options(
      _filtered(all, _tabs.index, includeSenders: false).map((tx) => tx.sender),
      _senders,
    );
    final categoryIds = _options(
      _filtered(
        all,
        _tabs.index,
        includeCategories: false,
      ).map((tx) => tx.categoryId ?? ''),
      _categories,
      label: categoryLabel,
    );
    final tags = _options(
      _filtered(
        all,
        _tabs.index,
        includeTags: false,
      ).map((tx) => tx.tag).whereType<String>().where((tag) => tag.isNotEmpty),
      _tags,
    );
    return PopScope(
      canPop: !_selecting && !_assigningCategory,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_assigningCategory) _exitSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selecting
              ? IconButton(
                  tooltip: 'Exit selection',
                  onPressed: _assigningCategory ? null : _exitSelection,
                  icon: const Icon(Icons.close),
                )
              : null,
          title: Text(
            _selecting ? '${_selectedIds.length} selected' : 'All Transactions',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            if (!_selecting) ...[
              IconButton(
                tooltip: 'Manage categories',
                icon: const Icon(Icons.category_outlined),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                  );
                  if (!mounted) return;
                  setState(
                    () => _categories.removeWhere(
                      (id) =>
                          id.isNotEmpty && !sms.categoriesById.containsKey(id),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Categorize a date or transaction window',
                icon: const Icon(Icons.date_range_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TransactionWindowCategoryScreen(),
                  ),
                ),
              ),
            ],
            PopupMenuButton<String>(
              enabled: !_assigningCategory,
              tooltip: 'Sort by amount',
              icon: Icon(
                _sort == 'amount_up'
                    ? Icons.arrow_upward_rounded
                    : _sort == 'amount_down'
                    ? Icons.arrow_downward_rounded
                    : Icons.sort_rounded,
              ),
              onSelected: (value) => setState(() => _sort = value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'date', child: Text('Default (by date)')),
                PopupMenuItem(
                  value: 'amount_up',
                  child: Text('Amount: Low to High'),
                ),
                PopupMenuItem(
                  value: 'amount_down',
                  child: Text('Amount: High to Low'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Money In'),
              Tab(text: 'Money Out'),
            ],
          ),
        ),
        bottomNavigationBar: _selecting
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        key: const ValueKey('select-all-filtered'),
                        onPressed: _assigningCategory || visibleIds.isEmpty
                            ? null
                            : () => setState(() {
                                if (_selectedIds.length == visibleIds.length) {
                                  _selectedIds.clear();
                                } else {
                                  _selectedIds.addAll(visibleIds);
                                }
                              }),
                        child: Text(
                          visibleIds.isNotEmpty &&
                                  _selectedIds.length == visibleIds.length
                              ? 'Deselect all'
                              : 'Select all filtered',
                        ),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('assign-category'),
                        onPressed: _assigningCategory || _selectedIds.isEmpty
                            ? null
                            : _assignCategory,
                        icon: _savingCategory
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.category_outlined),
                        label: const Text('Assign category'),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: AbsorbPointer(
          absorbing: _assigningCategory,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SearchBar(
                  hintText: 'Search merchant, bank, amount or notes...',
                  leading: const Icon(Icons.search_rounded),
                  onChanged: (value) =>
                      setState(() => _search = value.toLowerCase().trim()),
                ),
              ),
              if (senders.isNotEmpty)
                _chipRow(
                  'banks',
                  'All Banks',
                  Icons.account_balance,
                  senders,
                  _senders,
                  (id) => id,
                ),
              if (categoryIds.isNotEmpty)
                _chipRow(
                  'categories',
                  'All Categories',
                  Icons.category_outlined,
                  categoryIds,
                  _categories,
                  categoryLabel,
                  avatar: (id) => categories[id] == null
                      ? null
                      : Text(
                          categories[id]!.emoji,
                          style: const TextStyle(fontSize: 14),
                        ),
                  color: (id) => categories[id]?.color,
                ),
              if (tags.isNotEmpty)
                _chipRow(
                  'tags',
                  'All Tags',
                  Icons.sell_outlined,
                  tags,
                  _tags,
                  (id) => id,
                ),
              if (_cycles.isNotEmpty)
                _chipStrip('periods', [
                  FilterChip(
                    avatar: const Icon(Icons.calendar_month, size: 16),
                    label: const Text('All Time'),
                    selected: _cycleId == null,
                    onSelected: (_) => setState(() => _cycleId = null),
                  ),
                  ..._cycles.map(
                    (cycle) => FilterChip(
                      key: ValueKey('period-${cycle.id}'),
                      avatar: cycle.isCurrent
                          ? const Icon(
                              Icons.circle,
                              size: 8,
                              color: Colors.green,
                            )
                          : null,
                      label: Text(
                        cycle.cycleLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: _cycleId == cycle.id,
                      onSelected: (_) => setState(
                        () => _cycleId = _cycleId == cycle.id ? null : cycle.id,
                      ),
                    ),
                  ),
                ]),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    for (var direction = 0; direction < 3; direction++)
                      _transactionList(
                        sms,
                        _filtered(all, direction),
                        direction,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filteredSummary(
    List<Transaction> transactions,
    List<MergedTransfer> allTransfers,
  ) {
    final credit = transactions.where((tx) => tx.isCredit).totalAmount;
    final debit = transactions.where((tx) => tx.isDebit).totalAmount;
    final net = Money.sum([credit, -debit]);
    final ids = transactions.map((tx) => tx.id).toSet();
    final transfers = allTransfers
        .where(
          (pair) =>
              ids.contains(pair.sourceTransaction.id) ||
              ids.contains(pair.destinationTransaction.id),
        )
        .toList();
    final internal = Money.sum(transfers.map((pair) => pair.amount));
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${transactions.length} filtered transactions'),
              ),
              TextButton.icon(
                onPressed: transactions.isEmpty || _selecting
                    ? null
                    : () => _startSelection(),
                icon: const Icon(Icons.checklist),
                label: const Text('Select'),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final tileWidth =
                  width < 340 || MediaQuery.textScalerOf(context).scale(14) > 20
                  ? width
                  : (width - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _summaryTile(
                    'filtered-credit',
                    'Total credit',
                    credit,
                    Icons.south_west,
                    colors.primary,
                    tileWidth,
                  ),
                  _summaryTile(
                    'filtered-debit',
                    'Total debit',
                    debit,
                    Icons.north_east,
                    colors.error,
                    tileWidth,
                  ),
                  _summaryTile(
                    'filtered-net',
                    'Total amount (net)',
                    net,
                    Icons.account_balance_wallet_outlined,
                    colors.onSurface,
                    tileWidth,
                  ),
                  _summaryTile(
                    'filtered-transfers',
                    'Internal transfers',
                    internal,
                    Icons.swap_horiz,
                    colors.tertiary,
                    tileWidth,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Net = credit minus debit. Internal transfers are already included in these totals.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (transfers.isNotEmpty)
            Text(
              '${transfers.length} matching merged ${transfers.length == 1 ? 'transfer' : 'transfers'}, counted once per pair.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          Text(
            _selecting
                ? 'Tap cards to select. Transfer checkboxes select debit (top) or credit (bottom).'
                : 'Long-press a transaction to select several and assign a category.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(
    String key,
    String label,
    double amount,
    IconData icon,
    Color color,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$label: ${FormatUtils.formatCurrency(amount)}',
                  key: ValueKey(key),
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipRow(
    String key,
    String title,
    IconData icon,
    List<String> options,
    Set<String> selected,
    String Function(String) label, {
    Widget? Function(String)? avatar,
    Color? Function(String)? color,
  }) => _chipStrip(key, [
    FilterChip(
      key: ValueKey('$key-all'),
      avatar: Icon(icon, size: 16),
      label: Text(title),
      selected: selected.isEmpty,
      onSelected: (_) => setState(selected.clear),
    ),
    ...options.map(
      (id) => FilterChip(
        key: ValueKey('$key-$id'),
        avatar: avatar?.call(id),
        label: Text(label(id), style: const TextStyle(fontSize: 12)),
        selected: selected.contains(id),
        backgroundColor: color?.call(id)?.withValues(alpha: 0.1),
        selectedColor: color?.call(id)?.withValues(alpha: 0.25),
        onSelected: (value) => setState(() {
          if (value) {
            selected.add(id);
          } else {
            selected.remove(id);
          }
        }),
      ),
    ),
  ]);

  Widget _chipStrip(String key, List<Widget> chips) => SizedBox(
    height: 24 + MediaQuery.textScalerOf(context).scale(18),
    child: ListView(
      key: PageStorageKey('filter-$key'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: chips
          .map(
            (chip) =>
                Padding(padding: const EdgeInsets.only(right: 8), child: chip),
          )
          .toList(),
    ),
  );

  Widget _transactionList(
    SmsService sms,
    List<Transaction> filtered,
    int direction,
  ) {
    final items = <Object>[
      ...TransferService.getMergedTransfers(filtered),
      ...TransferService.getStandaloneTransactions(filtered),
    ];
    DateTime dateOf(Object item) =>
        item is Transaction ? item.date : (item as MergedTransfer).date;
    double amountOf(Object item) =>
        item is Transaction ? item.amount : (item as MergedTransfer).amount;
    items.sort(
      (a, b) => _sort == 'date'
          ? dateOf(b).compareTo(dateOf(a))
          : _sort == 'amount_up'
          ? amountOf(a).compareTo(amountOf(b))
          : amountOf(b).compareTo(amountOf(a)),
    );
    final rows = <Object>[];
    String? lastDay;
    for (final item in items) {
      if (_sort == 'date') {
        final day = AppDateUtils.formatDateKey(dateOf(item));
        if (lastDay != day) {
          rows.add(day);
          lastDay = day;
        }
      }
      rows.add(item);
    }
    return ListView.builder(
      key: PageStorageKey('transactions-$direction'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: rows.isEmpty ? 2 : rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _filteredSummary(
            filtered,
            TransferService.getMergedTransfers(sms.transactions),
          );
        }
        if (rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No matching transactions')),
          );
        }
        final item = rows[index - 1];
        if (item is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(item, style: Theme.of(context).textTheme.labelLarge),
          );
        }
        if (item is MergedTransfer) {
          return MergedTransferCard(
            key: ValueKey('transfer-${item.transferGroupId}'),
            mergedTransfer: item,
            selectionMode: _selecting,
            sourceSelected: _selectedIds.contains(item.sourceTransaction.id),
            destinationSelected: _selectedIds.contains(
              item.destinationTransaction.id,
            ),
            onSourceSelected: (value) =>
                _setSelected([item.sourceTransaction.id], value),
            onDestinationSelected: (value) =>
                _setSelected([item.destinationTransaction.id], value),
            onLongPress: () => _startSelection([
              item.sourceTransaction.id,
              item.destinationTransaction.id,
            ]),
            onTap: _selecting
                ? () => _setSelected(
                    [item.sourceTransaction.id, item.destinationTransaction.id],
                    !(_selectedIds.contains(item.sourceTransaction.id) &&
                        _selectedIds.contains(item.destinationTransaction.id)),
                  )
                : () => _openTransfer(item),
          );
        }
        final tx = item as Transaction;
        return TransactionCard(
          key: ValueKey('transaction-${tx.id}'),
          tx: tx,
          selectionMode: _selecting,
          selected: _selectedIds.contains(tx.id),
          onSelected: (value) => _setSelected([tx.id], value),
          onLongPress: () => _startSelection([tx.id]),
          accountDisplayName: sms.getAccountDisplayName(
            tx.accountId,
            tx.accountLast4,
          ),
          onTap: () => TransactionDetailSheet.show(context, tx),
          onSwipeIgnore: (tx) => _edit(tx, ignore: true),
          onSwipeToggleType: _edit,
        );
      },
    );
  }
}

class _BulkCategoryPicker extends StatelessWidget {
  const _BulkCategoryPicker({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final categories =
        context.watch<SmsService>().categoriesById.values.toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    return FractionallySizedBox(
      heightFactor: 0.7,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Assign category to $count ${count == 1 ? 'transaction' : 'transactions'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Choose a category to replace the current category on the selected transactions.',
              ),
            ),
            Expanded(
              child: categories.isEmpty
                  ? const Center(
                      child: Text('No categories yet. Create one below.'),
                    )
                  : ListView.builder(
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        return ListTile(
                          key: ValueKey('assign-category-${category.id}'),
                          leading: Text(category.emoji),
                          title: Text(category.name),
                          onTap: () => Navigator.pop(context, category.id),
                        );
                      },
                    ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Create or manage categories'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
