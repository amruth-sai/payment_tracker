// lib/screens/budget_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/budget.dart';
import '../models/salary_cycle.dart';
import '../models/app_category.dart';
import '../models/transaction.dart';
import '../services/budget_service.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';
import '../utils/date_utils.dart';
import '../widgets/transaction_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import 'outside_budget_transactions_screen.dart';
import 'categories_screen.dart';
import '../utils/format_utils.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  List<BudgetStatus> _statuses = [];
  List<AppCategory> _categories = [];
  List<Transaction> _outsideBudgetTransactions = [];
  bool _isLoading = true;
  double _monthlyIncome = 0;
  SmsService? _smsService;
  List<_BudgetPeriod> _periods = [];
  _BudgetPeriod? _selectedPeriod;
  bool _periodsLoaded = false;
  bool _hasSalaryCycles = false;

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
    _refreshStatuses(
      useProviderTransactions: true,
      refreshPeriods: !_hasSalaryCycles,
    );
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final incomeStr = await LocalStorageService.getSetting('monthly_income');
    final categories = await BudgetService.loadBudgetCategories();

    _monthlyIncome = double.tryParse(incomeStr ?? '') ?? 0;
    _categories = categories.values.toList();

    await _refreshStatuses(useProviderTransactions: true, refreshPeriods: true);
  }

  Future<void> _refreshStatuses({
    required bool useProviderTransactions,
    bool refreshPeriods = false,
  }) async {
    final providerTransactions = useProviderTransactions
        ? (_smsService?.transactions ?? const <Transaction>[])
        : const <Transaction>[];
    final baseTransactions = providerTransactions.isNotEmpty
        ? providerTransactions
        : await LocalStorageService.getTrackedTransactions();

    if (refreshPeriods || !_periodsLoaded) {
      await _loadPeriods(baseTransactions: baseTransactions);
    }

    _categories = (await LocalStorageService.getAllCategories());
    final activePeriod = _activePeriod;
    final statuses = await BudgetService.checkBudgets(
      transactions: baseTransactions,
      start: activePeriod.start,
      end: activePeriod.end,
    );
    final budgets = await LocalStorageService.getAllBudgets();
    final outside = BudgetService.outsideBudgetTransactions(
      transactions: baseTransactions,
      budgetCategoryIds: budgets.map((budget) => budget.categoryId).toSet(),
      start: activePeriod.start,
      end: activePeriod.end,
    );

    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _outsideBudgetTransactions = outside;
      _isLoading = false;
    });
  }

  Map<String, AppCategory> get _categoriesById => {
    for (final category in _categories) category.id: category,
  };

  List<AppCategory> get _budgetableCategories {
    final categories =
        _categoriesById.values
            .where(BudgetService.isBudgetableCategory)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
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
            onPressed: _showSuggestions,
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
                  if (_periodsLoaded && _periods.length > 1)
                    _buildPeriodChips(),
                  if (_statuses.isEmpty)
                    _buildEmptyState()
                  else
                    ..._statuses.map(_buildBudgetCard),
                  _buildOutsideBudgetsCard(),
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

  Widget _buildPeriodChips() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _periods
            .map(
              (period) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: period.isCurrent
                      ? const Icon(Icons.circle, size: 8, color: Colors.green)
                      : null,
                  label: Text(
                    period.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _selectedPeriod?.id == period.id,
                  onSelected: (_) => _selectPeriod(period),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _selectPeriod(_BudgetPeriod period) {
    if (_selectedPeriod?.id == period.id) return;
    setState(() => _selectedPeriod = period);
    _refreshStatuses(useProviderTransactions: true);
  }

  Future<void> _loadPeriods({List<Transaction>? baseTransactions}) async {
    final cycles = await LocalStorageService.getAllSalaryCycles();
    _hasSalaryCycles = cycles.isNotEmpty;

    if (_hasSalaryCycles) {
      _periods = cycles.map(_periodFromSalaryCycle).toList();
    } else {
      final transactions =
          baseTransactions ??
          await LocalStorageService.getTrackedTransactions();
      _periods = _buildMonthlyPeriods(transactions);
    }

    _selectedPeriod = _resolveSelectedPeriod(_periods, _selectedPeriod);
    _periodsLoaded = true;
  }

  _BudgetPeriod? _resolveSelectedPeriod(
    List<_BudgetPeriod> periods,
    _BudgetPeriod? current,
  ) {
    if (periods.isEmpty) return null;

    final currentId = current?.id;
    if (currentId != null) {
      for (final period in periods) {
        if (period.id == currentId) return period;
      }
    }

    for (final period in periods) {
      if (period.isCurrent) return period;
    }

    return periods.first;
  }

  List<_BudgetPeriod> _buildMonthlyPeriods(List<Transaction> transactions) {
    final now = DateTime.now();
    final monthStarts = <String, DateTime>{};

    final currentStart = DateTime(now.year, now.month, 1);
    monthStarts[_monthKey(currentStart)] = currentStart;

    for (final tx in transactions) {
      final start = DateTime(tx.date.year, tx.date.month, 1);
      monthStarts[_monthKey(start)] = start;
    }

    final starts = monthStarts.values.toList()..sort((a, b) => b.compareTo(a));

    return starts
        .map(
          (start) => _BudgetPeriod(
            id: 'month_${_monthKey(start)}',
            label: _monthLabel(start),
            start: start,
            end: _endOfMonth(start),
            isCurrent: start.year == now.year && start.month == now.month,
            rangeLabel: _formatRange(start, _endOfMonth(start)),
          ),
        )
        .toList();
  }

  _BudgetPeriod _periodFromSalaryCycle(SalaryCycle cycle) {
    final end =
        cycle.endDate?.subtract(const Duration(milliseconds: 1)) ??
        DateTime.now();
    return _BudgetPeriod(
      id: 'cycle_${cycle.id}',
      label: cycle.cycleLabel,
      start: cycle.startDate,
      end: end,
      isCurrent: cycle.isCurrent,
      rangeLabel: _formatRange(cycle.startDate, end),
    );
  }

  _BudgetPeriod get _activePeriod =>
      _selectedPeriod ??
      (_periods.isNotEmpty ? _periods.first : _fallbackMonthlyPeriod());

  _BudgetPeriod _fallbackMonthlyPeriod() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return _BudgetPeriod(
      id: 'month_${_monthKey(start)}',
      label: _monthLabel(start),
      start: start,
      end: now,
      isCurrent: true,
      rangeLabel: _formatRange(start, now),
    );
  }

  String _monthLabel(DateTime start) {
    final month = AppDateUtils.months[start.month - 1];
    return '$month ${start.year}';
  }

  String _monthKey(DateTime start) {
    return '${start.year}_${start.month.toString().padLeft(2, '0')}';
  }

  DateTime _endOfMonth(DateTime start) {
    final nextMonth = DateTime(start.year, start.month + 1, 1);
    return nextMonth.subtract(const Duration(milliseconds: 1));
  }

  String _formatRange(DateTime start, DateTime end) {
    final startLabel = '${start.day} ${AppDateUtils.months[start.month - 1]}';
    final endLabel =
        '${end.day} ${AppDateUtils.months[end.month - 1]} ${end.year}';
    return '$startLabel - $endLabel';
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
            'Add budgets using your categories or use suggestions based on your spending.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _showSuggestions,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Get Suggestions'),
          ),
        ],
      ),
    );
  }

  Widget _buildOutsideBudgetsCard() {
    final transactions = _outsideBudgetTransactions;
    final total = transactions.fold<double>(0, (sum, tx) => sum + tx.amount);
    final categoriesById = _categoriesById;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Outside your budgets',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              transactions.isEmpty
                  ? 'No uncovered spending in ${_activePeriod.label}.'
                  : '${transactions.length} spending transactions · '
                        '\u20B9${_fmt(total)} in ${_activePeriod.label}',
            ),
            if (transactions.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...transactions.take(3).map((tx) {
                final categoryId = BudgetService.categoryIdForTransaction(tx);
                final category = categoriesById[categoryId];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    tx.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    categoryId == null
                        ? 'Needs category'
                        : category?.name ?? 'Category not found',
                  ),
                  trailing: Text('\u20B9${_fmt(tx.amount)}'),
                );
              }),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _showOutsideBudgetTransactions,
              icon: const Icon(Icons.rule_folder_outlined),
              label: const Text('View and categorize transactions'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOutsideBudgetTransactions() async {
    final period = _activePeriod;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OutsideBudgetTransactionsScreen(
          periodLabel: period.label,
          periodStart: period.start,
          periodEnd: period.end,
        ),
      ),
    );
    if (mounted) await _loadData();
  }

  Widget _buildBudgetCard(BudgetStatus status) {
    final color = status.isOverBudget
        ? Colors.red
        : status.isWarning
        ? Colors.orange
        : Colors.green;
    final category = status.category;

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
                          category.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (status.budget.isSuggested)
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
                          status.budget.id,
                        );
                        await _loadData();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
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
    final period = _activePeriod;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _BudgetCategoryTransactionsSheet(status: status, period: period),
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

  Future<void> _showSuggestions() async {
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
    final categoriesById = _categoriesById;

    if (!mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.savings_outlined, color: Colors.amber),
            SizedBox(width: 8),
            Text('Budget Suggestions'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: suggestions.entries.where((entry) => entry.value > 0).map(
              (entry) {
                final category = categoriesById[entry.key];
                if (category == null ||
                    !BudgetService.isBudgetableCategory(category)) {
                  return const SizedBox.shrink();
                }
                return ListTile(
                  leading: Text(
                    category.emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                  title: Text(category.name),
                  trailing: Text(
                    '\u20B9${_fmt(entry.value)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  dense: true,
                );
              },
            ).toList(),
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
        if (category == null || !BudgetService.isBudgetableCategory(category)) {
          continue;
        }
        await LocalStorageService.saveBudget(
          Budget(
            id: 'budget_${entry.key}',
            categoryId: entry.key,
            monthlyLimit: entry.value,
            isSuggested: true,
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
    if (_budgetableCategories.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CategoriesScreen()),
      );
      if (!mounted) return;
      await _loadData();
      if (!mounted || _budgetableCategories.isEmpty) return;
    }

    final budgeted = _statuses.map((s) => s.budget.categoryId).toSet();
    final availableCategories = _budgetableCategories
        .where((c) => c.id == existing?.categoryId || !budgeted.contains(c.id))
        .toList();
    if (availableCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Every category already has a budget. Edit a budget or create a category.',
          ),
        ),
      );
      return;
    }
    if (existing != null) {
      final existingCategory = _categoriesById[existing.categoryId];
      if (existingCategory != null &&
          !availableCategories.any((c) => c.id == existingCategory.id)) {
        availableCategories.add(existingCategory);
        availableCategories.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      }
    }

    String selectedCategoryId =
        existing?.categoryId ?? availableCategories.first.id;
    final limitController = TextEditingController(
      text: existing?.monthlyLimit.toStringAsFixed(2) ?? '',
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
                        child: Text('${category.emoji} ${category.name}'),
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
                if (limit == null || !limit.isFinite || limit < 0.01) return;
                Navigator.pop(
                  context,
                  Budget(
                    id: existing?.id ?? 'budget_$selectedCategoryId',
                    categoryId: selectedCategoryId,
                    monthlyLimit: limit,
                    isSuggested: existing?.isSuggested ?? false,
                    createdAt: existing?.createdAt ?? DateTime.now(),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    limitController.dispose();
    if (result != null && mounted) {
      try {
        await LocalStorageService.saveBudget(result);
        if (mounted) await _loadData();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not save budget. Each category can have one budget.',
              ),
            ),
          );
        }
      }
    }
  }

  String _fmt(double value) => FormatUtils.formatAmount(value);
}

