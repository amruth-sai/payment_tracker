import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/local_backup.dart';
import '../models/salary_cycle.dart';
import '../services/backup_service.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';
import '../services/transaction_export_service.dart';
import 'merchant_rules_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, int> _cacheStats = const {};
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;

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
                          'Backup & Restore',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create a password-protected backup of all app data, including '
                          'transactions, settings, and payment SMS. Choose Drive, Downloads, '
                          'or another location with Android\'s document picker.',
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isBackingUp || _isRestoring
                                ? null
                                : _createBackup,
                            icon: _isBackingUp
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.lock_outline),
                            label: Text(
                              _isBackingUp
                                  ? 'Creating Backup...'
                                  : 'Create Encrypted Backup',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isBackingUp || _isRestoring
                                ? null
                                : _restoreBackup,
                            icon: _isRestoring
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.settings_backup_restore),
                            label: Text(
                              _isRestoring
                                  ? 'Restoring Backup...'
                                  : 'Restore Encrypted Backup',
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

  Future<void> _createBackup() async {
    final password = await _askForBackupPassword(confirm: true);
    if (password == null || !mounted) return;

    setState(() => _isBackingUp = true);
    try {
      await BackupService.createEncryptedBackup(password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encrypted backup saved. Keep its password safe.')),
      );
    } catch (error) {
      _showBackupError(error, fallback: 'Unable to create the backup.');
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  Future<void> _restoreBackup() async {
    setState(() => _isRestoring = true);
    try {
      final encryptedContent = await BackupService.chooseEncryptedBackup();
      if (encryptedContent == null || !mounted) return;

      final password = await _askForBackupPassword(confirm: false);
      if (password == null || !mounted) return;

      final backup = await BackupService.decryptBackup(encryptedContent, password);
      if (!mounted) return;

      final mode = await _chooseRestoreMode(backup);
      if (mode == null || !mounted) return;
      if (mode == BackupRestoreMode.replace) {
        final confirmed = await _confirmReplacement();
        if (!confirmed) return;
      }
      if (!mounted) return;

      final records = await LocalStorageService.restoreBackup(backup, mode);
      if (!mounted) return;
      await context.read<SmsService>().reloadFromCache();
      await _loadCacheStats();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${mode == BackupRestoreMode.merge ? 'Merged' : 'Restored'} '
            '$records backup records.',
          ),
        ),
      );
    } catch (error) {
      _showBackupError(error, fallback: 'Unable to restore this backup.');
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<String?> _askForBackupPassword({required bool confirm}) async {
    final passwordController = TextEditingController();
    final confirmationController = TextEditingController();
    String? error;

    final password = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(confirm ? 'Protect Your Backup' : 'Backup Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                confirm
                    ? 'Use a password with at least 8 characters. It cannot be recovered.'
                    : 'Enter the password used when this backup was created.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (confirm) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: confirmationController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = passwordController.text;
                if (value.length < 8) {
                  setDialogState(() => error = 'Use at least 8 characters.');
                  return;
                }
                if (confirm && value != confirmationController.text) {
                  setDialogState(() => error = 'Passwords do not match.');
                  return;
                }
                Navigator.pop(context, value);
              },
              child: Text(confirm ? 'Continue' : 'Unlock'),
            ),
          ],
        ),
      ),
    );

    passwordController.dispose();
    confirmationController.dispose();
    return password;
  }

  Future<BackupRestoreMode?> _chooseRestoreMode(LocalBackup backup) {
    final formattedDate = DateFormat('d MMM yyyy, h:mm a').format(
      backup.createdAt.toLocal(),
    );
    return showDialog<BackupRestoreMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Created $formattedDate with ${backup.transactionCount} '
              'transactions and ${backup.recordCount} total records.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Merge adds records that are not already on this device. '
              'When a record already exists locally, it stays unchanged.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Replace deletes current app data, then restores this backup.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, BackupRestoreMode.merge),
            child: const Text('Merge'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, BackupRestoreMode.replace),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmReplacement() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace All App Data?'),
            content: const Text(
              'Your current transactions, settings, and cleanup rules will be removed '
              'before this backup is restored. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Replace Data'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showBackupError(Object error, {required String fallback}) {
    if (!mounted || error is PlatformException && error.code == 'cancelled') {
      return;
    }
    final message = error is FormatException ? error.message : fallback;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
