// lib/screens/emi_tracker_screen.dart

import 'package:flutter/material.dart';
import '../models/emi.dart';
import '../services/emi_service.dart';
import '../services/local_storage_service.dart';

class EMITrackerScreen extends StatefulWidget {
  const EMITrackerScreen({super.key});

  @override
  State<EMITrackerScreen> createState() => _EMITrackerScreenState();
}

class _EMITrackerScreenState extends State<EMITrackerScreen> {
  List<DetectedEMI> _emis = [];
  bool _isLoading = true;
  double _totalBurden = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final transactions = await LocalStorageService.getAllTransactions();
    final emis = EMIService.detectEMIs(transactions);
    final burden = EMIService.totalMonthlyBurden(emis);
    setState(() {
      _emis = emis;
      _totalBurden = burden;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EMI Tracker')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 12),
                  if (_emis.isEmpty)
                    _buildEmptyState()
                  else
                    ..._emis.map(_buildEMICard),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard() {
    final active = _emis.where((e) => e.isActive).length;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text('₹${_fmt(_totalBurden)}',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                const Text('Monthly EMI Burden',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
            Container(width: 1, height: 40, color: Colors.grey[400]),
            Column(
              children: [
                Text('$active',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                const Text('Active EMIs', style: TextStyle(fontSize: 12)),
              ],
            ),
            Container(width: 1, height: 40, color: Colors.grey[400]),
            Column(
              children: [
                Text('${_emis.length}',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                const Text('Detected', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.event_repeat, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('No recurring EMIs detected',
              style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          const Text(
            'We analyze your transactions to find recurring monthly payments.\n'
            'EMIs are detected when similar amounts appear on similar dates each month.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEMICard(DetectedEMI emi) {
    final dayStr = _ordinal(emi.dayOfMonth);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor:
              emi.isActive ? Colors.orange[100] : Colors.grey[200],
          child: Icon(
            Icons.event_repeat,
            color: emi.isActive ? Colors.orange[700] : Colors.grey,
          ),
        ),
        title: Text(emi.merchant,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            Text('₹${_fmt(emi.amount)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.orange)),
            const Text(' · ', style: TextStyle(color: Colors.grey)),
            Text('$dayStr of every month',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (!emi.isActive) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Inactive',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _detailItem('Occurrences', '${emi.totalDetected}'),
                    _detailItem('Est. Total',
                        '₹${_fmt(emi.estimatedTotal?.toDouble() ?? 0.0)}'),
                    if (emi.remainingCount != null)
                      _detailItem('Remaining', '~${emi.remainingCount}'),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Payment History',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: emi.occurrences.map((date) {
                    return Chip(
                      label: Text(
                        '${date.day}/${date.month}/${date.year}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailItem(String label, String value) {
    return Column(
      children: [
        Text(value,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}
