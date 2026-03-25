// lib/screens/budget_screen.dart

import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../models/transaction.dart';
import '../services/budget_service.dart';
import '../services/local_storage_service.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  List<BudgetStatus> _statuses = [];
  bool _isLoading = true;
  double _monthlyIncome = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final incomeStr = await LocalStorageService.getSetting('monthly_income');
    _monthlyIncome = double.tryParse(incomeStr ?? '') ?? 0;

    final statusMap = await BudgetService.checkBudgets();
    setState(() {
      _statuses = statusMap.values.toList()
        ..sort((a, b) => b.percentage.compareTo(a.percentage));
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Budgets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI Suggestions',
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
                  if (_statuses.isEmpty) _buildEmptyState() else ..._statuses.map(_buildBudgetCard),
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
                child: const Icon(Icons.account_balance_wallet, color: Colors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Monthly Income',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      _monthlyIncome > 0
                          ? '₹${_fmt(_monthlyIncome)}'
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
          Text('No budgets set', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          const Text(
            'Add budgets manually or use AI suggestions based on your spending.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _showAISuggestions,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Get AI Suggestions'),
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
    final cat = status.budget.category;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(cat.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (status.budget.isAiSuggested)
                        const Text('AI suggested',
                            style: TextStyle(fontSize: 10, color: Colors.amber)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${_fmt(status.spent)} / ₹${_fmt(status.budget.monthlyLimit)}',
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
                  onSelected: (v) async {
                    if (v == 'edit') {
                      _showEditBudgetDialog(status.budget);
                    } else if (v == 'delete') {
                      await LocalStorageService.deleteBudget(status.budget.id);
                      _loadData();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: Colors.red))),
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
            Text(
              'Remaining: ₹${_fmt(status.remaining)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setMonthlyIncome() async {
    final controller = TextEditingController(
        text: _monthlyIncome > 0 ? _monthlyIncome.toStringAsFixed(0) : '');
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Monthly Income'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: '₹ ',
            hintText: 'e.g. 80000',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              Navigator.pop(context, val);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      await LocalStorageService.setSetting('monthly_income', result.toString());
      _loadData();
    }
  }

  Future<void> _showAISuggestions() async {
    if (_monthlyIncome <= 0) {
      await _setMonthlyIncome();
      if (_monthlyIncome <= 0) return;
    }

    final transactions = await LocalStorageService.getAllTransactions();
    final suggestions = BudgetService.suggestBudgets(
      transactions: transactions,
      monthlyIncome: _monthlyIncome,
    );

    if (!mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.amber),
            SizedBox(width: 8),
            Text('AI Budget Suggestions'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: suggestions.entries
                .where((e) => e.value > 0)
                .map((e) => ListTile(
                      leading: Text(e.key.emoji, style: const TextStyle(fontSize: 20)),
                      title: Text(e.key.displayName),
                      trailing: Text('₹${_fmt(e.value)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      dense: true,
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
        await LocalStorageService.saveBudget(Budget(
          id: 'budget_${entry.key.name}',
          category: entry.key,
          monthlyLimit: entry.value,
          isAiSuggested: true,
        ));
      }
      _loadData();
    }
  }

  Future<void> _showAddBudgetDialog() async {
    _showBudgetFormDialog(null);
  }

  Future<void> _showEditBudgetDialog(Budget budget) async {
    _showBudgetFormDialog(budget);
  }

  Future<void> _showBudgetFormDialog(Budget? existing) async {
    TransactionCategory selectedCat = existing?.category ?? TransactionCategory.foodDining;
    final limitController = TextEditingController(
        text: existing?.monthlyLimit.toStringAsFixed(0) ?? '');

    final result = await showDialog<Budget>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing != null ? 'Edit Budget' : 'Add Budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<TransactionCategory>(
                initialValue: selectedCat,
                decoration: const InputDecoration(labelText: 'Category'),
                items: TransactionCategory.values
                    .where((c) =>
                        c != TransactionCategory.salaryIncome &&
                        c != TransactionCategory.uncategorized &&
                        c != TransactionCategory.other)
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.emoji} ${c.displayName}'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedCat = v);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: limitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly Limit',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final limit = double.tryParse(limitController.text);
                if (limit == null || limit <= 0) return;
                Navigator.pop(
                  context,
                  Budget(
                    id: existing?.id ?? 'budget_${selectedCat.name}',
                    category: selectedCat,
                    monthlyLimit: limit,
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
      _loadData();
    }
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(2)}K';
    return v.toStringAsFixed(0);
  }
}
