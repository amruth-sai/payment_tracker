// lib/screens/sender_management_screen.dart
// Screen for managing sender assignments and manual message reassignment

import 'package:flutter/material.dart';
import '../models/sender_mapping.dart';
import '../models/account.dart';
import '../services/sender_discovery_service.dart';
import '../services/local_storage_service.dart';
import '../widgets/transaction_reassignment_sheet.dart';

class SenderManagementScreen extends StatefulWidget {
  const SenderManagementScreen({super.key});

  @override
  State<SenderManagementScreen> createState() => _SenderManagementScreenState();
}

class _SenderManagementScreenState extends State<SenderManagementScreen>
    with SingleTickerProviderStateMixin {
  List<AccountWithSenders> _accountsWithSenders = [];
  List<String> _unassignedSenders = [];
  Map<String, int> _stats = {};
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final accountsWithSenders = await SenderDiscoveryService.getAccountsWithSenders();
      final unassignedSenders = await SenderDiscoveryService.getUnassignedSenders();
      final stats = await SenderDiscoveryService.getSenderAssignmentStats();

      setState(() {
        _accountsWithSenders = accountsWithSenders;
        _unassignedSenders = unassignedSenders;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sender Management'),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Accounts', icon: Icon(Icons.account_balance)),
            Tab(text: 'Unassigned', icon: Icon(Icons.help_outline)),
            Tab(text: 'Statistics', icon: Icon(Icons.analytics)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _AccountsTab(
                  accountsWithSenders: _accountsWithSenders,
                  onSenderMoved: _loadData,
                  onTransactionReassign: _showTransactionReassignment,
                ),
                _UnassignedTab(
                  unassignedSenders: _unassignedSenders,
                  accounts: _accountsWithSenders.map((a) => a.account).toList(),
                  onSenderAssigned: _loadData,
                ),
                _StatisticsTab(stats: _stats),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddAccountDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Account'),
      ),
    );
  }

  Future<void> _showTransactionReassignment(String senderId) async {
    final transactions = await LocalStorageService.getAllTransactions();
    final senderTransactions = transactions.where((tx) => tx.sender == senderId).toList();

    if (mounted && senderTransactions.isNotEmpty) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => TransactionReassignmentSheet(
          transactions: senderTransactions,
          accounts: _accountsWithSenders.map((a) => a.account).toList(),
          onReassignment: (transactions, newAccountId) async {
            // Reassign transactions to the new account
            for (final tx in transactions) {
              await LocalStorageService.updateTransaction(
                tx.copyWith(accountId: newAccountId),
              );
            }
            _loadData();
          },
        ),
      );
    }
  }

  Future<void> _showAddAccountDialog() async {
    final result = await showDialog<Account>(
      context: context,
      builder: (context) => _AddAccountDialog(),
    );

    if (result != null) {
      await LocalStorageService.saveAccount(result);
      _loadData();
    }
  }
}

class _AccountsTab extends StatelessWidget {
  final List<AccountWithSenders> accountsWithSenders;
  final VoidCallback onSenderMoved;
  final Function(String) onTransactionReassign;

  const _AccountsTab({
    required this.accountsWithSenders,
    required this.onSenderMoved,
    required this.onTransactionReassign,
  });

  @override
  Widget build(BuildContext context) {
    if (accountsWithSenders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No accounts found'),
            Text('Add an account to get started', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: accountsWithSenders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final accountWithSenders = accountsWithSenders[index];
        return _AccountCard(
          accountWithSenders: accountWithSenders,
          onSenderMoved: onSenderMoved,
          onTransactionReassign: onTransactionReassign,
        );
      },
    );
  }
}

class _AccountCard extends StatefulWidget {
  final AccountWithSenders accountWithSenders;
  final VoidCallback onSenderMoved;
  final Function(String) onTransactionReassign;

  const _AccountCard({
    required this.accountWithSenders,
    required this.onSenderMoved,
    required this.onTransactionReassign,
  });

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = widget.accountWithSenders.account;
    final senders = widget.accountWithSenders.senderMappings;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Account header
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                account.type == AccountType.creditCard
                    ? Icons.credit_card
                    : Icons.account_balance,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            title: Text(
              account.displayName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${account.typeLabel} • ${senders.length} sender${senders.length != 1 ? 's' : ''}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (senders.isNotEmpty)
                  IconButton(
                    onPressed: () => widget.onTransactionReassign(senders.first.senderId),
                    icon: const Icon(Icons.swap_horiz),
                    tooltip: 'Reassign Transactions',
                  ),
                IconButton(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  icon: AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
              ],
            ),
          ),

          // Senders list (expandable)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 0),
            secondChild: Column(
              children: [
                if (senders.isNotEmpty) ...[
                  const Divider(height: 1),
                  ...senders.map((mapping) => _SenderTile(
                    mapping: mapping,
                    onMove: () => _showMoveSenderDialog(context, mapping),
                    onRemove: () => _removeSender(mapping),
                  )),
                ] else
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No senders assigned to this account',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveSenderDialog(BuildContext context, SenderMapping mapping) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move ${mapping.senderId}'),
        content: const Text('Select the account to move this sender to:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (result != null) {
      await SenderDiscoveryService.moveSenderToAccount(
        senderId: mapping.senderId,
        fromAccountId: mapping.accountId,
        toAccountId: result,
      );
      widget.onSenderMoved();
    }
  }

  Future<void> _removeSender(SenderMapping mapping) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Sender'),
        content: Text('Remove ${mapping.senderId} from this account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SenderDiscoveryService.removeSenderFromAccount(
        mapping.senderId,
        mapping.accountId,
      );
      widget.onSenderMoved();
    }
  }
}

