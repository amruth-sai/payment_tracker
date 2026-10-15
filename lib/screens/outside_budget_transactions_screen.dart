import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_category.dart';
import '../models/transaction.dart';
import '../services/budget_service.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';
import '../widgets/transaction_detail_sheet.dart';
import 'categories_screen.dart';

enum _CoverageScope { period, allTime }

class OutsideBudgetTransactionsScreen extends StatefulWidget {
  const OutsideBudgetTransactionsScreen({
    super.key,
    required this.periodLabel,
    required this.periodStart,
    required this.periodEnd,
  });

  final String periodLabel;
  final DateTime periodStart;
  final DateTime periodEnd;

  @override
  State<OutsideBudgetTransactionsScreen> createState() =>
      _OutsideBudgetTransactionsScreenState();
}

class _OutsideBudgetTransactionsScreenState
    extends State<OutsideBudgetTransactionsScreen> {
  List<Transaction> _transactions = const [];
  Map<String, AppCategory> _categoriesById = const {};
  Set<String> _budgetCategoryIds = const {};
  _CoverageScope _scope = _CoverageScope.period;
  String _search = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final transactions = await LocalStorageService.getTrackedTransactions();
      final budgets = await LocalStorageService.getAllBudgets();
      final categories = await BudgetService.loadBudgetCategories();
      if (!mounted) return;
      setState(() {
        _transactions = transactions;
        _budgetCategoryIds = budgets.map((budget) => budget.categoryId).toSet();
        _categoriesById = categories;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load transactions.')),
      );
    }
  }

  List<Transaction> _outsideTransactions() {
    return BudgetService.outsideBudgetTransactions(
      transactions: _transactions,
      budgetCategoryIds: _budgetCategoryIds,
      start: _scope == _CoverageScope.period ? widget.periodStart : null,
      end: _scope == _CoverageScope.period ? widget.periodEnd : null,
    );
  }

  String _categoryLabel(Transaction transaction) {
    final categoryId = BudgetService.categoryIdForTransaction(transaction);
    if (categoryId == null) return 'Needs category';
    return _categoriesById[categoryId]?.name ?? 'Category not found';
  }

  Future<void> _chooseCategory(Transaction transaction) async {
    if (_saving) return;
    final available =
        _categoriesById.values
            .where(BudgetService.isBudgetableCategory)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final budgeted = available
        .where((category) => _budgetCategoryIds.contains(category.id))
        .toList();
    final other = available
        .where((category) => !_budgetCategoryIds.contains(category.id))
        .toList();

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Choose a category for this transaction'),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Manage categories'),
                    onTap: () => Navigator.pop(sheetContext, '__manage'),
                  ),
                  ListTile(
                    title: const Text('Uncategorized'),
                    onTap: () => Navigator.pop(sheetContext, ''),
                  ),
                  if (budgeted.isNotEmpty) ...[
                    const ListTile(title: Text('Categories with budgets')),
                    ...budgeted.map(
                      (category) => ListTile(
                        leading: Text(
                          category.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(category.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(sheetContext, category.id),
                      ),
                    ),
                  ],
                  if (other.isNotEmpty) ...[
                    const Divider(),
                    const ListTile(
                      title: Text('Other categories'),
                      subtitle: Text(
                        'These need a budget before spending is covered.',
                      ),
                    ),
                    ...other.map(
                      (category) => ListTile(
                        leading: Text(
                          category.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(category.name),
                        onTap: () => Navigator.pop(sheetContext, category.id),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selectedId == null || !mounted) return;
    if (selectedId == '__manage') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CategoriesScreen()),
      );
      if (mounted) await _load();
      return;
    }

    setState(() => _saving = true);
    try {
      await LocalStorageService.updateTransactionCategory(
        transaction.id,
        selectedId.isEmpty ? null : selectedId,
      );
      if (!mounted) return;
      await context.read<SmsService>().reloadFromCache();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _budgetCategoryIds.contains(selectedId)
                ? 'Transaction now counts toward that budget.'
                : 'Category updated. Add a budget to cover it.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the category.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outside = _outsideTransactions();
    final query = _search.trim().toLowerCase();
    final visible = query.isEmpty
        ? outside
        : outside.where((transaction) {
            return transaction.displayName.toLowerCase().contains(query) ||
                transaction.sender.toLowerCase().contains(query) ||
                _categoryLabel(transaction).toLowerCase().contains(query);
          }).toList();
    final total = outside.fold<double>(0, (sum, tx) => sum + tx.amount);
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      appBar: AppBar(title: const Text('Outside Budgets')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<_CoverageScope>(
                        segments: const [
                          ButtonSegment(
                            value: _CoverageScope.period,
                            label: Text('Selected period'),
                          ),
                          ButtonSegment(
                            value: _CoverageScope.allTime,
                            label: Text('All time'),
                          ),
                        ],
                        selected: {_scope},
                        onSelectionChanged: (values) =>
                            setState(() => _scope = values.first),
                      ),
                      const SizedBox(height: 12),
                      if (_scope == _CoverageScope.period) ...[
                        Text(widget.periodLabel),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        '${outside.length} spending transactions · '
                        '${currency.format(total)}',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Income, ignored transactions, and transfers are excluded. '
                        'Choose a category to organize this payment and include it in its budget.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search merchant or category',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            outside.isEmpty
                                ? _scope == _CoverageScope.period
                                      ? 'All spending in this period has a budget.'
                                      : 'All tracked spending has a budget.'
                                : 'No transactions match your search.',
                          ),
                        )
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final tx = visible[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
                                child: Column(
                                  children: [
                                    ListTile(
                                      title: Text(
                                        tx.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${DateFormat.yMMMd().format(tx.date)} · '
                                        '${_categoryLabel(tx)}',
                                      ),
                                      trailing: Text(
                                        currency.format(tx.amount),
                                      ),
                                      onTap: () => TransactionDetailSheet.show(
                                        context,
                                        tx,
                                        onUpdated: (_) => _load(),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: OutlinedButton.icon(
                                        onPressed: _saving
                                            ? null
                                            : () => _chooseCategory(tx),
                                        icon: const Icon(
                                          Icons.category_outlined,
                                        ),
                                        label: const Text('Choose category'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
