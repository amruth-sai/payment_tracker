// lib/screens/alerts_screen.dart

import 'package:flutter/material.dart';
import '../models/app_alert.dart';
import '../models/transaction.dart';
import '../services/anomaly_service.dart';
import '../services/budget_service.dart';
import '../services/emi_service.dart';
import '../services/local_storage_service.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AppAlert> _allAlerts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAlerts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    _allAlerts = await LocalStorageService.getAllAlerts();
    _allAlerts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() => _isLoading = false);
  }

  Future<void> _refreshAlerts() async {
    setState(() => _isRefreshing = true);

    final transactions = await LocalStorageService.getTrackedTransactions();

    final anomalies = AnomalyService.detectAnomalies(transactions);
    final duplicates = AnomalyService.detectDuplicates(transactions);
    final budgetStatuses =
        await BudgetService.getOverBudgetAlerts(transactions: transactions);
    final budgetUsage =
        await BudgetService.checkBudgets(transactions: transactions);
    final totalBudget = budgetUsage.fold<double>(
        0, (sum, status) => sum + status.budget.monthlyLimit);
    final totalBudgetSpent =
        budgetUsage.fold<double>(0, (sum, status) => sum + status.spent);
    final digest = AnomalyService.generateDailyDigest(
      transactions,
      totalBudget,
      totalBudgetSpent,
    );
    final emiAlerts = _detectEMIAlerts(transactions);

    final budgetAlerts = budgetStatuses
        .map(
          (status) => AppAlert(
            id: 'budget_${status.standardCategory.id}_${DateTime.now().millisecondsSinceEpoch}',
            type: AlertType.budgetWarning,
            severity: status.isOverBudget
                ? AlertSeverity.critical
                : AlertSeverity.warning,
            title:
                '${status.standardCategory.emoji} ${status.standardCategory.displayName} budget',
            message:
                '${status.percentage.toStringAsFixed(0)}% used - ₹${status.spent.toStringAsFixed(0)} of ₹${status.budget.monthlyLimit.toStringAsFixed(0)}',
          ),
        )
        .toList();

    final newAlerts = <AppAlert>[
      ...anomalies,
      ...duplicates,
      ...budgetAlerts,
      ...emiAlerts,
    ];
    if (digest != null) newAlerts.add(digest);

    if (newAlerts.isNotEmpty) {
      await LocalStorageService.saveAlerts(newAlerts);
    }

    await _loadAlerts();
    setState(() => _isRefreshing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found ${newAlerts.length} new alerts'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  List<AppAlert> _detectEMIAlerts(List<Transaction> transactions) {
    final emis = EMIService.detectEMIs(transactions);
    return emis
        .where((emi) => emi.isActive && emi.totalDetected >= 3)
        .map(
          (emi) => AppAlert(
            id: 'emi_${emi.id}_${DateTime.now().millisecondsSinceEpoch}',
            type: AlertType.emiDetected,
            severity: AlertSeverity.info,
            title: 'Recurring EMI: ${emi.merchant}',
            message:
                '₹${emi.amount.toStringAsFixed(0)} detected on the ${emi.dayOfMonth}th of each month (${emi.totalDetected} occurrences)',
          ),
        )
        .toList();
  }

  List<AppAlert> _filtered(AlertType type) =>
      _allAlerts.where((alert) => alert.type == type).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts & Insights'),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Scan for new alerts',
              onPressed: _refreshAlerts,
            ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'read_all') {
                await LocalStorageService.markAllAlertsRead();
                _loadAlerts();
              } else if (value == 'clean') {
                await LocalStorageService.cleanOldAlerts();
                _loadAlerts();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'read_all',
                child: Text('Mark all as read'),
              ),
              const PopupMenuItem(
                value: 'clean',
                child: Text('Clear old alerts'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            _buildTab('Anomalies', AlertType.anomaly, Icons.warning_amber),
            _buildTab('Duplicates', AlertType.duplicate, Icons.copy),
            _buildTab('Budget', AlertType.budgetWarning, Icons.pie_chart),
            _buildTab('Digest', AlertType.dailyDigest, Icons.summarize),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAlertList(_filtered(AlertType.anomaly)),
                _buildAlertList(_filtered(AlertType.duplicate)),
                _buildAlertList(_filtered(AlertType.budgetWarning)),
                _buildAlertList([
                  ..._filtered(AlertType.dailyDigest),
                  ..._filtered(AlertType.emiDetected),
                ]),
              ],
            ),
    );
  }

  Widget _buildTab(String label, AlertType type, IconData icon) {
    final unread = _allAlerts.where((a) => a.type == type && !a.isRead).length;
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label),
          if (unread > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$unread',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertList(List<AppAlert> alerts) {
    if (alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 48, color: Colors.green[300]),
            const SizedBox(height: 12),
            const Text(
              'All clear!',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _refreshAlerts,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan now'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: alerts.length,
      itemBuilder: (_, index) => _buildAlertCard(alerts[index]),
    );
  }

  Widget _buildAlertCard(AppAlert alert) {
    final severityColor = switch (alert.severity) {
      AlertSeverity.critical => Colors.red,
      AlertSeverity.warning => Colors.orange,
      AlertSeverity.info => Colors.blue,
    };

    final typeIcon = switch (alert.type) {
      AlertType.anomaly => Icons.trending_up,
      AlertType.duplicate => Icons.copy_all,
      AlertType.budgetWarning => Icons.pie_chart,
      AlertType.dailyDigest => Icons.calendar_today,
      AlertType.emiDetected => Icons.event_repeat,
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: alert.isRead ? 0 : 2,
      color: alert.isRead ? null : severityColor.withValues(alpha: 0.05),
      child: InkWell(
        onTap: () async {
          if (!alert.isRead) {
            await LocalStorageService.markAlertRead(alert.id);
            _loadAlerts();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: severityColor.withValues(alpha: 0.15),
                child: Icon(typeIcon, size: 18, color: severityColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.title,
                            style: TextStyle(
                              fontWeight: alert.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (!alert.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: severityColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.message,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeAgo(alert.createdAt),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}
