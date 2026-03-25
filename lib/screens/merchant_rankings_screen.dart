// lib/screens/merchant_rankings_screen.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';
import '../models/transaction.dart';

class MerchantRankingsScreen extends StatefulWidget {
  const MerchantRankingsScreen({super.key});

  @override
  State<MerchantRankingsScreen> createState() => _MerchantRankingsScreenState();
}

class _MerchantRankingsScreenState extends State<MerchantRankingsScreen> {
  List<_MerchantStat> _merchants = [];
  bool _isLoading = true;
  int _periodDays = 30;

  static const _barColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Violet
    Color(0xFFEC4899), // Pink
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Emerald
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final allTx = await LocalStorageService.getAllTransactions();
    final cutoff = DateTime.now().subtract(Duration(days: _periodDays));

    final Map<String, _MerchantStat> map = {};
    for (final tx in allTx) {
      if (tx.type != TransactionType.debit || tx.date.isBefore(cutoff)) continue;
      final merchantName = tx.merchant ?? tx.sender;
      final key = merchantName.toLowerCase().trim();
      if (key.isEmpty || key == 'unknown') continue;
      map.putIfAbsent(
          key,
          () => _MerchantStat(
                name: merchantName,
                totalAmount: 0,
                count: 0,
                category: tx.category,
              ));
      map[key] = _MerchantStat(
        name: map[key]!.name,
        totalAmount: map[key]!.totalAmount + tx.amount,
        count: map[key]!.count + 1,
        category: tx.category ?? map[key]!.category,
      );
    }

    final sorted = map.values.toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    setState(() {
      _merchants = sorted;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Merchant Rankings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildPeriodSelector(),
                if (_merchants.isNotEmpty) _buildBarChart(),
                Expanded(child: _buildMerchantList()),
              ],
            ),
    );
  }

  Widget _buildPeriodSelector() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 7, label: Text('7D')),
          ButtonSegment(value: 30, label: Text('30D')),
          ButtonSegment(value: 90, label: Text('90D')),
          ButtonSegment(value: 365, label: Text('1Y')),
        ],
        selected: {_periodDays},
        onSelectionChanged: (s) {
          setState(() => _periodDays = s.first);
          _loadData();
        },
      ),
    );
  }

  Widget _buildBarChart() {
    final topN = _merchants.take(5).toList();
    final maxVal = topN.fold(0.0, (m, s) => s.totalAmount > m ? s.totalAmount : m);

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(16, 8, 24, 0),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gIdx, rod, rIdx) {
                final stat = topN[group.x.toInt()];
                return BarTooltipItem(
                  '${stat.name}\n₹${_fmt(stat.totalAmount)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx >= topN.length) return const SizedBox.shrink();
                  final name = topN[idx].name;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      name.length > 8 ? '${name.substring(0, 8)}...' : name,
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
                reservedSize: 36,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (value, _) {
                  return Text('₹${_fmtShort(value)}',
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.grey.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          barGroups: List.generate(topN.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: topN[i].totalAmount,
                  color: _barColors[i % _barColors.length],
                  width: 28,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildMerchantList() {
    if (_merchants.isEmpty) {
      return const Center(child: Text('No merchants found in this period'));
    }

    final total = _merchants.fold(0.0, (s, m) => s + m.totalAmount);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _merchants.length,
      itemBuilder: (_, i) {
        final m = _merchants[i];
        final pct = total > 0 ? (m.totalAmount / total * 100) : 0.0;
        final color = _barColors[i % _barColors.length];

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Text(
                '${i + 1}',
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ),
            title: Row(
              children: [
                if (m.category != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(m.category!.emoji),
                  ),
                Expanded(
                  child: Text(m.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            subtitle: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0, 1),
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${_fmt(m.totalAmount)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${m.count} txns',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(2)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtShort(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(2)}K';
    return v.toStringAsFixed(0);
  }
}

class _MerchantStat {
  final String name;
  final double totalAmount;
  final int count;
  final TransactionCategory? category;

  const _MerchantStat({
    required this.name,
    required this.totalAmount,
    required this.count,
    this.category,
  });
}