class _SenderTile extends StatelessWidget {
  final SenderMapping mapping;
  final VoidCallback onMove;
  final VoidCallback onRemove;

  const _SenderTile({
    required this.mapping,
    required this.onMove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      leading: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: mapping.isUserAssigned
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          mapping.isUserAssigned ? Icons.person : Icons.auto_fix_high,
          size: 16,
          color: mapping.isUserAssigned
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        mapping.senderId,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        mapping.isUserAssigned ? 'User assigned' : 'Auto assigned',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onMove,
            icon: const Icon(Icons.open_with),
            iconSize: 18,
            tooltip: 'Move to another account',
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            iconSize: 18,
            tooltip: 'Remove from account',
          ),
        ],
      ),
    );
  }
}

class _UnassignedTab extends StatelessWidget {
  final List<String> unassignedSenders;
  final List<Account> accounts;
  final VoidCallback onSenderAssigned;

  const _UnassignedTab({
    required this.unassignedSenders,
    required this.accounts,
    required this.onSenderAssigned,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (unassignedSenders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 64,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'All senders assigned!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Every SMS sender has been assigned to an account',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${unassignedSenders.length} Unassigned Senders',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'These senders don\'t belong to any account yet',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: unassignedSenders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final senderId = unassignedSenders[index];
              return _UnassignedSenderTile(
                senderId: senderId,
                accounts: accounts,
                onAssigned: onSenderAssigned,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UnassignedSenderTile extends StatelessWidget {
  final String senderId;
  final List<Account> accounts;
  final VoidCallback onAssigned;

  const _UnassignedSenderTile({
    required this.senderId,
    required this.accounts,
    required this.onAssigned,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.help_outline,
              color: Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              senderId,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          DropdownButton<String>(
            hint: const Text('Assign to...', style: TextStyle(fontSize: 12)),
            underline: const SizedBox(),
            items: accounts.map((account) => DropdownMenuItem<String>(
              value: account.id,
              child: Text(
                account.name,
                style: const TextStyle(fontSize: 12),
              ),
            )).toList(),
            onChanged: (accountId) async {
              if (accountId != null) {
                await SenderDiscoveryService.assignSenderToAccount(
                  senderId: senderId,
                  accountId: accountId,
                  isUserAssigned: true,
                );
                onAssigned();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _StatisticsTab extends StatelessWidget {
  final Map<String, int> stats;

  const _StatisticsTab({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSenders = stats['total_senders'] ?? 0;
    final assignedSenders = stats['assigned_senders'] ?? 0;
    final userAssigned = stats['user_assigned'] ?? 0;
    final autoAssigned = assignedSenders - userAssigned;
    final unassigned = totalSenders - assignedSenders;
    final assignmentPercentage = totalSenders > 0 ? (assignedSenders / totalSenders * 100).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.trending_up,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assignment Progress',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$assignmentPercentage% of senders assigned',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$assignedSenders / $totalSenders',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: totalSenders > 0 ? assignedSenders / totalSenders : 0,
                    backgroundColor: theme.colorScheme.surfaceContainer,
                    valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Statistics grid
          Text(
            'Detailed Statistics',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.5,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _StatCard(
                title: 'Total Senders',
                value: totalSenders.toString(),
                color: Colors.blue,
                icon: Icons.sms,
              ),
              _StatCard(
                title: 'User Assigned',
                value: userAssigned.toString(),
                color: Colors.green,
                icon: Icons.person,
              ),
              _StatCard(
                title: 'Auto Assigned',
                value: autoAssigned.toString(),
                color: Colors.purple,
                icon: Icons.auto_fix_high,
              ),
              _StatCard(
                title: 'Unassigned',
                value: unassigned.toString(),
                color: Colors.orange,
                icon: Icons.help_outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AddAccountDialog extends StatefulWidget {
  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _nameController = TextEditingController();
  AccountType _selectedType = AccountType.bankAccount;
  final _bankNameController = TextEditingController();
  final _last4Controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Account Name *',
                hintText: 'e.g., My HDFC Savings',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AccountType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(labelText: 'Account Type *'),
              items: [
                const DropdownMenuItem(
                  value: AccountType.bankAccount,
                  child: Text('Bank Account'),
                ),
                const DropdownMenuItem(
                  value: AccountType.creditCard,
                  child: Text('Credit Card'),
                ),
              ],
              onChanged: (type) => setState(() => _selectedType = type!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bankNameController,
              decoration: const InputDecoration(
                labelText: 'Bank Name',
                hintText: 'e.g., HDFC Bank',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _last4Controller,
              decoration: const InputDecoration(
                labelText: 'Last 4 Digits',
                hintText: 'e.g., 1234',
              ),
              maxLength: 4,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_nameController.text.isNotEmpty) {
              final account = Account(
                id: 'account_${DateTime.now().millisecondsSinceEpoch}',
                name: _nameController.text,
                type: _selectedType,
                bankName: _bankNameController.text.isNotEmpty ? _bankNameController.text : null,
                last4Digits: _last4Controller.text.isNotEmpty ? _last4Controller.text : null,
                isManuallyAdded: true,
              );
              Navigator.pop(context, account);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bankNameController.dispose();
    _last4Controller.dispose();
    super.dispose();
  }
}