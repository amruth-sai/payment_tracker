import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/salary_cycle.dart';
import '../models/transaction.dart';
import '../services/local_storage_service.dart';
import '../services/salary_closeout_service.dart';

class SalaryMonthCloseoutScreen extends StatefulWidget {
  const SalaryMonthCloseoutScreen({super.key});

  @override
  State<SalaryMonthCloseoutScreen> createState() =>
      _SalaryMonthCloseoutScreenState();
}

class _SalaryMonthCloseoutScreenState extends State<SalaryMonthCloseoutScreen> {
  List<SalaryCycle> _cycles = const [];
  List<Transaction> _allTransactions = const [];
  SalaryCycle? _selectedCycle;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        LocalStorageService.getAllSalaryCycles(),
        LocalStorageService.getAllTransactions(),
      ]);
      if (!mounted) return;
      final cycles = results[0] as List<SalaryCycle>;
      final matchingSelectedCycle = _selectedCycle == null
          ? const <SalaryCycle>[]
          : cycles.where((cycle) => cycle.id == _selectedCycle!.id).toList();
      setState(() {
        _cycles = cycles;
        _allTransactions = results[1] as List<Transaction>;
        _selectedCycle = matchingSelectedCycle.isEmpty
            ? _defaultCycle(cycles)
            : matchingSelectedCycle.first;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Unable to load salary closeout data.';
      });
    }
  }

  SalaryCycle? _defaultCycle(List<SalaryCycle> cycles) {
    for (final cycle in cycles) {
      if (!cycle.isCurrent) return cycle;
    }
    return cycles.isEmpty ? null : cycles.first;
  }

  SalaryCycle? _previousCycle(SalaryCycle cycle) {
    final ordered = [..._cycles]
      ..sort((first, second) => first.startDate.compareTo(second.startDate));
    final index = ordered.indexWhere((item) => item.id == cycle.id);
    return index > 0 ? ordered[index - 1] : null;
  }

  Future<void> _chooseCycle() async {
    final cycle = await showDialog<SalaryCycle>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose Salary Month'),
        children: _cycles
            .map(
              (cycle) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, cycle),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cycle.cycleLabel),
                    const SizedBox(height: 2),
                    Text(
                      _rangeLabel(cycle),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (cycle != null && mounted) {
      setState(() => _selectedCycle = cycle);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Salary Month Closeout')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _CloseoutMessage(message: _error!, onRetry: _load)
              : _selectedCycle == null
                  ? const _CloseoutMessage(
                      message: 'Create a salary cycle before viewing a closeout.',
                    )
                  : _buildCloseout(_selectedCycle!),
    );
  }

  Widget _buildCloseout(SalaryCycle cycle) {
    final closeout = SalaryCloseoutService.build(
      cycle: cycle,
      previousCycle: _previousCycle(cycle),
      allTransactions: _allTransactions,
    );
    final savingsColor = closeout.savings >= 0 ? Colors.green : Colors.red;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OutlinedButton.icon(
          onPressed: _chooseCycle,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text('${cycle.cycleLabel}: ${_rangeLabel(cycle)}'),
        ),
        const SizedBox(height: 16),
        if (!closeout.isComplete)
          const _CloseoutNotice(
            icon: Icons.timelapse_outlined,
            text: 'This cycle is still active. Values update as new transactions arrive.',
          ),
        if (!closeout.isComplete) const SizedBox(height: 12),
        Card(
          color: savingsColor.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('Cycle Savings', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  _currency(closeout.savings),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: savingsColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_currency(closeout.income)} income minus '
                  '${_currency(closeout.spending)} spending',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _SummaryAmount(
              label: 'Income',
              amount: closeout.income,
              color: Colors.green,
              icon: Icons.south_west,
            ),
            const SizedBox(width: 8),
            _SummaryAmount(
              label: 'Spending',
              amount: closeout.spending,
              color: Colors.red,
              icon: Icons.north_east,
            ),
            const SizedBox(width: 8),
            _SummaryAmount(
              label: 'Salary',
              amount: cycle.salaryAmount,
              color: Colors.blue,
              icon: Icons.account_balance_wallet_outlined,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle(
          icon: Icons.schedule_outlined,
          title: 'Cash-Flow Timing',
          subtitle: 'How spending landed around your income',
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              _TimingRow(
                label: 'First 7 days spending',
                amount: closeout.firstWeekSpending,
              ),
              const Divider(height: 1),
              _TimingRow(
                label: 'Final 7 days spending',
                amount: closeout.lastWeekSpending,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Lowest net cash flow'),
                subtitle: Text(
                  'Reached on ${DateFormat('d MMM').format(closeout.lowestNetCashFlowDate)}',
                ),
                trailing: Text(
                  _currency(closeout.lowestNetCashFlow),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle(
          icon: Icons.swap_vert,
          title: 'Biggest Category Changes',
          subtitle: _previousCycle(cycle) == null
              ? 'Your next completed cycle will enable comparisons.'
              : 'Compared with the previous salary cycle',
        ),
        const SizedBox(height: 8),
        if (closeout.categoryChanges.isEmpty)
          const _CloseoutNotice(
            icon: Icons.pie_chart_outline,
            text: 'No category spending changes to compare yet.',
          )
        else
          Card(
            child: Column(
              children: closeout.categoryChanges
                  .take(3)
                  .map(
                    (change) => _CategoryChangeRow(
                      label: _categoryLabel(change.categoryId),
                      currentAmount: change.currentAmount,
                      difference: change.difference,
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 24),
        const _SectionTitle(
          icon: Icons.event_repeat_outlined,
          title: 'Recurring Payments',
          subtitle: 'Monthly-looking payments found in your history',
        ),
        const SizedBox(height: 8),
        if (closeout.recurringPayments.isEmpty)
          const _CloseoutNotice(
            icon: Icons.event_available_outlined,
            text: 'No recurring payments were detected for this cycle.',
          )
        else
          Card(
            child: Column(
              children: closeout.recurringPayments
                  .take(5)
                  .map(
                    (payment) => ListTile(
                      leading: const Icon(Icons.repeat),
                      title: Text(payment.merchant),
                      subtitle: Text(payment.frequencyLabel),
                      trailing: Text(
                        _currency(payment.amount),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 24),
        const _SectionTitle(
          icon: Icons.receipt_long_outlined,
          title: 'Outstanding Reimbursable',
          subtitle: 'Expenses tagged reimbursable remain here until you retag them',
        ),
        const SizedBox(height: 8),
        if (closeout.reimbursableTransactions.isEmpty)
          const _CloseoutNotice(
            icon: Icons.check_circle_outline,
            text: 'No reimbursable expenses in this cycle.',
          )
        else
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.pending_actions_outlined),
                  title: const Text('Waiting to be reimbursed'),
                  trailing: Text(
                    _currency(closeout.reimbursableAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.deepOrange,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ...closeout.reimbursableTransactions.map(
                  (transaction) => ListTile(
                    dense: true,
                    title: Text(transaction.displayName),
                    subtitle: Text(DateFormat('d MMM').format(transaction.date)),
                    trailing: Text(_currency(transaction.amount)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _rangeLabel(SalaryCycle cycle) {
    final end = cycle.endDate ?? DateTime.now();
    final formatter = DateFormat('d MMM');
    return '${formatter.format(cycle.startDate)} to ${formatter.format(end)}';
  }

  String _categoryLabel(String categoryId) {
    final category = TransactionCategory.fromStandardCategoryId(categoryId);
    if (category != null) return category.displayName;
    if (categoryId == 'uncategorized') return 'Uncategorized';
    return categoryId
        .split('_')
        .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _currency(double amount) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: 'Rs. ',
      decimalDigits: 0,
    ).format(amount);
  }
}

class _CloseoutMessage extends StatelessWidget {
  const _CloseoutMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

class _CloseoutNotice extends StatelessWidget {
  const _CloseoutNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SummaryAmount extends StatelessWidget {
  const _SummaryAmount({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
            Text(
              NumberFormat.compactCurrency(
                locale: 'en_IN',
                symbol: 'Rs. ',
                decimalDigits: 0,
              ).format(amount),
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.payments_outlined),
      title: Text(label),
      trailing: Text(
        NumberFormat.currency(
          locale: 'en_IN',
          symbol: 'Rs. ',
          decimalDigits: 0,
        ).format(amount),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CategoryChangeRow extends StatelessWidget {
  const _CategoryChangeRow({
    required this.label,
    required this.currentAmount,
    required this.difference,
  });

  final String label;
  final double currentAmount;
  final double difference;

  @override
  Widget build(BuildContext context) {
    final increased = difference > 0;
    final color = increased ? Colors.red : Colors.green;
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: 'Rs. ',
      decimalDigits: 0,
    );
    return ListTile(
      leading: Icon(
        increased ? Icons.arrow_upward : Icons.arrow_downward,
        color: color,
      ),
      title: Text(label),
      subtitle: Text('This cycle: ${formatter.format(currentAmount)}'),
      trailing: Text(
        '${increased ? '+' : '-'}${formatter.format(difference.abs())}',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}
