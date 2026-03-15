// lib/screens/onboarding/ai_account_review_screen.dart
// Screen for reviewing AI-discovered accounts before confirmation

import 'package:flutter/material.dart';
import '../../models/account.dart';
import '../../services/ai_account_discovery_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/sms_parser.dart';
import '../home_screen.dart';

class AiAccountReviewScreen extends StatefulWidget {
  final AccountDiscoveryResult discoveryResult;
  final DateTimeRange dateRange;

  const AiAccountReviewScreen({
    super.key,
    required this.discoveryResult,
    required this.dateRange,
  });

  @override
  State<AiAccountReviewScreen> createState() => _AiAccountReviewScreenState();
}

class _AiAccountReviewScreenState extends State<AiAccountReviewScreen> {
  late List<DiscoveredAccount> _accounts;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _accounts = List.from(widget.discoveryResult.discoveredAccounts);
  }

  int get _selectedCount => _accounts.where((a) => a.isSelected).length;
  int get _bankCount =>
      _accounts.where((a) => a.isSelected && a.type == AccountType.bankAccount).length;
  int get _cardCount =>
      _accounts.where((a) => a.isSelected && a.type == AccountType.creditCard).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Review Your Accounts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Summary header
          _buildSummaryHeader(theme),

          // Account list
          Expanded(
            child: _accounts.isEmpty
                ? _buildEmptyState(theme)
                : _buildAccountList(theme),
          ),

          // Bottom actions
          _buildBottomActions(theme),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome,
              color: theme.colorScheme.onPrimary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI found ${_accounts.length} accounts',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_bankCount bank accounts, $_cardCount credit cards',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No accounts found',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'We couldn\'t detect any bank accounts from your messages. You can add them manually.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _showAddAccountDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Account Manually'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _accounts.length + 1, // +1 for "Add Account" button
      itemBuilder: (context, index) {
        if (index == _accounts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton.icon(
              onPressed: _showAddAccountDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Missing Account'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          );
        }

        final account = _accounts[index];
        return _AccountCard(
          account: account,
          onToggle: () => _toggleAccount(index),
          onEdit: () => _editAccount(index),
          onDelete: () => _deleteAccount(index),
        );
      },
    );
  }

  Widget _buildBottomActions(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedCount == 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Select at least one account to continue',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selectedCount > 0 && !_isSaving
                    ? _confirmAndSave
                    : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Confirm $_selectedCount Accounts'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleAccount(int index) {
    setState(() {
      _accounts[index].isSelected = !_accounts[index].isSelected;
    });
  }

  void _editAccount(int index) {
    showDialog(
      context: context,
      builder: (context) => _EditAccountDialog(
        account: _accounts[index],
        onSave: (name, type) {
          setState(() {
            _accounts[index].name = name;
            _accounts[index].type = type;
          });
        },
      ),
    );
  }

  void _deleteAccount(int index) {
    setState(() {
      _accounts.removeAt(index);
    });
  }

  void _showAddAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddAccountDialog(
        onAdd: (account) {
          setState(() {
            _accounts.add(account);
          });
        },
      ),
    );
  }

  Future<void> _confirmAndSave() async {
    setState(() => _isSaving = true);

    try {
      // Save selected accounts
      final selectedAccounts = _accounts.where((a) => a.isSelected).toList();
      await AiAccountDiscoveryService.saveConfirmedAccounts(selectedAccounts);

      // Create sender to account name mapping for transactions
      final senderToAccountName = <String, String>{};
      for (final account in selectedAccounts) {
        for (final senderId in account.senderIds) {
          senderToAccountName[senderId] = account.name;
        }
      }

      // Save transactions
      await AiAccountDiscoveryService.saveTransactions(
        widget.discoveryResult.parsedTransactions,
        senderToAccountName,
      );

      // Clear the parser cache to use new mappings
      SmsParser.clearSenderMappingCache();

      // Mark onboarding as complete
      await OnboardingService.setSenderOnboardingCompleted(true);

      if (mounted) {
        // Navigate to home screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving accounts: $e')),
        );
      }
    }
  }
}

