import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/salary_cycle.dart';
import 'merchant_rules_screen.dart';
import '../services/local_storage_service.dart';
import '../services/transaction_export_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, int> _cacheStats = const {};
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadCacheStats();
  }

  Future<void> _loadCacheStats() async {
    try {
      final stats = await LocalStorageService.getStats();
      if (!mounted) return;
      setState(() {
        _cacheStats = stats;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load cache statistics.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local Processing',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Payment messages are parsed and stored only on this device. '
                          'No AI service or API key is used.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Merchant Cleanup Rules',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Normalize a matching SMS to one merchant, category, and tag. '
                          'You can also apply a rule to transactions already saved.',
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MerchantRulesScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.auto_fix_high_outlined),
                            label: const Text('Manage Merchant Rules'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export Transactions',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Share all active transactions, a selected period, or a '
                          'salary month as JSON for trend analysis. Ignored '
                          'transactions and raw SMS content are excluded; '
                          'tags are included.',
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                _isExporting ? null : _exportTransactions,
                            icon: _isExporting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.ios_share),
                            label: Text(
                              _isExporting
                                  ? 'Preparing Export...'
                                  : 'Choose & Share JSON',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local Cache',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _StatRow(
                          label: 'Cached Transactions',
                          value: '${_cacheStats['transactions'] ?? 0}',
                        ),
                        _StatRow(
                          label: 'Processed SMS',
                          value: '${_cacheStats['processed_sms'] ?? 0}',
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _clearCache,
                            icon: const Icon(Icons.delete_sweep),
                            label: const Text('Clear Cache & Re-parse All'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Supported Senders',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The rule-based parser recognizes common Indian bank, UPI, '
                          'wallet, and card sender IDs.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text(
          'This deletes cached transactions and processes your SMS messages again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await LocalStorageService.clearAll();
    await LocalStorageService.setOnboardingCompleted(false);
    await LocalStorageService.setTrackFromDate(null);
    await LocalStorageService.setTrackFromTransactionId(null);
    await _loadCacheStats();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cache cleared. Return home to set up tracking.'),
      ),
    );
  }

  Future<void> _exportTransactions() async {
    final period = await _chooseExportPeriod();
    if (period == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Transactions?'),
        content: Text(
          'This creates a JSON file for ${period.label} with categories, tags, '
          'and notes. Ignored transactions, raw SMS content, balances, and '
          'reference IDs are excluded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isExporting = true);
    try {
      final count = await TransactionExportService.shareTrackedTransactions(
        start: period.start,
        end: period.end,
        periodLabel: period.label,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prepared $count transactions for sharing.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to export transactions. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<_ExportPeriod?> _chooseExportPeriod() async {
    final scope = await showDialog<_ExportScope>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose Export Period'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ExportScope.allActive),
            child: const _ExportOption(
              icon: Icons.all_inclusive,
              title: 'All Active Transactions',
              subtitle: 'Everything included in the app summaries',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ExportScope.dateRange),
            child: const _ExportOption(
              icon: Icons.date_range,
              title: 'Selected Period',
              subtitle: 'Choose a custom start and end date',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ExportScope.salaryCycle),
            child: const _ExportOption(
              icon: Icons.calendar_month,
              title: 'Salary Month',
              subtitle: 'Choose one of your saved salary cycles',
            ),
          ),
        ],
      ),
    );

    if (scope == null || !mounted) return null;

    switch (scope) {
      case _ExportScope.allActive:
        return const _ExportPeriod(label: 'All active transactions');
      case _ExportScope.dateRange:
        return _chooseDateRange();
      case _ExportScope.salaryCycle:
        return _chooseSalaryCycle();
    }
  }

  Future<_ExportPeriod?> _chooseDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month, now.day),
      ),
    );

    if (range == null) return null;

    final dateFormat = DateFormat('d MMM yyyy');
    return _ExportPeriod(
      label:
          '${dateFormat.format(range.start)} to ${dateFormat.format(range.end)}',
      start: DateTime(range.start.year, range.start.month, range.start.day),
      end: DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
        999,
      ),
    );
  }

  Future<_ExportPeriod?> _chooseSalaryCycle() async {
    try {
      final cycles = await LocalStorageService.getAllSalaryCycles();
      if (!mounted) return null;

      if (cycles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No saved salary cycles are available to export.'),
          ),
        );
        return null;
      }

      final cycle = await showDialog<SalaryCycle>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose Salary Month'),
          children: cycles
              .map(
                (cycle) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, cycle),
                  child: _ExportOption(
                    icon: cycle.isCurrent
                        ? Icons.circle
                        : Icons.calendar_month,
                    title: cycle.cycleLabel,
                    subtitle: _salaryCycleRangeLabel(cycle),
                  ),
                ),
              )
              .toList(),
        ),
      );

      if (cycle == null) return null;

      return _ExportPeriod(
        label: 'Salary month: ${cycle.cycleLabel}',
        start: cycle.startDate,
        end: cycle.endDate ?? DateTime.now(),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to load salary cycles.')),
        );
      }
      return null;
    }
  }

  String _salaryCycleRangeLabel(SalaryCycle cycle) {
    final dateFormat = DateFormat('d MMM yyyy');
    final end = cycle.endDate ?? DateTime.now();
    return '${dateFormat.format(cycle.startDate)} to ${dateFormat.format(end)}';
  }
}

enum _ExportScope { allActive, dateRange, salaryCycle }

class _ExportPeriod {
  const _ExportPeriod({this.start, this.end, required this.label});

  final DateTime? start;
  final DateTime? end;
  final String label;
}

class _ExportOption extends StatelessWidget {
  const _ExportOption({
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
        Icon(icon),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
