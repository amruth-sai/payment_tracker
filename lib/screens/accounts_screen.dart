// lib/screens/accounts_screen.dart

import 'package:flutter/material.dart';
import '../models/account.dart';
import '../services/local_storage_service.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Account> _accounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);

    // First, auto-detect any new accounts from transactions
    await LocalStorageService.detectAccountsFromTransactions();

    // Then load all accounts
    final accounts = await LocalStorageService.getAllAccounts();

    setState(() {
      _accounts = accounts;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAccounts,
            tooltip: 'Re-detect accounts',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? _buildEmptyState()
              : _buildAccountsList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddAccountDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Account'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No accounts found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Accounts will be auto-detected from your transactions\nor you can add them manually',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsList() {
    final bankAccounts =
        _accounts.where((a) => a.type == AccountType.bankAccount).toList();
    final creditCards =
        _accounts.where((a) => a.type == AccountType.creditCard).toList();
    final wallets = _accounts
        .where((a) => a.type == AccountType.wallet || a.type == AccountType.upi)
        .toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        if (bankAccounts.isNotEmpty) ...[
          _buildSectionHeader('Bank Accounts', Icons.account_balance),
          ...bankAccounts.map(_buildAccountTile),
        ],
        if (creditCards.isNotEmpty) ...[
          _buildSectionHeader('Credit Cards', Icons.credit_card),
          ...creditCards.map(_buildAccountTile),
        ],
        if (wallets.isNotEmpty) ...[
          _buildSectionHeader('Wallets & UPI', Icons.wallet),
          ...wallets.map(_buildAccountTile),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTile(Account account) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getAccountColor(account.type).withValues(alpha: 0.2),
          child: Icon(
            _getAccountIcon(account.type),
            color: _getAccountColor(account.type),
          ),
        ),
        title: Text(account.name),
        subtitle: Text(
          account.last4Digits != null
              ? '••••${account.last4Digits}'
              : account.typeLabel,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (account.isManuallyAdded)
              const Chip(
                label: Text('Manual', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  await _confirmDelete(account);
                } else if (value == 'edit') {
                  await _showEditAccountDialog(account);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
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
        return Icons.wallet;
      case AccountType.upi:
        return Icons.phone_android;
    }
  }

  Color _getAccountColor(AccountType type) {
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

  Future<void> _confirmDelete(Account account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text('Are you sure you want to delete "${account.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LocalStorageService.deleteAccount(account.id);
      await _loadAccounts();
    }
  }

  Future<void> _showAddAccountDialog() async {
    final result = await showDialog<Account>(
      context: context,
      builder: (context) => const _AccountFormDialog(),
    );

    if (result != null) {
      await LocalStorageService.saveAccount(result);
      await _loadAccounts();
    }
  }

  Future<void> _showEditAccountDialog(Account account) async {
    final result = await showDialog<Account>(
      context: context,
      builder: (context) => _AccountFormDialog(account: account),
    );

    if (result != null) {
      await LocalStorageService.saveAccount(result);
      await _loadAccounts();
    }
  }
}

class _AccountFormDialog extends StatefulWidget {
  final Account? account;

  const _AccountFormDialog({this.account});

  @override
  State<_AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends State<_AccountFormDialog> {
  late TextEditingController _nameController;
  late TextEditingController _last4Controller;
  late TextEditingController _bankNameController;
  AccountType _selectedType = AccountType.bankAccount;

  bool get isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account?.name ?? '');
    _last4Controller =
        TextEditingController(text: widget.account?.last4Digits ?? '');
    _bankNameController =
        TextEditingController(text: widget.account?.bankName ?? '');
    _selectedType = widget.account?.type ?? AccountType.bankAccount;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _last4Controller.dispose();
    _bankNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEditing ? 'Edit Account' : 'Add Account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Account Name *',
                hintText: 'e.g., HDFC Savings, OneCard',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AccountType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(labelText: 'Account Type'),
              items: AccountType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_getTypeLabel(type)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedType = value);
              },
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
            const SizedBox(height: 8),
            TextField(
              controller: _bankNameController,
              decoration: const InputDecoration(
                labelText: 'Bank/Issuer Name',
                hintText: 'e.g., HDFC, Bank of Baroda',
              ),
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
          onPressed: _save,
          child: Text(isEditing ? 'Save' : 'Add'),
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

  void _save() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter account name')),
      );
      return;
    }

    final account = Account(
      id: widget.account?.id ??
          'manual_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      type: _selectedType,
      last4Digits: _last4Controller.text.isNotEmpty
          ? _last4Controller.text.trim()
          : null,
      bankName: _bankNameController.text.isNotEmpty
          ? _bankNameController.text.trim()
          : null,
      isManuallyAdded: true,
      createdAt: widget.account?.createdAt ?? DateTime.now(),
    );

    Navigator.pop(context, account);
  }
}
