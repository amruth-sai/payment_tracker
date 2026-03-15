// lib/screens/sender_review_demo_screen.dart
// Demo screen showing how to use the new sender grouping functionality

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/sms_parser.dart';
import '../services/transaction_review_service.dart';
import '../services/local_storage_service.dart';
import '../widgets/sender_grouped_review_sheet.dart';

class SenderReviewDemoScreen extends StatefulWidget {
  const SenderReviewDemoScreen({super.key});

  @override
  State<SenderReviewDemoScreen> createState() => _SenderReviewDemoScreenState();
}

class _SenderReviewDemoScreenState extends State<SenderReviewDemoScreen> {
  List<Transaction> _allTransactions = [];
  Map<String, List<Transaction>> _groupedTransactions = {};
  Map<String, TransactionSummary> _summaries = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);

    try {
      final transactions = await LocalStorageService.getAllTransactions();
      final grouped = SmsParser.groupTransactionsBySender(transactions);
      final summaries = TransactionReviewService.getTransactionSummaryBySender(transactions);

      setState(() {
        _allTransactions = transactions;
        _groupedTransactions = grouped;
        _summaries = summaries;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading transactions: $e')),
        );
      }
    }
  }

  Future<void> _showGroupedReviewDemo() async {
    // Create some demo transactions for your specific banks
    final demoTransactions = [
      Transaction(
        id: 'demo_hdfc_1',
        amount: 25000,
        type: TransactionType.credit,
        source: PaymentSource.bank,
        sender: 'HDFC',
        merchant: 'Salary Credit',
        date: DateTime.now().subtract(const Duration(days: 1)),
        rawMessage: 'Your account has been credited with Rs. 25000 salary',
      ),
      Transaction(
        id: 'demo_hdfc_2',
        amount: 1500,
        type: TransactionType.debit,
        source: PaymentSource.card,
        sender: 'HDFC',
        merchant: 'Swiggy',
        date: DateTime.now().subtract(const Duration(hours: 6)),
        rawMessage: 'Rs. 1500 spent at Swiggy via HDFC card',
      ),
      Transaction(
        id: 'demo_icici_1',
        amount: 850,
        type: TransactionType.debit,
        source: PaymentSource.upi,
        sender: 'ICICI',
        merchant: 'Uber',
        date: DateTime.now().subtract(const Duration(hours: 3)),
        rawMessage: 'Rs. 850 paid to Uber via UPI',
      ),
      Transaction(
        id: 'demo_airtel_1',
        amount: 5000,
        type: TransactionType.credit,
        source: PaymentSource.bank,
        sender: 'AIRTEL',
        merchant: 'Money Transfer',
        date: DateTime.now().subtract(const Duration(hours: 2)),
        rawMessage: 'Rs. 5000 received in Airtel Payments Bank',
      ),
      Transaction(
        id: 'demo_onecard_1',
        amount: 2500,
        type: TransactionType.debit,
        source: PaymentSource.card,
        sender: 'OneCard',
        merchant: 'Amazon',
        date: DateTime.now().subtract(const Duration(minutes: 30)),
        rawMessage: 'Rs. 2500 spent on Amazon using OneCard',
      ),
    ];

    if (mounted) {
      await SenderGroupedReviewSheet.show(
        context,
        transactions: demoTransactions,
        onDone: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Demo review completed!'),
              backgroundColor: Colors.green,
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sender Grouping Demo'),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Info
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sender Grouping System',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your transactions are now grouped by sender, making it easier to review and manage your finances across different banks and credit cards.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoChip(
                                label: 'Total Transactions',
                                value: _allTransactions.length.toString(),
                                color: Colors.blue,
                              ),
                              _InfoChip(
                                label: 'Unique Senders',
                                value: _groupedTransactions.length.toString(),
                                color: Colors.orange,
                              ),
                              _InfoChip(
                                label: 'Your Banks',
                                value: _summaries.values
                                    .where((s) => s.isUserBank)
                                    .length
                                    .toString(),
                                color: Colors.green,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Demo Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _showGroupedReviewDemo,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Try Sender-Grouped Review'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Your Banks Section
                  Text(
                    'Your Banks & Credit Cards',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._summaries.entries
                      .where((entry) => entry.value.isUserBank)
                      .map((entry) => _SenderSummaryCard(
                            summary: entry.value,
                            onTap: () => _showSenderDetails(entry.key),
                          )),

                  if (_summaries.values.any((s) => !s.isUserBank)) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Other Payment Services',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._summaries.entries
                        .where((entry) => !entry.value.isUserBank)
                        .map((entry) => _SenderSummaryCard(
                              summary: entry.value,
                              onTap: () => _showSenderDetails(entry.key),
                            )),
                  ],

                  const SizedBox(height: 32),

                  // How it works section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                   color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'How Sender Grouping Works',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const _HowItWorksStep(
                            step: '1',
                            title: 'SMS Analysis',
                            description: 'The app reads SMS messages from banks and payment services',
                          ),
                          const _HowItWorksStep(
                            step: '2',
                            title: 'Sender Mapping',
                            description: 'Messages are grouped by unified sender names (e.g., HDFCBK → HDFC)',
                          ),
                          const _HowItWorksStep(
                            step: '3',
                            title: 'User Review',
                            description: 'You can review and confirm transaction types for each sender group',
                          ),
                          const _HowItWorksStep(
                            step: '4',
                            title: 'Smart Organization',
                            description: 'Your specific banks (HDFC, ICICI, Airtel, Jio Pay, OneCard, SBI) are highlighted',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _showSenderDetails(String senderName) {
    final transactions = _groupedTransactions[senderName] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SenderDetailSheet(
        senderName: senderName,
        transactions: transactions,
        summary: _summaries[senderName]!,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderSummaryCard extends StatelessWidget {
  final TransactionSummary summary;
  final VoidCallback onTap;

  const _SenderSummaryCard({
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: summary.isUserBank
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            summary.accountType == 'Credit Card'
                ? Icons.credit_card
                : Icons.account_balance,
            color: summary.isUserBank
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(summary.senderName)),
            if (summary.isUserBank)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'YOUR BANK',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${summary.accountType} • ${summary.summaryText}'),
            const SizedBox(height: 4),
            Text(
              'Net: ${summary.netAmount >= 0 ? '+' : ''}₹${NumberFormat('#,##,###').format(summary.netAmount.abs())}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: summary.netAmount >= 0 ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final String step;
  final String title;
  final String description;

  const _HowItWorksStep({
    required this.step,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderDetailSheet extends StatelessWidget {
  final String senderName;
  final List<Transaction> transactions;
  final TransactionSummary summary;

  const _SenderDetailSheet({
    required this.senderName,
    required this.transactions,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: summary.isUserBank
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        summary.accountType == 'Credit Card'
                            ? Icons.credit_card
                            : Icons.account_balance,
                        color: summary.isUserBank
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            senderName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(summary.accountType,
                               style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        label: 'Credits',
                        value: '₹${NumberFormat('#,##,###').format(summary.totalCredit)}',
                        count: '${summary.creditCount} transaction${summary.creditCount > 1 ? 's' : ''}',
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatItem(
                        label: 'Debits',
                        value: '₹${NumberFormat('#,##,###').format(summary.totalDebit)}',
                        count: '${summary.debitCount} transaction${summary.debitCount > 1 ? 's' : ''}',
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Transaction List
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: transactions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final tx = transactions[index];
                return _TransactionItem(transaction: tx);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String count;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            count,
            style: TextStyle(
              fontSize: 10,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionItem extends StatelessWidget {
  final Transaction transaction;

  const _TransactionItem({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = transaction;
    final amountColor = tx.isCredit ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: amountColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              tx.isCredit ? Icons.add : Icons.remove,
              size: 16,
              color: amountColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.merchant ?? 'Transaction',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(tx.date),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '${tx.isCredit ? '+' : '-'}₹${NumberFormat('#,##,###').format(tx.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}