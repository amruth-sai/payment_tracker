// lib/screens/category_breakdown_screen.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/standard_category.dart';
import '../models/custom_category.dart';
import '../services/local_storage_service.dart';

class CategoryBreakdownScreen extends StatefulWidget {
  const CategoryBreakdownScreen({super.key});

  @override
  State<CategoryBreakdownScreen> createState() =>
      _CategoryBreakdownScreenState();
}

class _CategoryBreakdownScreenState extends State<CategoryBreakdownScreen> {
  Map<String, double> _categoryTotals = {};
  Map<String, int> _categoryCounts = {};
  Map<String, StandardCategory> _standardCategories = {};
  Map<String, CustomCategory> _customCategories = {};
  List<Transaction> _periodTransactions = [];
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
    var transactions = await LocalStorageService.getTrackedTransactions();
    final standardCategories = await LocalStorageService.getAllStandardCategories();
    final customCategories = await LocalStorageService.getAllCustomCategories();

    // Filter by period
    final now = DateTime.now();
    if (_period != 'all') {
      final days = _period == '7d' ? 7 : _period == '30d' ? 30 : 90;
      final cutoff = now.subtract(Duration(days: days));
      transactions = transactions.where((t) => t.date.isAfter(cutoff)).toList();
    }

    // Sum debits by category
    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final tx in transactions.where((t) => t.isDebit)) {
      final cat = _categoryId(tx);
      totals[cat] = (totals[cat] ?? 0) + tx.amount;
      counts[cat] = (counts[cat] ?? 0) + 1;
    }

    setState(() {
      _categoryTotals = Map.fromEntries(
        totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );
      _categoryCounts = counts;
      _standardCategories = {for (final category in standardCategories) category.id: category};
      _customCategories = {for (final category in customCategories) category.id: category};
      _periodTransactions = transactions;
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
            color: _categoryColor(entry.key),
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
        final color = _categoryColor(cat);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(_categoryEmoji(cat), style: const TextStyle(fontSize: 18)),
          ),
          title: Text(
            _categoryName(cat),
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

  void _showCategoryTransactions(String category) async {
    final txs = _periodTransactions
        .where((t) => t.isDebit && _categoryId(t) == category)
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
                  Text(_categoryEmoji(category), style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text(_categoryName(category),
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

  String _categoryId(Transaction tx) => tx.customCategoryId == null
      ? (tx.effectiveStandardCategoryId ?? 'uncategorized')
      : 'custom:${tx.customCategoryId}';

  String _categoryName(String id) {
    if (id.startsWith('custom:')) {
      return _customCategories[id.substring(7)]?.name ?? 'Custom category';
    }
    return _standardCategories[id]?.displayName ??
        TransactionCategory.fromStandardCategoryId(id)?.displayName ??
        'Uncategorized';
  }

  String _categoryEmoji(String id) => id.startsWith('custom:')
      ? (_customCategories[id.substring(7)]?.emoji ?? '🏷️')
      : (_standardCategories[id]?.emoji ?? '❓');

  Color _categoryColor(String id) => id.startsWith('custom:')
      ? Color(_customCategories[id.substring(7)]?.colorValue ?? Colors.grey.toARGB32())
      : (_standardCategories[id]?.color ?? Colors.grey);

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(2)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}
