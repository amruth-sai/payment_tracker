// lib/screens/onboarding/sender_discovery_screen.dart
// Screen for discovering and assigning SMS senders to accounts

import 'package:flutter/material.dart';
import '../../models/sender_mapping.dart';
import '../../models/account.dart';
import '../../services/sender_discovery_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/local_storage_service.dart';
import '../sender_management_screen.dart';

class SenderDiscoveryScreen extends StatefulWidget {
  const SenderDiscoveryScreen({super.key});

  @override
  State<SenderDiscoveryScreen> createState() => _SenderDiscoveryScreenState();
}

class _SenderDiscoveryScreenState extends State<SenderDiscoveryScreen> {
  List<DiscoveredSender> _discoveredSenders = [];
  List<Account> _accounts = [];
  final Map<String, String?> _senderAssignments = {}; // senderId -> accountId
  bool _loading = true;
  bool _saving = false;
  String _loadingMessage = 'Discovering senders...';

  @override
  void initState() {
    super.initState();
    _loadSenders();
  }

  Future<void> _loadSenders() async {
    setState(() {
      _loading = true;
      _loadingMessage = 'Loading accounts...';
    });

    try {
      // Get accounts
      final accounts = await LocalStorageService.getAllAccounts();

      setState(() {
        _accounts = accounts;
        _loadingMessage = 'Analyzing SMS messages...';
      });

      // For demo purposes, create some sample discovered senders
      // In real implementation, this would analyze actual SMS messages
      final sampleSenders = await _createSampleSenders();

      setState(() {
        _discoveredSenders = sampleSenders;
        _loadingMessage = 'Auto-assigning senders...';
      });

      // Auto-assign senders based on name matching
      await _autoAssignSenders();

      setState(() {
        _loading = false;
      });

    } catch (e) {
      setState(() {
        _loading = false;
        _loadingMessage = 'Error: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading senders: $e')),
        );
      }
    }
  }

  Future<List<DiscoveredSender>> _createSampleSenders() async {
    // This would normally call SMS analysis
    // For demo, creating sample data
    return [
      DiscoveredSender(
        senderId: 'HDFCBK',
        messageCount: 45,
        firstSeen: DateTime.now().subtract(const Duration(days: 30)),
        lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
        sampleMessages: [
          'Rs.5,000 debited from your HDFC Bank account ending 1234',
          'Rs.25,000 credited to your HDFC Bank account',
          'Your HDFC Bank account balance is Rs.1,50,000',
        ],
        suggestedAccountName: 'HDFC Bank',
        suggestedAccountType: 'bank_account',
      ),
      DiscoveredSender(
        senderId: 'HDFCCC',
        messageCount: 22,
        firstSeen: DateTime.now().subtract(const Duration(days: 25)),
        lastSeen: DateTime.now().subtract(const Duration(days: 1)),
        sampleMessages: [
          'Rs.1,500 spent at SWIGGY using HDFC Credit Card ending 5678',
          'Rs.850 spent at UBER using HDFC Credit Card',
        ],
        suggestedAccountName: 'HDFC Bank',
        suggestedAccountType: 'credit_card',
      ),
      DiscoveredSender(
        senderId: 'ICICIB',
        messageCount: 18,
        firstSeen: DateTime.now().subtract(const Duration(days: 28)),
        lastSeen: DateTime.now().subtract(const Duration(hours: 5)),
        sampleMessages: [
          'Rs.2,000 debited from ICICI Bank account',
          'UPI payment of Rs.500 to merchant via ICICI Bank',
        ],
        suggestedAccountName: 'ICICI Bank',
        suggestedAccountType: 'bank_account',
      ),
      DiscoveredSender(
        senderId: 'ONECARD',
        messageCount: 12,
        firstSeen: DateTime.now().subtract(const Duration(days: 20)),
        lastSeen: DateTime.now().subtract(const Duration(hours: 8)),
        sampleMessages: [
          'Rs.3,200 spent at AMAZON using OneCard',
          'Rs.750 spent at FLIPKART using OneCard',
        ],
        suggestedAccountName: 'OneCard',
        suggestedAccountType: 'credit_card',
      ),
      DiscoveredSender(
        senderId: 'AIRTEL',
        messageCount: 8,
        firstSeen: DateTime.now().subtract(const Duration(days: 15)),
        lastSeen: DateTime.now().subtract(const Duration(days: 3)),
        sampleMessages: [
          'Rs.1,000 received in Airtel Payments Bank account',
          'Money transfer of Rs.500 from Airtel Payments Bank',
        ],
        suggestedAccountName: 'Airtel Payments Bank',
        suggestedAccountType: 'bank_account',
      ),
    ];
  }

  Future<void> _autoAssignSenders() async {
    for (final sender in _discoveredSenders) {
      // Find matching account based on suggestions
      final matchingAccount = _accounts.firstWhere(
        (account) => _isMatchingAccount(account, sender),
        orElse: () => _accounts.first, // Default to first account if no match
      );

      _senderAssignments[sender.senderId] = matchingAccount.id;
    }
  }

  bool _isMatchingAccount(Account account, DiscoveredSender sender) {
    final accountName = account.name.toLowerCase();
    final senderName = (sender.suggestedAccountName ?? '').toLowerCase();

    return accountName.contains('hdfc') && senderName.contains('hdfc') ||
           accountName.contains('icici') && senderName.contains('icici') ||
           accountName.contains('sbi') && senderName.contains('sbi') ||
           accountName.contains('airtel') && senderName.contains('airtel') ||
           accountName.contains('jio') && senderName.contains('jio');
  }

  Future<void> _saveAssignments() async {
    setState(() => _saving = true);

    try {
      // Save sender assignments
      for (final entry in _senderAssignments.entries) {
        final senderId = entry.key;
        final accountId = entry.value;

        if (accountId != null) {
          await SenderDiscoveryService.assignSenderToAccount(
            senderId: senderId,
            accountId: accountId,
            isUserAssigned: true,
          );
        }
      }

      // Mark onboarding as complete
      await OnboardingService.setSenderOnboardingCompleted(true);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const SenderManagementScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving assignments: $e')),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sender Discovery'),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      body: _loading
          ? _LoadingView(message: _loadingMessage)
          : Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.explore,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Found ${_discoveredSenders.length} SMS Senders',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Review and assign senders to your accounts',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _senderAssignments.values.where((id) => id != null).length /
                            _discoveredSenders.length,
                        backgroundColor: theme.colorScheme.surfaceContainer,
                        valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_senderAssignments.values.where((id) => id != null).length} of ${_discoveredSenders.length} senders assigned',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // Sender list
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _discoveredSenders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final sender = _discoveredSenders[index];
                      final assignedAccountId = _senderAssignments[sender.senderId];
                      final assignedAccount = assignedAccountId != null
                          ? _accounts.firstWhere((a) => a.id == assignedAccountId)
                          : null;

                      return _SenderAssignmentCard(
                        sender: sender,
                        accounts: _accounts,
                        assignedAccount: assignedAccount,
                        onAssignmentChanged: (accountId) {
                          setState(() {
                            _senderAssignments[sender.senderId] = accountId;
                          });
                        },
                      );
                    },
                  ),
                ),

                // Bottom actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                        offset: const Offset(0, -2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _showCreateAccountDialog(),
                            child: const Text('Add Account'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _saving ? null : _saveAssignments,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Complete Setup'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _showCreateAccountDialog() async {
    final result = await showDialog<Account>(
      context: context,
      builder: (context) => _CreateAccountDialog(),
    );

    if (result != null) {
      await LocalStorageService.saveAccount(result);
      setState(() {
        _accounts.add(result);
      });
    }
  }
}

