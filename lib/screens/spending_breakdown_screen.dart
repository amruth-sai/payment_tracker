// lib/screens/spending_breakdown_screen.dart

import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../services/local_storage_service.dart';

class SpendingBreakdownScreen extends StatefulWidget {
  const SpendingBreakdownScreen({super.key});

  @override
  State<SpendingBreakdownScreen> createState() =>
      _SpendingBreakdownScreenState();
}

class _SpendingBreakdownScreenState extends State<SpendingBreakdownScreen> {
  List<Transaction> _transactions = [];
  Map<String, _AccountStats> _stats = {};
  bool _isLoading = true;
  String _selectedPeriod = 'all';

  final _periods = {
    'all': 'All Time',
    '7d': 'Last 7 Days',
    '30d': 'Last 30 Days',
    '90d': 'Last 90 Days',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final accounts = await LocalStorageService.getAllAccounts();
    final transactions = await LocalStorageService.getAllTransactions();

    // Calculate stats per account
    final stats = <String, _AccountStats>{};

    for (final tx in transactions) {
      if (!_isInPeriod(tx.date)) continue;

      final key = tx.accountLast4 ?? tx.sender;

      stats.putIfAbsent(
          key,
          () => _AccountStats(
                key: key,
                account: accounts.firstWhere(
                  (a) => a.last4Digits == tx.accountLast4,
                  orElse: () => Account(
                    id: 'unknown_$key',
                    name: tx.sender,
                    type: _guessAccountType(tx),
                  ),
                ),
              ));

      if (tx.type == TransactionType.debit) {
        stats[key]!.totalSpent += tx.amount;
        stats[key]!.debitCount++;
      } else if (tx.type == TransactionType.credit) {
        stats[key]!.totalReceived += tx.amount;
        stats[key]!.creditCount++;
      }
    }

    setState(() {
      _transactions = transactions;
      _stats = stats;
      _isLoading = false;
    });
  }

  bool _isInPeriod(DateTime date) {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case '7d':
        return date.isAfter(now.subtract(const Duration(days: 7)));
      case '30d':
        return date.isAfter(now.subtract(const Duration(days: 30)));
      case '90d':
        return date.isAfter(now.subtract(const Duration(days: 90)));
      default:
        return true;
    }
  }

  AccountType _guessAccountType(Transaction tx) {
    if (tx.source == PaymentSource.card) return AccountType.creditCard;
    if (tx.source == PaymentSource.wallet) return AccountType.wallet;
    if (tx.source == PaymentSource.upi) return AccountType.upi;
    return AccountType.bankAccount;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending Breakdown'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildPeriodSelector(),
                _buildSummaryCard(),
                Expanded(child: _buildBreakdownList()),
              ],
            ),
    );
  }

  Widget _buildPeriodSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _periods.entries.map((entry) {
          final selected = entry.key == _selectedPeriod;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.value),
              selected: selected,
              onSelected: (_) {
                setState(() => _selectedPeriod = entry.key);
                _loadData();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final totalSpent = _stats.values.fold(0.0, (sum, s) => sum + s.totalSpent);
    final totalReceived =
        _stats.values.fold(0.0, (sum, s) => sum + s.totalReceived);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                label: 'Total Spent',
                amount: totalSpent,
                color: Colors.red,
                icon: Icons.arrow_upward,
              ),
            ),
            Container(
              width: 1,
              height: 50,
              color: Colors.grey[300],
            ),
            Expanded(
              child: _SummaryItem(
                label: 'Total Received',
                amount: totalReceived,
                color: Colors.green,
                icon: Icons.arrow_downward,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownList() {
    final sortedStats = _stats.values.toList()
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

    if (sortedStats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No transactions found',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final maxSpent = sortedStats.first.totalSpent;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: sortedStats.length,
      itemBuilder: (context, index) {
        final stat = sortedStats[index];
        return _buildAccountCard(stat, maxSpent);
      },
    );
  }

  Widget _buildAccountCard(_AccountStats stat, double maxSpent) {
    final progress = maxSpent > 0 ? stat.totalSpent / maxSpent : 0.0;
    final account = stat.account;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => _showAccountTransactions(stat),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        _getAccountColor(account.type).withValues(alpha: 0.2),
                    child: Icon(
                      _getAccountIcon(account.type),
                      color: _getAccountColor(account.type),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        if (account.last4Digits != null)
                          Text(
                            '••••${account.last4Digits}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${_formatAmount(stat.totalSpent)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.red,
                        ),
                      ),
                      Text(
                        '${stat.debitCount} transactions',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[200],
                  valueColor:
                      AlwaysStoppedAnimation(_getAccountColor(account.type)),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Received: ₹${_formatAmount(stat.totalReceived)}',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Net: ₹${_formatAmount(stat.totalReceived - stat.totalSpent)}',
                    style: TextStyle(
                      color: stat.totalReceived >= stat.totalSpent
                          ? Colors.green[700]
                          : Colors.red[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountTransactions(_AccountStats stat) {
    final accountTxs = _transactions.where((tx) {
      final key = tx.accountLast4 ?? tx.sender;
      return key == stat.key && _isInPeriod(tx.date);
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        _getAccountColor(stat.account.type).withValues(alpha: 0.2),
                    child: Icon(
                      _getAccountIcon(stat.account.type),
                      color: _getAccountColor(stat.account.type),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stat.account.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          '${accountTxs.length} transactions',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: accountTxs.length,
                itemBuilder: (context, index) {
                  final tx = accountTxs[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: tx.isDebit
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.green.withValues(alpha: 0.1),
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getAccountIcon(AccountType type) {
    switch (type) {
      case AccountType.bankAccount:
        return Icons.account_balance;
      case AccountType.creditCard:
        return Icons.credit_card;
      case AccountType.wallet:
        return Icons.wallet;
      case AccountType.upi:
        return Icons.phone_android;
    }
  }

  Color _getAccountColor(AccountType type) {
    switch (type) {
      case AccountType.bankAccount:
        return Colors.blue;
      case AccountType.creditCard:
        return Colors.purple;
      case AccountType.wallet:
        return Colors.orange;
      case AccountType.upi:
        return Colors.green;
    }
  }

  String _formatAmount(double amount) {
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(2)}K';
    }
    return amount.toStringAsFixed(0);
  }

  String _formatDate(DateTime date) {
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

class _AccountStats {
  final String key;
  final Account account;
  double totalSpent = 0;
  double totalReceived = 0;
  int debitCount = 0;
  int creditCount = 0;

  _AccountStats({required this.key, required this.account});
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '₹${_formatAmount(amount)}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(2)}K';
    }
    return amount.toStringAsFixed(0);
  }
}
