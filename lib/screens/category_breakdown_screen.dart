// lib/screens/category_breakdown_screen.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/category_service.dart';
import '../services/local_storage_service.dart';

class CategoryBreakdownScreen extends StatefulWidget {
  const CategoryBreakdownScreen({super.key});

  @override
  State<CategoryBreakdownScreen> createState() =>
      _CategoryBreakdownScreenState();
}

class _CategoryBreakdownScreenState extends State<CategoryBreakdownScreen> {
  Map<TransactionCategory, double> _categoryTotals = {};
  Map<TransactionCategory, int> _categoryCounts = {};
  bool _isLoading = true;
  String _period = '30d';
  int? _touchedIndex;

  final _periods = {'7d': '7 Days', '30d': '30 Days', '90d': '90 Days', 'all': 'All'};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    var transactions = await LocalStorageService.getAllTransactions();

    // Filter by period
    final now = DateTime.now();
    if (_period != 'all') {
      final days = _period == '7d' ? 7 : _period == '30d' ? 30 : 90;
      final cutoff = now.subtract(Duration(days: days));
      transactions = transactions.where((t) => t.date.isAfter(cutoff)).toList();
    }

    // Auto-categorize uncategorized transactions
    final updates = <String, TransactionCategory>{};
    transactions = transactions.map((tx) {
      if (tx.category == null || tx.category == TransactionCategory.uncategorized) {
        final cat = CategoryService.categorize(tx);
        if (cat != TransactionCategory.uncategorized) {
          updates[tx.id] = cat;
        }
        return tx.copyWith(category: cat);
      }
      return tx;
    }).toList();

    // Persist categorizations
    if (updates.isNotEmpty) {
      await LocalStorageService.batchUpdateCategories(updates);
    }

    // Sum debits by category
    final totals = <TransactionCategory, double>{};
    final counts = <TransactionCategory, int>{};
    for (final tx in transactions.where((t) => t.isDebit)) {
      final cat = tx.category ?? TransactionCategory.uncategorized;
      totals[cat] = (totals[cat] ?? 0) + tx.amount;
      counts[cat] = (counts[cat] ?? 0) + 1;
    }

    setState(() {
      _categoryTotals = Map.fromEntries(
        totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );
      _categoryCounts = counts;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Category Breakdown')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _categoryTotals.isEmpty
              ? _buildEmpty()
              : Column(
                  children: [
                    _buildPeriodSelector(),
                    SizedBox(height: 220, child: _buildPieChart()),
                    const Divider(),
                    Expanded(child: _buildCategoryList()),
                  ],
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pie_chart_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('No spending data', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _periods.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.value),
              selected: _period == e.key,
              onSelected: (_) {
                setState(() => _period = e.key);
                _loadData();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPieChart() {
    final entries = _categoryTotals.entries.toList();
    final total = entries.fold(0.0, (sum, e) => sum + e.value);

    return PieChart(
      PieChartData(
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  response == null ||
                  response.touchedSection == null) {
                _touchedIndex = null;
                return;
              }
              _touchedIndex = response.touchedSection!.touchedSectionIndex;
            });
          },
        ),
        borderData: FlBorderData(show: false),
        sectionsSpace: 2,
        centerSpaceRadius: 50,
        sections: List.generate(entries.length, (i) {
          final isTouched = i == _touchedIndex;
          final entry = entries[i];
          final pct = total > 0 ? (entry.value / total * 100) : 0.0;
          return PieChartSectionData(
            color: _getCategoryColor(entry.key),
            value: entry.value,
            title: pct >= 5 ? '${pct.toStringAsFixed(0)}%' : '',
            radius: isTouched ? 60 : 50,
            titleStyle: TextStyle(
              fontSize: isTouched ? 14 : 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCategoryList() {
    final entries = _categoryTotals.entries.toList();
    final total = entries.fold(0.0, (sum, e) => sum + e.value);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final cat = entries[i].key;
        final amount = entries[i].value;
        final count = _categoryCounts[cat] ?? 0;
        final pct = total > 0 ? (amount / total * 100) : 0.0;
        final color = _getCategoryColor(cat);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(cat.emoji, style: const TextStyle(fontSize: 18)),
          ),
          title: Text(
            cat.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count transactions'),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 6,
                ),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${_fmt(amount)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          onTap: () => _showCategoryTransactions(cat),
        );
      },
    );
  }

  void _showCategoryTransactions(TransactionCategory category) async {
    final all = await LocalStorageService.getAllTransactions();
    final txs = all
        .where((t) => t.isDebit && (t.category ?? TransactionCategory.uncategorized) == category)
        .toList();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(category.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text(category.displayName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: txs.length,
                itemBuilder: (_, i) {
                  final tx = txs[i];
                  return ListTile(
                    title: Text(tx.merchant ?? tx.sender),
                    subtitle: Text(_fmtDate(tx.date)),
                    trailing: Text(
                      '-₹${_fmt(tx.amount)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.red),
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

  Color _getCategoryColor(TransactionCategory cat) {
    const colors = {
      TransactionCategory.foodDining: Colors.orange,
      TransactionCategory.travelTransport: Colors.blue,
      TransactionCategory.shopping: Colors.purple,
      TransactionCategory.rentHousing: Colors.brown,
      TransactionCategory.emiLoans: Colors.red,
      TransactionCategory.entertainment: Colors.pink,
      TransactionCategory.billsUtilities: Colors.teal,
      TransactionCategory.healthMedical: Colors.green,
      TransactionCategory.education: Colors.indigo,
      TransactionCategory.salaryIncome: Colors.lightGreen,
      TransactionCategory.transfer: Colors.blueGrey,
      TransactionCategory.cashback: Colors.amber,
      TransactionCategory.investment: Colors.cyan,
      TransactionCategory.other: Colors.grey,
      TransactionCategory.uncategorized: Colors.grey,
    };
    return colors[cat] ?? Colors.grey;
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}
