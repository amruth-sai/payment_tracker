import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/app_category.dart';
import '../models/transaction_review.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';
import 'categories_screen.dart';

class MerchantRulesScreen extends StatefulWidget {
  const MerchantRulesScreen({super.key});

  @override
  State<MerchantRulesScreen> createState() => _MerchantRulesScreenState();
}

class _MerchantRulesScreenState extends State<MerchantRulesScreen> {
  static const _uuid = Uuid();

  List<MerchantRule> _rules = const [];
  List<AppCategory> _categories = const [];
  bool _isLoading = true;
  bool _isBusy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        LocalStorageService.getMerchantRules(),
        LocalStorageService.getAllCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _rules = results[0] as List<MerchantRule>;
        _categories = results[1] as List<AppCategory>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load merchant rules.';
      });
    }
  }

  Future<void> _showEditor({MerchantRule? existing}) async {
    final rule = await showModalBottomSheet<MerchantRule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _MerchantRuleEditor(
        existing: existing,
        categories: _categories,
        newRuleId: _uuid.v4(),
      ),
    );
    if (rule == null) return;

    await LocalStorageService.saveMerchantRule(rule);
    if (!mounted) return;
    await _load();
  }

  Future<void> _applyToExisting(MerchantRule rule) async {
    if (!rule.isEnabled || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      final count =
          await LocalStorageService.countTransactionsMatchingMerchantRule(rule);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Apply Rule to Existing Transactions?'),
          content: Text(
            'SMS contains: ${rule.matchText}\n'
            'Matching transactions: $count\n'
            'Merchant: ${rule.merchant}\n'
            'Category: ${_categoryLabel(rule)}\n\n'
            'This can replace existing merchant names and tags. It changes '
            'categories except ones you chose manually. Amounts and '
            'debit/credit stay unchanged. Disabling the rule later will not '
            'undo these changes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: count == 0 ? null : () => Navigator.pop(context, true),
              child: const Text('Apply to all matches'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final updated =
          await LocalStorageService.applyMerchantRuleToExistingTransactions(
            rule,
          );
      if (!mounted) return;
      await context.read<SmsService>().reloadFromCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated $updated existing transactions.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not apply this merchant rule.')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _setEnabled(MerchantRule rule, bool enabled) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await LocalStorageService.saveMerchantRule(
        rule.copyWith(isEnabled: enabled),
      );
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update this merchant rule.')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _delete(MerchantRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Merchant Rule?'),
        content: Text(
          'Delete the rule for messages containing "${rule.matchText}"?',
        ),
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
    if (confirmed != true) return;

    await LocalStorageService.deleteMerchantRule(rule.id);
    if (!mounted) return;
    await _load();
  }

  String _categoryLabel(MerchantRule rule) {
    final category = _categories.where((item) => item.id == rule.categoryId);
    return category.isEmpty ? 'No category' : category.first.name;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Merchant rules'),
      actions: [
        IconButton(
          tooltip: 'Manage categories',
          icon: const Icon(Icons.category_outlined),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CategoriesScreen()),
            );
            if (mounted) await _load();
          },
        ),
      ],
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _loadError != null
        ? _LoadError(message: _loadError!, onRetry: _load)
        : _rules.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No merchant rules yet. Add a rule to match SMS text, name a merchant, and optionally assign one of your categories.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: _rules.length,
            itemBuilder: (context, index) {
              final rule = _rules[index];
              return Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(rule.merchant),
                        subtitle: Text('SMS contains: ${rule.matchText}'),
                        trailing: Switch(
                          value: rule.isEnabled,
                          onChanged: _isBusy
                              ? null
                              : (value) => _setEnabled(rule, value),
                        ),
                      ),
                      Text(_categoryLabel(rule)),
                      if (rule.tag != null) Text('Tag: ${rule.tag}'),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _isBusy
                                ? null
                                : () => _showEditor(existing: rule),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            onPressed: _isBusy ? null : () => _delete(rule),
                            child: const Text('Delete'),
                          ),
                          OutlinedButton(
                            onPressed: !rule.isEnabled || _isBusy
                                ? null
                                : () => _applyToExisting(rule),
                            child: const Text('Apply to existing'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _isBusy ? null : () => _showEditor(),
      icon: const Icon(Icons.add),
      label: const Text('Add rule'),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _MerchantRuleEditor extends StatefulWidget {
  const _MerchantRuleEditor({
    required this.existing,
    required this.categories,
    required this.newRuleId,
  });

  final MerchantRule? existing;
  final List<AppCategory> categories;
  final String newRuleId;

  @override
  State<_MerchantRuleEditor> createState() => _MerchantRuleEditorState();
}

class _MerchantRuleEditorState extends State<_MerchantRuleEditor> {
  late final TextEditingController _matchController;
  late final TextEditingController _merchantController;
  late final TextEditingController _tagController;
  late String _categoryId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _matchController = TextEditingController(
      text: widget.existing?.matchText ?? '',
    );
    _merchantController = TextEditingController(
      text: widget.existing?.merchant ?? '',
    );
    _tagController = TextEditingController(text: widget.existing?.tag ?? '');
    _categoryId = widget.existing?.categoryId ?? '';
  }

  @override
  void dispose() {
    _matchController.dispose();
    _merchantController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _save() {
    final matchText = _matchController.text.trim();
    final merchant = _merchantController.text.trim();
    final tag = _tagController.text.trim();
    if (matchText.isEmpty || merchant.isEmpty) {
      setState(
        () => _error = 'Enter both the SMS text to match and merchant name.',
      );
      return;
    }

    Navigator.pop(
      context,
      MerchantRule(
        id: widget.existing?.id ?? widget.newRuleId,
        matchText: matchText,
        merchant: merchant,
        categoryId: _categoryId.isEmpty ? null : _categoryId,
        tag: tag.isEmpty ? null : tag,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        isEnabled: widget.existing?.isEnabled ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Edit Merchant Rule' : 'New Merchant Rule',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _matchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'When SMS contains',
                hintText: 'Example: SWIGGY',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: 'Merchant name',
                hintText: 'Example: Swiggy',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('No category rule'),
                ),
                ...widget.categories.map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text('${category.emoji} ${category.name}'),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _categoryId = value ?? ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagController,
              decoration: const InputDecoration(
                labelText: 'Tag (optional)',
                hintText: 'Example: Dining',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(isEdit ? 'Save Changes' : 'Create Rule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