class _AccountCard extends StatelessWidget {
  final DiscoveredAccount account;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AccountCard({
    required this.account,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: account.isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
          : null,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Checkbox
                  Checkbox(
                    value: account.isSelected,
                    onChanged: (_) => onToggle(),
                  ),

                  // Account icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getAccountColor(account.type, theme),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getAccountIcon(account.type),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Account details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _TypeChip(type: account.type),
                            if (account.last4Digits != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '****${account.last4Digits}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Actions
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Remove', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Sender IDs
              if (account.senderIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: account.senderIds.map((sender) {
                    return Chip(
                      label: Text(
                        sender,
                        style: theme.textTheme.bodySmall,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    );
                  }).toList(),
                ),
              ],

              // Message count
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${account.messageCount} messages found',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getAccountIcon(AccountType type) {
    switch (type) {
      case AccountType.bankAccount:
        return Icons.account_balance;
      case AccountType.creditCard:
        return Icons.credit_card;
      case AccountType.wallet:
        return Icons.account_balance_wallet;
      case AccountType.upi:
        return Icons.phone_android;
    }
  }

  Color _getAccountColor(AccountType type, ThemeData theme) {
    switch (type) {
      case AccountType.bankAccount:
        return Colors.blue;
      case AccountType.creditCard:
        return Colors.purple;
      case AccountType.wallet:
        return Colors.orange;
      case AccountType.upi:
        return Colors.green;
    }
  }
}

class _TypeChip extends StatelessWidget {
  final AccountType type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String label;
    Color color;

    switch (type) {
      case AccountType.bankAccount:
        label = 'Bank';
        color = Colors.blue;
        break;
      case AccountType.creditCard:
        label = 'Credit Card';
        color = Colors.purple;
        break;
      case AccountType.wallet:
        label = 'Wallet';
        color = Colors.orange;
        break;
      case AccountType.upi:
        label = 'UPI';
        color = Colors.green;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _EditAccountDialog extends StatefulWidget {
  final DiscoveredAccount account;
  final Function(String name, AccountType type) onSave;

  const _EditAccountDialog({
    required this.account,
    required this.onSave,
  });

  @override
  State<_EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<_EditAccountDialog> {
  late TextEditingController _nameController;
  late AccountType _selectedType;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account.name);
    _selectedType = widget.account.type;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Account Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AccountType>(
            initialValue: _selectedType,
            decoration: const InputDecoration(
              labelText: 'Account Type',
              border: OutlineInputBorder(),
            ),
            items: AccountType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(_getTypeLabel(type)),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedType = value);
              }
            },
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
            widget.onSave(_nameController.text.trim(), _selectedType);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _getTypeLabel(AccountType type) {
    switch (type) {
      case AccountType.bankAccount:
        return 'Bank Account';
      case AccountType.creditCard:
        return 'Credit Card';
      case AccountType.wallet:
        return 'Wallet';
      case AccountType.upi:
        return 'UPI';
    }
  }
}

class _AddAccountDialog extends StatefulWidget {
  final Function(DiscoveredAccount account) onAdd;

  const _AddAccountDialog({required this.onAdd});

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _nameController = TextEditingController();
  final _senderController = TextEditingController();
  AccountType _selectedType = AccountType.bankAccount;

  @override
  void dispose() {
    _nameController.dispose();
    _senderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Account Name',
              hintText: 'e.g., HDFC Savings',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AccountType>(
            initialValue: _selectedType,
            decoration: const InputDecoration(
              labelText: 'Account Type',
              border: OutlineInputBorder(),
            ),
            items: AccountType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(_getTypeLabel(type)),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedType = value);
              }
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _senderController,
            decoration: const InputDecoration(
              labelText: 'SMS Sender ID (optional)',
              hintText: 'e.g., HDFCBK',
              border: OutlineInputBorder(),
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
          onPressed: _nameController.text.trim().isNotEmpty
              ? () {
                  final senderIds = _senderController.text.trim().isNotEmpty
                      ? [_senderController.text.trim().toUpperCase()]
                      : <String>[];

                  widget.onAdd(DiscoveredAccount(
                    id: 'account_manual_${DateTime.now().millisecondsSinceEpoch}',
                    name: _nameController.text.trim(),
                    type: _selectedType,
                    senderIds: senderIds,
                    messageCount: 0,
                  ));
                  Navigator.pop(context);
                }
              : null,
          child: const Text('Add'),
        ),
      ],
    );
  }

  String _getTypeLabel(AccountType type) {
    switch (type) {
      case AccountType.bankAccount:
        return 'Bank Account';
      case AccountType.creditCard:
        return 'Credit Card';
      case AccountType.wallet:
        return 'Wallet';
      case AccountType.upi:
        return 'UPI';
    }
  }
}
