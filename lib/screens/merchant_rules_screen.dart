import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/standard_category.dart';
import '../models/transaction_review.dart';
import '../models/merchant_rule_suggestion.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';

class _RecurringRuleTemplate {
  const _RecurringRuleTemplate(this.label, this.merchant, this.categoryId);

  final String label;
  final String merchant;
  final String categoryId;
}

const _recurringRuleTemplates = <_RecurringRuleTemplate>[
  _RecurringRuleTemplate('Rent', 'Rent payment', 'rent_housing'),
  _RecurringRuleTemplate('Loan or EMI', 'Loan repayment', 'emi_loans'),
  _RecurringRuleTemplate('Family support', 'Family support', 'family_support'),
  _RecurringRuleTemplate('Chitti', 'Chitti payment', 'chitti_commitments'),
  _RecurringRuleTemplate('Insurance', 'Insurance premium', 'insurance'),
  _RecurringRuleTemplate('Utilities', 'Utility bill', 'bills_utilities'),
  _RecurringRuleTemplate('Card bill', 'Credit card bill', 'credit_card_bills'),
  _RecurringRuleTemplate('Education', 'Education payment', 'education'),
];

class MerchantRulesScreen extends StatefulWidget {
  const MerchantRulesScreen({super.key});

  @override
  State<MerchantRulesScreen> createState() => _MerchantRulesScreenState();
}

class _MerchantRulesScreenState extends State<MerchantRulesScreen> {
  static const _uuid = Uuid();

  List<MerchantRule> _rules = const [];
  List<StandardCategory> _categories = const [];
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
        LocalStorageService.getAllStandardCategories(activeOnly: true),
      ]);
      if (!mounted) return;
      setState(() {
        _rules = results[0] as List<MerchantRule>;
        _categories = results[1] as List<StandardCategory>;
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

  Future<void> _showEditor({
    MerchantRule? existing,
    _RecurringRuleTemplate? template,
  }) async {
    final rule = await showModalBottomSheet<MerchantRule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _MerchantRuleEditor(
        existing: existing,
        template: template,
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
              rule);
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
            'Delete the rule for messages containing "${rule.matchText}"?'),
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
    final category =
        _categories.where((item) => item.id == rule.standardCategoryId);
    return category.isEmpty ? 'No category' : category.first.displayName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Cleanup Rules'),
        actions: [
          IconButton(
            onPressed: _isLoading || _isBusy ? null : () => _showEditor(),
            icon: const Icon(Icons.add),
            tooltip: 'Add merchant rule',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _LoadError(message: _loadError!, onRetry: _load)
              : _rules.isEmpty
                  ? _EmptyRules(onCreate: () => _showEditor())
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rules.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Suggested rules start off. Enable a rule for new SMS. '
                                  'Applying it to existing transactions needs a separate confirmation.',
                                ),
                                const SizedBox(height: 16),
                                Text('Recurring payment templates',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 4),
                                const Text(
                                  'For rent, loans, and personal payees, enter a unique phrase '
                                  'from an actual SMS. The export does not include SMS text.',
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _recurringRuleTemplates
                                      .map((template) => ActionChip(
                                            label: Text(template.label),
                                            onPressed: _isBusy
                                                ? null
                                                : () => _showEditor(
                                                    template: template),
                                          ))
                                      .toList(),
                                ),
                                const SizedBox(height: 12),
                                Text('Saved rules',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ],
                            ),
                          );
                        }
                        final rule = _rules[index - 1];
                        final suggestion =
                            MerchantRuleSuggestions.byId(rule.id);
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        rule.merchant,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _isBusy
                                          ? null
                                          : () => _showEditor(existing: rule),
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: 'Edit rule',
                                    ),
                                    if (suggestion == null)
                                      IconButton(
                                        onPressed: _isBusy
                                            ? null
                                            : () => _delete(rule),
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: 'Delete rule',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('When SMS contains: ${rule.matchText}'),
                                if (suggestion != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    rule.matchText == suggestion.matchText &&
                                            rule.standardCategoryId ==
                                                suggestion.standardCategoryId
                                        ? suggestion.reason
                                        : 'Customized suggested rule. Review matching SMS before enabling.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _RuleChip(label: _categoryLabel(rule)),
                                    if (suggestion != null)
                                      const _RuleChip(label: 'Suggested'),
                                    if (rule.tag != null)
                                      _RuleChip(label: 'Tag: ${rule.tag}'),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Expanded(
                                        child: Text('Use for new SMS')),
                                    Switch.adaptive(
                                      value: rule.isEnabled,
                                      onChanged: _isBusy
                                          ? null
                                          : (enabled) =>
                                              _setEnabled(rule, enabled),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: rule.isEnabled && !_isBusy
                                      ? () => _applyToExisting(rule)
                                      : null,
                                  icon: const Icon(Icons.auto_fix_high_outlined,
                                      size: 18),
                                  label: const Text(
                                      'Apply to Existing Transactions'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: _rules.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _isBusy ? null : () => _showEditor(),
              child: const Icon(Icons.add),
            ),
    );
  }
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
    required this.template,
    required this.categories,
    required this.newRuleId,
  });

  final MerchantRule? existing;
  final _RecurringRuleTemplate? template;
  final List<StandardCategory> categories;
  final String newRuleId;

  @override
  State<_MerchantRuleEditor> createState() => _MerchantRuleEditorState();
}

class _MerchantRuleEditorState extends State<_MerchantRuleEditor> {
  late final TextEditingController _matchController;
  late final TextEditingController _merchantController;
  late final TextEditingController _tagController;
  late String _standardCategoryId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _matchController =
        TextEditingController(text: widget.existing?.matchText ?? '');
    _merchantController = TextEditingController(
      text: widget.existing?.merchant ?? widget.template?.merchant ?? '',
    );
    _tagController = TextEditingController(text: widget.existing?.tag ?? '');
    _standardCategoryId = widget.existing?.standardCategoryId ??
        widget.template?.categoryId ??
        '';
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
          () => _error = 'Enter both the SMS text to match and merchant name.');
      return;
    }

    Navigator.pop(
      context,
      MerchantRule(
        id: widget.existing?.id ?? widget.newRuleId,
        matchText: matchText,
        merchant: merchant,
        standardCategoryId:
            _standardCategoryId.isEmpty ? null : _standardCategoryId,
        tag: tag.isEmpty ? null : tag,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        isEnabled: widget.existing?.isEnabled ?? widget.template == null,
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
            if (widget.template != null) ...[
              const SizedBox(height: 6),
              const Text(
                'Use an exact payee, VPA, or lender phrase from a real SMS. '
                'This rule will start disabled so you can review it first.',
              ),
            ],
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
              initialValue: _standardCategoryId,
              decoration:
                  const InputDecoration(labelText: 'Category (optional)'),
              items: [
                const DropdownMenuItem(
                    value: '', child: Text('No category rule')),
                ...widget.categories.map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text('${category.emoji} ${category.displayName}'),
                  ),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _standardCategoryId = value ?? ''),
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
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

class _EmptyRules extends StatelessWidget {
  const _EmptyRules({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_fix_high_outlined,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('No merchant rules yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Create a rule to normalize future SMS and clean matching transactions you already have.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Rule'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