class _BudgetPeriod {
  final String id;
  final String label;
  final DateTime start;
  final DateTime end;
  final bool isCurrent;
  final String rangeLabel;

  const _BudgetPeriod({
    required this.id,
    required this.label,
    required this.start,
    required this.end,
    required this.isCurrent,
    required this.rangeLabel,
  });
}

class _BudgetCategoryTransactionsSheet extends StatefulWidget {
  final BudgetStatus status;
  final _BudgetPeriod period;

  const _BudgetCategoryTransactionsSheet({
    required this.status,
    required this.period,
  });

  @override
  State<_BudgetCategoryTransactionsSheet> createState() =>
      _BudgetCategoryTransactionsSheetState();
}

class _BudgetCategoryTransactionsSheetState
    extends State<_BudgetCategoryTransactionsSheet> {
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  SmsService? _smsService;

  AppCategory get _category => widget.status.category;
  String get _categoryId => widget.status.budget.categoryId;

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

  Future<void> _refreshTransactions({
    required bool useProviderTransactions,
  }) async {
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
    List<Transaction> transactions,
  ) {
    final start = widget.period.start;
    final end = widget.period.end;
    return transactions
        .where((tx) => !tx.date.isBefore(start) && !tx.date.isAfter(end))
        .where(BudgetService.isBudgetExpense)
        .where((tx) {
          final categoryId = BudgetService.categoryIdForTransaction(tx);
          return categoryId == _categoryId;
        })
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  double get _totalSpent => _transactions.totalAmount;

  String _fmt(double value) => FormatUtils.formatAmount(value);

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
                          _category.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Transactions counted in ${widget.period.label} budget',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (widget.period.rangeLabel.isNotEmpty)
                          Text(
                            widget.period.rangeLabel,
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
                        value: _isLoading
                            ? '...'
                            : '\u20B9${_fmt(_totalSpent)}',
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
                              'No transactions counted for this category in this period.',
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
                          accountDisplayName: _smsService
                              ?.getAccountDisplayName(
                                tx.accountId,
                                tx.accountLast4,
                              ),
                          categoryLabel: _category.name,
                          categoryColor: _category.color,
                          onTap: () => TransactionDetailSheet.show(context, tx),
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

  const _SummaryStat({required this.label, required this.value});

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