class _LoadingView extends StatelessWidget {
  final String message;

  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

class _SenderAssignmentCard extends StatelessWidget {
  final DiscoveredSender sender;
  final List<Account> accounts;
  final Account? assignedAccount;
  final Function(String?) onAssignmentChanged;

  const _SenderAssignmentCard({
    required this.sender,
    required this.accounts,
    required this.assignedAccount,
    required this.onAssignmentChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAssigned = assignedAccount != null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAssigned
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isAssigned
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                sender.suggestedAccountType == 'credit_card'
                    ? Icons.credit_card
                    : Icons.account_balance,
                color: isAssigned
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            title: Row(
              children: [
                Text(
                  sender.senderId,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (sender.suggestedAccountName != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      sender.suggestedAccountName!,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              '${sender.messageCount} messages • ${sender.timeRangeDescription}',
            ),
            trailing: _AssignmentDropdown(
              accounts: accounts,
              selectedAccountId: assignedAccount?.id,
              onChanged: onAssignmentChanged,
            ),
          ),

          // Sample messages
          if (sender.sampleMessages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sample Messages:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...sender.sampleMessages.take(2).map(
                    (message) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AssignmentDropdown extends StatelessWidget {
  final List<Account> accounts;
  final String? selectedAccountId;
  final Function(String?) onChanged;

  const _AssignmentDropdown({
    required this.accounts,
    required this.selectedAccountId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButton<String?>(
      value: selectedAccountId,
      hint: Text(
        'Choose Account',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Unassigned', style: TextStyle(fontSize: 12)),
        ),
        ...accounts.map((account) => DropdownMenuItem<String?>(
          value: account.id,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                account.name,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              Text(
                account.typeLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        )),
      ],
      onChanged: onChanged,
      underline: const SizedBox(),
      isDense: true,
    );
  }
}

class _CreateAccountDialog extends StatefulWidget {
  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _nameController = TextEditingController();
  AccountType _selectedType = AccountType.bankAccount;
  final _bankNameController = TextEditingController();

  @override
  Widget build(BuildContext context) {

    return AlertDialog(
      title: const Text('Add New Account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Account Name',
              hintText: 'e.g., My HDFC Bank',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AccountType>(
            initialValue: _selectedType,
            decoration: const InputDecoration(labelText: 'Account Type'),
            items: AccountType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(type == AccountType.bankAccount ? 'Bank Account' : 'Credit Card'),
              );
            }).toList(),
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
        ],
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
    super.dispose();
  }
}