// lib/screens/budget_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/budget.dart';
import '../models/standard_category.dart';
import '../models/transaction.dart';
import '../services/budget_service.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';
import '../widgets/transaction_card.dart';
import '../widgets/transaction_detail_sheet.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  List<BudgetStatus> _statuses = [];
  List<StandardCategory> _standardCategories = [];
  bool _isLoading = true;
  double _monthlyIncome = 0;
  SmsService? _smsService;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final smsService = context.read<SmsService>();
    if (_smsService == smsService) return;

    _smsService?.removeListener(_handleTransactionsChanged);
    _smsService = smsService;
    _smsService?.addListener(_handleTransactionsChanged);
  }

  @override
  void dispose() {
    _smsService?.removeListener(_handleTransactionsChanged);
    super.dispose();
  }

  void _handleTransactionsChanged() {
    if (!mounted) return;
    _refreshStatuses(useProviderTransactions: true);
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final incomeStr = await LocalStorageService.getSetting('monthly_income');
    final categories = await LocalStorageService.getAllStandardCategories();

    _monthlyIncome = double.tryParse(incomeStr ?? '') ?? 0;
    _standardCategories = categories;

    await _refreshStatuses(useProviderTransactions: true);
  }

  Future<void> _refreshStatuses({required bool useProviderTransactions}) async {
    final providerTransactions = useProviderTransactions
        ? (_smsService?.transactions ?? const <Transaction>[])
        : const <Transaction>[];
    final fallbackTransactions = providerTransactions.isNotEmpty
        ? providerTransactions
        : await LocalStorageService.getTrackedTransactions();

    final statuses =
        await BudgetService.checkBudgets(transactions: fallbackTransactions);

    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _isLoading = false;
    });
  }

  Map<String, StandardCategory> get _standardCategoriesById => {
        for (final category in StandardCategory.defaultCategories)
          category.id: category,
        for (final category in _standardCategories) category.id: category,
      };

  List<StandardCategory> get _budgetableCategories {
    final categories = _standardCategoriesById.values
        .where((category) => category.isActive)
        .where(BudgetService.isBudgetableCategory)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return categories;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Budgets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Spending Suggestions',
            onPressed: _showAISuggestions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 80),
                children: [
                  _buildIncomeCard(),
                  if (_statuses.isEmpty)
                    _buildEmptyState()
                  else
                    ..._statuses.map(_buildBudgetCard),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddBudgetDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Budget'),
      ),
    );
  }

  Widget _buildIncomeCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: InkWell(
        onTap: _setMonthlyIncome,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.green.withValues(alpha: 0.2),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monthly Income',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      _monthlyIncome > 0
                          ? '\u20B9${_fmt(_monthlyIncome)}'
                          : 'Tap to set income',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _monthlyIncome > 0 ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.pie_chart_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No budgets set',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add budgets using your standard categories or use suggestions based on your spending.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _showAISuggestions,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Get Suggestions'),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetCard(BudgetStatus status) {
    final color = status.isOverBudget
        ? Colors.red
        : status.isWarning
            ? Colors.orange
            : Colors.green;
    final category = status.standardCategory;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showCategoryTransactions(status),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(category.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (status.budget.isAiSuggested)
                          const Text(
                            'Suggested from recent spending',
                            style: TextStyle(fontSize: 10, color: Colors.amber),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\u20B9${_fmt(status.spent)} / \u20B9${_fmt(status.budget.monthlyLimit)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        '${status.percentage.toStringAsFixed(0)}% used',
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    ],
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        _showEditBudgetDialog(status.budget);
                      } else if (value == 'delete') {
                        await LocalStorageService.deleteBudget(
                            status.budget.id);
                        await _loadData();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'delete',
                        child:
                            Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (status.percentage / 100).clamp(0, 1),
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Remaining: \u20B9${_fmt(status.remaining)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                  Text(
                    'Tap to view transactions',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCategoryTransactions(BudgetStatus status) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetCategoryTransactionsSheet(status: status),
    );
  }

  Future<void> _setMonthlyIncome() async {
    final controller = TextEditingController(
      text: _monthlyIncome > 0 ? _monthlyIncome.toStringAsFixed(0) : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Monthly Income'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: '\u20B9 ',
            hintText: 'e.g. 80000',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result > 0) {
      await LocalStorageService.setSetting('monthly_income', result.toString());
      await _loadData();
    }
  }

  Future<void> _showAISuggestions() async {
    if (_monthlyIncome <= 0) {
      await _setMonthlyIncome();
      if (_monthlyIncome <= 0) return;
    }

    final transactions = _smsService?.transactions.isNotEmpty == true
        ? _smsService!.transactions
        : await LocalStorageService.getTrackedTransactions();
    final suggestions = await BudgetService.suggestBudgets(
      transactions: transactions,
      monthlyIncome: _monthlyIncome,
    );
    final categoriesById = _standardCategoriesById;

    if (!mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.amber),
            SizedBox(width: 8),
            Text('Budget Suggestions'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: suggestions.entries
                .where((entry) => entry.value > 0)
                .map((entry) {
              final category = categoriesById[entry.key];
              if (category == null ||
                  !category.isActive ||
                  !BudgetService.isBudgetableCategory(category)) {
                return const SizedBox.shrink();
              }
              return ListTile(
                leading:
                    Text(category.emoji, style: const TextStyle(fontSize: 20)),
                title: Text(category.displayName),
                trailing: Text(
                  '\u20B9${_fmt(entry.value)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                dense: true,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply All'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      await LocalStorageService.clearBudgets();
      for (final entry in suggestions.entries) {
        if (entry.value <= 0) continue;
        final category = categoriesById[entry.key];
        if (category == null ||
            !category.isActive ||
            !BudgetService.isBudgetableCategory(category)) {
          continue;
        }
        await LocalStorageService.saveBudget(
          Budget(
            id: 'budget_${entry.key}',
            standardCategoryId: entry.key,
            monthlyLimit: entry.value,
            isAiSuggested: true,
          ),
        );
      }
      await _loadData();
    }
  }

  Future<void> _showAddBudgetDialog() async {
    await _showBudgetFormDialog(null);
  }

  Future<void> _showEditBudgetDialog(Budget budget) async {
    await _showBudgetFormDialog(budget);
  }

  Future<void> _showBudgetFormDialog(Budget? existing) async {
    if (_budgetableCategories.isEmpty) return;

    final availableCategories = [..._budgetableCategories];
    if (existing != null) {
      final existingCategory =
          _standardCategoriesById[existing.standardCategoryId];
      if (existingCategory != null &&
          !availableCategories.any((c) => c.id == existingCategory.id)) {
        availableCategories.add(existingCategory);
        availableCategories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
    }

    String selectedCategoryId =
        existing?.standardCategoryId ?? availableCategories.first.id;
    final limitController = TextEditingController(
      text: existing?.monthlyLimit.toStringAsFixed(0) ?? '',
    );

    final result = await showDialog<Budget>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing != null ? 'Edit Budget' : 'Add Budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: availableCategories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child:
                            Text('${category.emoji} ${category.displayName}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedCategoryId = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: limitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly Limit',
                  prefixText: '\u20B9 ',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final limit = double.tryParse(limitController.text);
                if (limit == null || limit <= 0) return;
                Navigator.pop(
                  context,
                  Budget(
                    id: existing?.id ?? 'budget_$selectedCategoryId',
                    standardCategoryId: selectedCategoryId,
                    monthlyLimit: limit,
                    isAiSuggested: existing?.isAiSuggested ?? false,
                    createdAt: existing?.createdAt,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await LocalStorageService.saveBudget(result);
      await _loadData();
    }
  }

  String _fmt(double value) {
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(2)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(2)}K';
    return value.toStringAsFixed(0);
  }
}

class _BudgetCategoryTransactionsSheet extends StatefulWidget {
  final BudgetStatus status;

  const _BudgetCategoryTransactionsSheet({required this.status});

  @override
  State<_BudgetCategoryTransactionsSheet> createState() =>
      _BudgetCategoryTransactionsSheetState();
}

class _BudgetCategoryTransactionsSheetState
    extends State<_BudgetCategoryTransactionsSheet> {
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  SmsService? _smsService;

  StandardCategory get _category => widget.status.standardCategory;
  String get _categoryId => widget.status.budget.standardCategoryId;

  @override
  void initState() {
    super.initState();
    _refreshTransactions(useProviderTransactions: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final smsService = context.read<SmsService>();
    if (_smsService == smsService) return;

    _smsService?.removeListener(_handleTransactionsChanged);
    _smsService = smsService;
    _smsService?.addListener(_handleTransactionsChanged);
    _refreshTransactions(useProviderTransactions: true);
  }

  @override
  void dispose() {
    _smsService?.removeListener(_handleTransactionsChanged);
    super.dispose();
  }

  void _handleTransactionsChanged() {
    if (!mounted) return;
    _refreshTransactions(useProviderTransactions: true);
  }

  Future<void> _refreshTransactions(
      {required bool useProviderTransactions}) async {
    final providerTransactions = useProviderTransactions
        ? (_smsService?.transactions ?? const <Transaction>[])
        : const <Transaction>[];
    final baseTransactions = providerTransactions.isNotEmpty
        ? providerTransactions
        : await LocalStorageService.getTrackedTransactions();

    final includedTransactions = _filterIncludedTransactions(baseTransactions);

    if (!mounted) return;
    setState(() {
      _transactions = includedTransactions;
      _isLoading = false;
    });
  }

  List<Transaction> _filterIncludedTransactions(
      List<Transaction> transactions) {
    final now = DateTime.now();
    return transactions
        .where((tx) => tx.date.year == now.year && tx.date.month == now.month)
        .where((tx) => tx.isDebit)
        .where((tx) {
      final categoryId = tx.effectiveStandardCategoryId ??
          TransactionCategory.uncategorized.standardCategoryId;
      return categoryId == _categoryId;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  double get _totalSpent =>
      _transactions.fold(0.0, (sum, tx) => sum + tx.amount);

  String _fmt(double value) {
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(2)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(2)}K';
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _category.color.withValues(alpha: 0.14),
                    foregroundColor: _category.color,
                    child: Text(_category.emoji),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _category.displayName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Transactions counted in this month\'s budget',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryStat(
                        label: 'Transactions',
                        value: _isLoading
                            ? '...'
                            : _transactions.length.toString(),
                      ),
                    ),
                    Expanded(
                      child: _SummaryStat(
                        label: 'Spent',
                        value:
                            _isLoading ? '...' : '\u20B9${_fmt(_totalSpent)}',
                      ),
                    ),
                    Expanded(
                      child: _SummaryStat(
                        label: 'Budget',
                        value:
                            '\u20B9${_fmt(widget.status.budget.monthlyLimit)}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _transactions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 48,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No transactions counted for this category this month.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.only(top: 8, bottom: 24),
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final tx = _transactions[index];
                            return TransactionCard(
                              tx: tx,
                              accountDisplayName:
                                  _smsService?.getAccountDisplayName(
                                      tx.accountId, tx.accountLast4),
                              standardCategoryLabel: _category.displayName,
                              standardCategoryColor: _category.color,
                              onTap: () =>
                                  TransactionDetailSheet.show(context, tx),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
