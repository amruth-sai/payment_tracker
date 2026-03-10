// lib/screens/spending_heatmap_screen.dart

import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';
import '../models/transaction.dart';
// ignore_for_file: unused_import

class SpendingHeatmapScreen extends StatefulWidget {
  const SpendingHeatmapScreen({super.key});

  @override
  State<SpendingHeatmapScreen> createState() => _SpendingHeatmapScreenState();
}

class _SpendingHeatmapScreenState extends State<SpendingHeatmapScreen> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, double> _dailySpending = {};
  double _maxDailySpend = 0;
  bool _isLoading = true;
  List<Transaction> _allTransactions = [];

  @override
  void initState() {
    super.initState();
    _loadAllTransactions();
  }

  Future<void> _loadAllTransactions() async {
    _allTransactions = await LocalStorageService.getAllTransactions();
    _computeMonth();
  }

  void _computeMonth() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final Map<int, double> daily = {};
    for (int d = 1; d <= daysInMonth; d++) {
      daily[d] = 0;
    }

    for (final tx in _allTransactions) {
      if (tx.date.year == year &&
          tx.date.month == month &&
          tx.type == TransactionType.debit) {
        final day = tx.date.day;
        daily[day] = (daily[day] ?? 0) + tx.amount;
      }
    }

    double maxVal = 0;
    for (final v in daily.values) {
      if (v > maxVal) maxVal = v;
    }

    setState(() {
      _dailySpending = daily;
      _maxDailySpend = maxVal;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spending Heatmap')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildMonthSelector(),
                _buildLegend(),
                Expanded(child: _buildCalendarGrid()),
                _buildMonthSummary(),
              ],
            ),
    );
  }

  Widget _buildMonthSelector() {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
              });
              _computeMonth();
            },
          ),
          Text(
            '${months[_currentMonth.month - 1]} ${_currentMonth.year}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              final now = DateTime.now();
              final next = DateTime(_currentMonth.year, _currentMonth.month + 1);
              if (next.isBefore(DateTime(now.year, now.month + 1))) {
                setState(() => _currentMonth = next);
                _computeMonth();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Less', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 4),
          for (double i = 0; i <= 1; i += 0.25)
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: _getHeatColor(i),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          const SizedBox(width: 4),
          const Text('More', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=Mon, 7=Sun

    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: dayLabels
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style:
                                const TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.builder(
              itemCount: firstWeekday - 1 + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                if (index < firstWeekday - 1) {
                  return const SizedBox.shrink();
                }
                final day = index - (firstWeekday - 1) + 1;
                final amount = _dailySpending[day] ?? 0;
                final intensity =
                    _maxDailySpend > 0 ? (amount / _maxDailySpend) : 0.0;
                final isToday = DateTime.now().year == year &&
                    DateTime.now().month == month &&
                    DateTime.now().day == day;

                return GestureDetector(
                  onTap: () => _showDayDetail(day, amount),
                  child: Container(
                    decoration: BoxDecoration(
                      color: amount > 0
                          ? _getHeatColor(intensity)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                      border: isToday
                          ? Border.all(color: Colors.blue, width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.normal,
                        color: intensity > 0.6 ? Colors.white : Colors.black87,
                      ),
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

  Widget _buildMonthSummary() {
    double total = 0;
    int spendDays = 0;
    double highest = 0;
    int highestDay = 0;

    _dailySpending.forEach((day, amount) {
      total += amount;
      if (amount > 0) spendDays++;
      if (amount > highest) {
        highest = amount;
        highestDay = day;
      }
    });

    final average = spendDays > 0 ? total / spendDays : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Total', '₹${_fmt(total)}'),
          _summaryItem('Avg/Day', '₹${_fmt(average)}'),
          _summaryItem('Peak', '₹${_fmt(highest)}\n(Day $highestDay)'),
          _summaryItem('Active', '$spendDays days'),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      children: [
        Text(value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  void _showDayDetail(int day, double amount) {
    final txs = _allTransactions.where((tx) {
      return tx.date.year == _currentMonth.year &&
          tx.date.month == _currentMonth.month &&
          tx.date.day == day &&
          tx.type == TransactionType.debit;
    }).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '${_currentMonth.month}/$day — ',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '₹${_fmt(amount)} spent',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: txs.isEmpty
                  ? const Center(child: Text('No spending this day'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: txs.length,
                      itemBuilder: (_, i) {
                        final tx = txs[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red[50],
                            child: Text(tx.category?.emoji ?? '💳',
                                style: const TextStyle(fontSize: 18)),
                          ),
                          title: Text(tx.merchant ?? tx.sender,
                              style: const TextStyle(fontSize: 14)),
                          trailing: Text(
                            '-₹${_fmt(tx.amount)}',
                            style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600),
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

  Color _getHeatColor(double intensity) {
    if (intensity <= 0) return Colors.grey[100]!;
    if (intensity < 0.25) return Colors.red[100]!;
    if (intensity < 0.50) return Colors.red[200]!;
    if (intensity < 0.75) return Colors.red[400]!;
    return Colors.red[700]!;
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}
