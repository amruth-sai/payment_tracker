import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_category.dart';
import '../models/transaction.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';
import '../services/transaction_window_service.dart';
import 'categories_screen.dart';

enum _WindowMode { dates, transactions }

class TransactionWindowCategoryScreen extends StatefulWidget {
  const TransactionWindowCategoryScreen({super.key});

  @override
  State<TransactionWindowCategoryScreen> createState() =>
      _TransactionWindowCategoryScreenState();
}

class _TransactionWindowCategoryScreenState
    extends State<TransactionWindowCategoryScreen> {
  late final List<Transaction> _transactions;
  final _tagController = TextEditingController();
  List<AppCategory> _categories = const [];
  _WindowMode _mode = _WindowMode.dates;
  DateTimeRange? _dateRange;
  Transaction? _firstTransaction;
  Transaction? _lastTransaction;
  String? _categoryId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _transactions = List.of(context.read<SmsService>().transactions);
    _loadCategories();
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await LocalStorageService.getAllCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (!categories.any((cat) => cat.id == _categoryId)) {
          _categoryId = null;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load Categories.')),
      );
    }
  }

  List<Transaction> _selectedTransactions() {
    if (_mode == _WindowMode.dates) {
      final range = _dateRange;
      return range == null
          ? const []
          : TransactionWindowService.byDateRange(
              _transactions,
              range.start,
              range.end,
            );
    }
    if (_firstTransaction == null || _lastTransaction == null) return const [];
    return TransactionWindowService.betweenTransactions(
      _transactions,
      _firstTransaction!.id,
      _lastTransaction!.id,
    );
  }

  Future<void> _chooseDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDateRange: _dateRange,
      helpText: 'Select the trip dates',
    );
    if (range != null && mounted) setState(() => _dateRange = range);
  }

  Future<void> _chooseTransaction({required bool first}) async {
    final selected = await showSearch<Transaction?>(
      context: context,
      delegate: _TransactionBoundarySearch(_transactions),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (first) {
        _firstTransaction = selected;
      } else {
        _lastTransaction = selected;
      }
    });
  }

  Future<void> _manageCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriesScreen()),
    );
    if (mounted) await _loadCategories();
  }

  Future<void> _apply() async {
    if (_saving || _categoryId == null) return;
    final selected = _selectedTransactions();
    final tag = _tagController.text.trim();
    if (selected.isEmpty || tag.isEmpty) return;
    final category = _categories.firstWhere((cat) => cat.id == _categoryId);
    final existingCategories = selected
        .where((tx) => tx.categoryId != null && tx.categoryId != category.id)
        .length;
    final existingTags = selected
        .where((tx) => tx.tag != null && tx.tag!.trim() != tag)
        .length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply to This Window?'),
        content: Text(
          '${selected.length} active transactions will receive '
          'Category “${category.name}” and tag “$tag”.\n\n'
          '$existingCategories already have a Category; '
          '$existingTags already have a tag. Those labels will be replaced. '
          'Amounts and debit/credit remain as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apply to all selected'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final updated = await LocalStorageService.applyCategoryToTransactions(
        transactionIds: selected.map((tx) => tx.id),
        categoryId: category.id,
        tag: tag,
      );
      if (!mounted) return;
      await context.read<SmsService>().reloadFromCache();
      if (mounted) Navigator.pop(context, updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not apply the category window.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedTransactions();
    final format = DateFormat('d MMM y, h:mm a');
    final outCount = selected.where((tx) => tx.isDebit).length;
    final inCount = selected.where((tx) => tx.isCredit).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Categorize a Trip Window')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Choose dates or two boundary transactions. Every active '
                  'transaction in the window is included, even if a search or '
                  'tab filter is selected on the transaction list.',
                ),
                const SizedBox(height: 20),
                SegmentedButton<_WindowMode>(
                  segments: const [
                    ButtonSegment(
                      value: _WindowMode.dates,
                      icon: Icon(Icons.date_range_outlined),
                      label: Text('Dates'),
                    ),
                    ButtonSegment(
                      value: _WindowMode.transactions,
                      icon: Icon(Icons.receipt_long_outlined),
                      label: Text('Transactions'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (values) =>
                      setState(() => _mode = values.first),
                ),
                const SizedBox(height: 12),
                if (_mode == _WindowMode.dates)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Trip date range'),
                      subtitle: Text(
                        _dateRange == null
                            ? 'Choose first and last day'
                            : '${DateFormat.yMMMd().format(_dateRange!.start)} – '
                                  '${DateFormat.yMMMd().format(_dateRange!.end)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _chooseDates,
                    ),
                  )
                else ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.first_page),
                      title: const Text('First boundary transaction'),
                      subtitle: Text(
                        _firstTransaction == null
                            ? 'Search and select a transaction'
                            : '${_firstTransaction!.displayName} · '
                                  '${format.format(_firstTransaction!.date)}',
                      ),
                      onTap: () => _chooseTransaction(first: true),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.last_page),
                      title: const Text('Last boundary transaction'),
                      subtitle: Text(
                        _lastTransaction == null
                            ? 'Search and select a transaction'
                            : '${_lastTransaction!.displayName} · '
                                  '${format.format(_lastTransaction!.date)}',
                      ),
                      onTap: () => _chooseTransaction(first: false),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 4),
                    child: Text('Both boundary transactions are included.'),
                  ),
                ],
                const SizedBox(height: 20),
                Text('Preview', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: selected.isEmpty
                        ? const Text(
                            'Select a window to preview its transactions.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${selected.length} transactions · '
                                '$outCount out · $inCount in',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${format.format(selected.first.date)} – '
                                '${format.format(selected.last.date)}',
                              ),
                              const Divider(height: 20),
                              ...selected
                                  .take(5)
                                  .map(
                                    (tx) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '${DateFormat.MMMd().format(tx.date)} · '
                                        '${tx.displayName} · '
                                        '${tx.typeLabel} ${tx.amount.toStringAsFixed(2)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              if (selected.length > 5)
                                Text('…and ${selected.length - 5} more'),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: ValueKey(_categoryId),
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text('${category.emoji} ${category.name}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _manageCategories,
                    icon: const Icon(Icons.add),
                    label: const Text('Create or manage Categories'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tagController,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Trip tag',
                    hintText: 'Example: Goa October 2026',
                    border: OutlineInputBorder(),
                    helperText:
                        'The same tag will be added to every selected transaction.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed:
                      _saving ||
                          selected.isEmpty ||
                          _categoryId == null ||
                          _tagController.text.trim().isEmpty
                      ? null
                      : _apply,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_all),
                  label: const Text('Apply Category and tag'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _TransactionBoundarySearch extends SearchDelegate<Transaction?> {
  _TransactionBoundarySearch(this.transactions)
    : super(searchFieldLabel: 'Search merchant, amount, or date');

  final List<Transaction> transactions;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) => _matches(context);

  @override
  Widget buildSuggestions(BuildContext context) => _matches(context);

  Widget _matches(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final ordered = transactions.toList()
      ..sort((a, b) => TransactionWindowService.compareByDateAndId(b, a));
    final matches = needle.isEmpty
        ? ordered
        : ordered.where((tx) {
            final date = DateFormat('d MMM y').format(tx.date).toLowerCase();
            return tx.displayName.toLowerCase().contains(needle) ||
                tx.sender.toLowerCase().contains(needle) ||
                tx.amount.toStringAsFixed(2).contains(needle) ||
                date.contains(needle);
          }).toList();
    if (matches.isEmpty) {
      return const Center(child: Text('No matching transactions.'));
    }
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final tx = matches[index];
        return ListTile(
          title: Text(
            tx.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${DateFormat('d MMM y, h:mm a').format(tx.date)} · '
            '${tx.typeLabel} ${tx.amount.toStringAsFixed(2)}',
          ),
          onTap: () => close(context, tx),
        );
      },
    );
  }
}
