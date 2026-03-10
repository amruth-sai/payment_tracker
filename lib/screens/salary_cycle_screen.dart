// lib/screens/salary_cycle_screen.dart

import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/salary_cycle.dart';
import '../services/local_storage_service.dart';

class SalaryCycleScreen extends StatefulWidget {
  const SalaryCycleScreen({super.key});

  @override
  State<SalaryCycleScreen> createState() => _SalaryCycleScreenState();
}

class _SalaryCycleScreenState extends State<SalaryCycleScreen> {
  List<SalaryCycle> _cycles = [];
  List<Transaction> _potentialSalaries = [];
  bool _isLoading = true;
  bool _showPotentialSalaries = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load existing salary cycles
      final cycles = await LocalStorageService.getAllSalaryCycles();
      
      // Get potential salary transactions
      final potential = await LocalStorageService.getPotentialSalaryTransactions(
        employerKeywords: ['HCA', 'HCA GLOBAL', 'SALARY', 'HCA GLOBAL SERVICES'],
        minimumAmount: 30000,  // Assume salary is at least 30k
      );

      setState(() {
        _cycles = cycles;
        _potentialSalaries = potential.take(20).toList();  // Show top 20 candidates
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salary Cycles'),
        actions: [
          if (_cycles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _regenerateCycles,
              tooltip: 'Regenerate cycles',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_cycles.isEmpty && _potentialSalaries.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          // Potential salaries section (for marking)
          if (_potentialSalaries.isNotEmpty) ...[
            _buildSectionHeader(
              'Mark Your Salary Transactions',
              subtitle: 'Tap a transaction to mark it as salary',
              trailing: TextButton(
                onPressed: () => setState(() => _showPotentialSalaries = !_showPotentialSalaries),
                child: Text(_showPotentialSalaries ? 'Hide' : 'Show'),
              ),
            ),
            if (_showPotentialSalaries)
              ..._potentialSalaries.map(_buildPotentialSalaryTile),
          ],
          
          // Existing cycles
          if (_cycles.isNotEmpty) ...[
            _buildSectionHeader(
              'Your Salary Cycles',
              subtitle: '${_cycles.length} cycles detected',
            ),
            ..._cycles.map(_buildCycleCard),
          ] else if (_potentialSalaries.isNotEmpty) ...[
            _buildSetupGuide(),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'No Salary Cycles Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We couldn\'t detect any salary transactions.\nMake sure you have credit transactions from your employer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupGuide() {
    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Setup Guide',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '1. Review the potential salary transactions above\n'
              '2. Tap on transactions that are your salary\n'
              '3. Once marked, tap "Generate Cycles" to create monthly cycles',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generateCyclesFromMarked,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate Cycles'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {String? subtitle, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildPotentialSalaryTile(Transaction tx) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tx.isSalary
              ? Colors.green.withOpacity(0.2)
              : Colors.grey.withOpacity(0.1),
          child: Icon(
            tx.isSalary ? Icons.check : Icons.attach_money,
            color: tx.isSalary ? Colors.green : Colors.grey,
          ),
        ),
        title: Text(
          tx.merchant ?? tx.sender,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${_formatDate(tx.date)} • ${tx.rawMessage.length > 50 ? '${tx.rawMessage.substring(0, 50)}...' : tx.rawMessage}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${_formatAmount(tx.amount)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            if (tx.isSalary)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'SALARY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
          ],
        ),
        onTap: () => _toggleSalaryMark(tx),
      ),
    );
  }

  Widget _buildCycleCard(SalaryCycle cycle) {
    final spentPercentage = cycle.salaryAmount > 0
        ? (cycle.totalSpent / cycle.salaryAmount * 100).clamp(0.0, 100.0)
        : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showCycleDetails(cycle),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: cycle.isCurrent
                          ? Colors.blue.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      cycle.cycleLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cycle.isCurrent ? Colors.blue : Colors.grey[700],
                      ),
                    ),
                  ),
                  if (cycle.isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${cycle.daysInCycle} days',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _CycleStatItem(
                    label: 'Salary',
                    amount: cycle.salaryAmount,
                    color: Colors.green,
                  ),
                  _CycleStatItem(
                    label: 'Spent',
                    amount: cycle.totalSpent,
                    color: Colors.red,
                  ),
                  _CycleStatItem(
                    label: 'Savings',
                    amount: cycle.savings,
                    color: cycle.savings >= 0 ? Colors.blue : Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: spentPercentage / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation(
                          spentPercentage > 80 ? Colors.red : Colors.blue,
                        ),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${spentPercentage.toStringAsFixed(0)}% spent',
                    style: TextStyle(
                      fontSize: 12,
                      color: spentPercentage > 80 ? Colors.red : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (cycle.employer != null) ...[
                const SizedBox(height: 8),
                Text(
                  'From: ${cycle.employer}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSalaryMark(Transaction tx) async {
    await LocalStorageService.markAsSalary(tx.id, !tx.isSalary);
    await _loadData();
  }

  Future<void> _generateCyclesFromMarked() async {
    setState(() => _isLoading = true);
    
    try {
      await LocalStorageService.generateSalaryCycles();
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated ${_cycles.length} salary cycles'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _regenerateCycles() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate Cycles?'),
        content: const Text('This will recreate all salary cycles based on marked transactions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _generateCyclesFromMarked();
    }
  }

  void _showCycleDetails(SalaryCycle cycle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CycleDetailSheet(
          cycle: cycle,
          scrollController: scrollController,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatAmount(double amount) {
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }
}

class _CycleStatItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _CycleStatItem({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '₹${_formatAmount(amount)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount.abs() >= 100000) {
      return '${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount.abs() >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }
}

class _CycleDetailSheet extends StatelessWidget {
  final SalaryCycle cycle;
  final ScrollController scrollController;

  const _CycleDetailSheet({
    required this.cycle,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final debits = cycle.transactions.where((t) => t.isDebit).toList();
    final credits = cycle.transactions.where((t) => t.isCredit && t.id != cycle.salaryTransactionId).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                cycle.cycleLabel,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_formatDate(cycle.startDate)} - ${cycle.endDate != null ? _formatDate(cycle.endDate!) : "Present"}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatBox(
                    label: 'Salary',
                    amount: cycle.salaryAmount,
                    color: Colors.green,
                  ),
                  _StatBox(
                    label: 'Spent',
                    amount: cycle.totalSpent,
                    color: Colors.red,
                  ),
                  _StatBox(
                    label: 'Saved',
                    amount: cycle.savings,
                    color: Colors.blue,
                    subtitle: '${cycle.savingsPercentage.toStringAsFixed(0)}%',
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  tabs: [
                    Tab(text: 'Expenses (${debits.length})'),
                    Tab(text: 'Income (${credits.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildTransactionList(debits, scrollController),
                      _buildTransactionList(credits, scrollController),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionList(List<Transaction> transactions, ScrollController controller) {
    if (transactions.isEmpty) {
      return Center(
        child: Text(
          'No transactions',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return ListView.builder(
      controller: controller,
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final tx = transactions[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: tx.isDebit
                ? Colors.red.withOpacity(0.1)
                : Colors.green.withOpacity(0.1),
            child: Icon(
              tx.isDebit ? Icons.arrow_upward : Icons.arrow_downward,
              color: tx.isDebit ? Colors.red : Colors.green,
            ),
          ),
          title: Text(tx.merchant ?? tx.sender),
          subtitle: Text(_formatDate(tx.date)),
          trailing: Text(
            '${tx.isDebit ? "-" : "+"}₹${_formatAmount(tx.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: tx.isDebit ? Colors.red : Colors.green,
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]}';
  }

  String _formatAmount(double amount) {
    if (amount.abs() >= 100000) {
      return '${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount.abs() >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final String? subtitle;

  const _StatBox({
    required this.label,
    required this.amount,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '₹${_formatAmount(amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 16,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount.abs() >= 100000) {
      return '${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount.abs() >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }
}
