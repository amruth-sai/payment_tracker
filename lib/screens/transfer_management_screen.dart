// lib/screens/transfer_management_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sms_service.dart';
import '../services/transfer_service.dart';
import '../models/transaction.dart';
import '../widgets/merged_transfer_card.dart';
import '../utils/format_utils.dart';

class TransferManagementScreen extends StatefulWidget {
  const TransferManagementScreen({super.key});

  @override
  State<TransferManagementScreen> createState() => _TransferManagementScreenState();
}

class _TransferManagementScreenState extends State<TransferManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _potentialTransfers = []; // TransferPair objects
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPotentialTransfers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPotentialTransfers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final transactions = context.read<SmsService>().transactions;
      final potentialPairs = TransferService.detectPotentialTransfers(transactions);

      if (mounted) {
        setState(() {
          _potentialTransfers = potentialPairs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading potential transfers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Transfer Management',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'integrity_check') {
                await _performIntegrityCheck();
              } else if (value == 'refresh') {
                _loadPotentialTransfers();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'integrity_check',
                child: Row(
                  children: [
                    Icon(Icons.health_and_safety),
                    SizedBox(width: 8),
                    Text('Data Integrity Check'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('Refresh Suggestions'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Suggestions', icon: Icon(Icons.auto_fix_high_rounded)),
            Tab(text: 'Merged', icon: Icon(Icons.merge_rounded)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSuggestionsTab(),
          _buildMergedTransfersTab(),
        ],
      ),
    );
  }

  Widget _buildSuggestionsTab() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Analyzing transactions...'),
          ],
        ),
      );
    }

    if (_potentialTransfers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'No potential transfers found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'All your transfer transactions are already merged or no potential pairs were detected.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _potentialTransfers.length,
      itemBuilder: (context, index) {
        final transferPair = _potentialTransfers[index];
        return TransferPairSuggestionCard(
          transferPair: transferPair,
          onMerge: () => _handleMergeTransfer(transferPair),
          onDismiss: () => _handleDismissSuggestion(index),
        );
      },
    );
  }

  Widget _buildMergedTransfersTab() {
    return Consumer<SmsService>(
      builder: (context, sms, _) {
        final mergedTransfers = TransferService.getMergedTransfers(sms.transactions);

        if (mergedTransfers.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swap_horiz_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No merged transfers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  'Merged transfer transactions will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: mergedTransfers.length,
          itemBuilder: (context, index) {
            final mergedTransfer = mergedTransfers[index];
            return MergedTransferCard(
              mergedTransfer: mergedTransfer,
              onTap: () => _showMergedTransferDetail(mergedTransfer),
              onSwipeUnmerge: (mt) => _handleUnmergeTransfer(mt),
            );
          },
        );
      },
    );
  }

  Future<void> _handleMergeTransfer(dynamic transferPair) async {
    try {
      await TransferService.mergeAsTransfer(
        transferPair.debitTransaction,
        transferPair.creditTransaction,
      );

      if (mounted) {
        context.read<SmsService>().reloadFromCache();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transactions merged as transfer successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Refresh suggestions
        _loadPotentialTransfers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error merging transfer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleDismissSuggestion(int index) {
    setState(() {
      _potentialTransfers.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Suggestion dismissed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _loadPotentialTransfers(); // Reload all suggestions
          },
        ),
      ),
    );
  }

  Future<void> _handleUnmergeTransfer(mergedTransfer) async {
    try {
      await TransferService.unmergeTransfer(mergedTransfer.sourceTransaction);

      if (mounted) {
        context.read<SmsService>().reloadFromCache();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transfer unmerged successfully'),
            backgroundColor: Colors.orange,
          ),
        );

        // Refresh suggestions since unmerged transactions might create new potential pairs
        _loadPotentialTransfers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error unmerging transfer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMergedTransferDetail(mergedTransfer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MergedTransferDetailSheet(mergedTransfer: mergedTransfer),
    );
  }

  Future<void> _performIntegrityCheck() async {
    if (!mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Checking data integrity...'),
          ],
        ),
      ),
    );

    try {
      final transactions = context.read<SmsService>().transactions;
      final report = TransferService.verifyDataIntegrity(transactions);

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        if (!report.hasIssues) {
          // No issues found
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ No data integrity issues found'),
              backgroundColor: Colors.green,
            ),
          );
          return;
        }

        // Issues found - show detailed report
        final shouldFix = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.warning, color: Colors.orange, size: 32),
            title: const Text('Data Integrity Issues Found'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(report.summary),
                const SizedBox(height: 16),
                if (report.orphanedTransactions.isNotEmpty) ...[
                  Text(
                    '🔴 Orphaned Transactions: ${report.orphanedTransactions.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text('Transactions with transfer IDs but missing partners'),
                  const SizedBox(height: 8),
                ],
                if (report.corruptedGroups.isNotEmpty) ...[
                  Text(
                    '🔴 Corrupted Groups: ${report.corruptedGroups.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text('Multiple transactions sharing the same transfer ID'),
                  const SizedBox(height: 8),
                ],
                if (report.invalidTransfers.isNotEmpty) ...[
                  Text(
                    '⚠️  Invalid Transfers: ${report.invalidTransfers.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text('Transfers with mismatched amounts or types'),
                  const SizedBox(height: 8),
                ],
                if (report.validationWarnings.isNotEmpty) ...[
                  Text(
                    '⚠️  Validation Warnings: ${report.validationWarnings.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text('Minor inconsistencies in transfer metadata'),
                  const SizedBox(height: 8),
                ],
                if (report.orphanedTransactions.isNotEmpty || report.corruptedGroups.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Would you like to automatically fix the resolvable issues?',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              if (report.orphanedTransactions.isNotEmpty || report.corruptedGroups.isNotEmpty)
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Fix Issues'),
                ),
            ],
          ),
        );

        // Apply fixes if requested
        if (shouldFix == true && mounted) {
          await _applyIntegrityFixes(transactions);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during integrity check: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _applyIntegrityFixes(List<Transaction> transactions) async {
    if (!mounted) return;

    // Show fixing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Fixing data integrity issues...'),
          ],
        ),
      ),
    );

    try {
      final result = await TransferService.cleanupDataIntegrity(transactions);

      if (mounted) {
        Navigator.of(context).pop(); // Close fixing dialog

        if (result.wasSuccessful) {
          context.read<SmsService>().reloadFromCache();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${result.summary}'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh the suggestions after cleanup
          _loadPotentialTransfers();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${result.summary}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close fixing dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fixing issues: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Detailed sheet for merged transfer - same as in all_transactions_screen.dart
class _MergedTransferDetailSheet extends StatelessWidget {
  final dynamic mergedTransfer;

  const _MergedTransferDetailSheet({required this.mergedTransfer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const transferColor = Color(0xFF1976D2);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Title
                    Row(
                      children: [
                        const Icon(Icons.swap_horiz_rounded, color: transferColor, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'Transfer Details',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: transferColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Amount
                    Center(
                      child: Column(
                        children: [
                          Text(
                            FormatUtils.formatCurrency(mergedTransfer.amount),
                            style: theme.textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: transferColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: transferColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Account Transfer',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: transferColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await TransferService.unmergeTransfer(mergedTransfer.sourceTransaction);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                context.read<SmsService>().reloadFromCache();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Transfer unmerged successfully'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.call_split_rounded),
                            label: const Text('Unmerge'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}