import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../models/salary_cycle.dart';
import '../models/merged_transfer.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';
import '../services/transfer_service.dart';
import '../widgets/transaction_card.dart';
import '../widgets/merged_transfer_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import '../utils/date_utils.dart';
import 'transaction_window_category_screen.dart';
import 'categories_screen.dart';

class AllTransactionsScreen extends StatefulWidget {
  const AllTransactionsScreen({super.key, this.filter = 0});
  final int filter;
  @override
  State<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends State<AllTransactionsScreen> {
  late int _direction;
  String _search = '';
  String? _sender;
  String? _category;
  String? _tag;
  String? _cycleId;
  String _sort = 'date';
  List<SalaryCycle> _cycles = [];

  @override
  void initState() {
    super.initState();
    _direction = widget.filter;
    _loadCycles();
  }

  Future<void> _loadCycles() async {
    try {
      final cycles = await LocalStorageService.getAllSalaryCycles();
      if (mounted) setState(() => _cycles = cycles);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load salary periods.')),
        );
      }
    }
  }

  Future<void> _edit(Transaction tx, {bool ignore = false}) async {
    try {
      if (ignore) {
        await LocalStorageService.updateTransactionIgnored(tx.id, true);
      } else {
        if (tx.isPartOfTransfer) await TransferService.unmergeTransfer(tx);
        await LocalStorageService.updateTransactionType(
          tx.id,
          tx.isCredit ? TransactionType.debit : TransactionType.credit,
        );
      }
      if (!mounted) return;
      await context.read<SmsService>().reloadFromCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ignore ? 'Transaction ignored' : 'Direction updated'),
          action: ignore
              ? SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    await LocalStorageService.updateTransactionIgnored(
                      tx.id,
                      false,
                    );
                    if (mounted) {
                      await context.read<SmsService>().reloadFromCache();
                    }
                  },
                )
              : null,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this transaction.')),
        );
      }
    }
  }

  Future<void> _openTransfer(MergedTransfer transfer) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Transfer', style: Theme.of(context).textTheme.titleLarge),
              TransactionCard(
                tx: transfer.sourceTransaction,
                onTap: () => TransactionDetailSheet.show(
                  context,
                  transfer.sourceTransaction,
                ),
              ),
              TransactionCard(
                tx: transfer.destinationTransaction,
                onTap: () => TransactionDetailSheet.show(
                  context,
                  transfer.destinationTransaction,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await TransferService.unmergeTransfer(
                    transfer.sourceTransaction,
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  if (mounted) {
                    await context.read<SmsService>().reloadFromCache();
                  }
                },
                child: const Text('Unlink transfer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sms = context.watch<SmsService>();
    final categories = sms.categoriesById;
    final all = sms.transactions;
    final senders = all.map((tx) => tx.sender).toSet().toList()..sort();
    final tags = all.map((tx) => tx.tag).whereType<String>().toSet().toList()
      ..sort();
    final cycle = _cycles.where((cycle) => cycle.id == _cycleId).firstOrNull;
    final filtered = all.where((tx) {
      if (_direction == 1 && !tx.isCredit || _direction == 2 && !tx.isDebit) {
        return false;
      }
      if (_sender != null && tx.sender != _sender) return false;
      if (_category != null && (tx.categoryId ?? '') != _category) return false;
      if (_tag != null && tx.tag != _tag) return false;
      if (cycle != null && !cycle.contains(tx.date)) return false;
      final text =
          '${tx.displayName} ${tx.sender} ${tx.note ?? ''} ${tx.tag ?? ''} ${tx.amount} ${tx.referenceId ?? ''}'
              .toLowerCase();
      return text.contains(_search);
    }).toList();
    final items = <Object>[
      ...TransferService.getMergedTransfers(filtered),
      ...TransferService.getStandaloneTransactions(filtered),
    ];
    DateTime dateOf(Object item) =>
        item is Transaction ? item.date : (item as MergedTransfer).date;
    double amountOf(Object item) =>
        item is Transaction ? item.amount : (item as MergedTransfer).amount;
    items.sort(
      (a, b) => _sort == 'date'
          ? dateOf(b).compareTo(dateOf(a))
          : _sort == 'amount_up'
          ? amountOf(a).compareTo(amountOf(b))
          : amountOf(b).compareTo(amountOf(a)),
    );
    // Headers and payments are individual lazy rows, including on busy days.
    final rows = <Object>[];
    String? lastDay;
    for (final item in items) {
      if (_sort == 'date') {
        final day = AppDateUtils.formatDateKey(dateOf(item));
        if (lastDay != day) {
          rows.add(day);
          lastDay = day;
        }
      }
      rows.add(item);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: 'Manage categories',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CategoriesScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Categorize a date or transaction window',
            icon: const Icon(Icons.date_range),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TransactionWindowCategoryScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search merchant, amount, notes or reference',
              ),
              onChanged: (value) =>
                  setState(() => _search = value.toLowerCase().trim()),
            ),
          ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('All')),
              ButtonSegment(value: 1, label: Text('Money in')),
              ButtonSegment(value: 2, label: Text('Money out')),
            ],
            selected: {_direction},
            onSelectionChanged: (value) =>
                setState(() => _direction = value.first),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _filter<String>(
                  'All senders',
                  senders,
                  _sender,
                  (value) => value,
                  (value) => setState(() => _sender = value),
                ),
                _filter<String>(
                  'All categories',
                  ['', ...categories.keys],
                  categories.containsKey(_category) || _category == ''
                      ? _category
                      : null,
                  (value) => categories[value]?.name ?? 'Uncategorized',
                  (value) => setState(() => _category = value),
                ),
                _filter<String>(
                  'All tags',
                  tags,
                  _tag,
                  (value) => value,
                  (value) => setState(() => _tag = value),
                ),
                _filter<String>(
                  'All periods',
                  _cycles.map((c) => c.id).toList(),
                  _cycleId,
                  (value) =>
                      _cycles.firstWhere((c) => c.id == value).cycleLabel,
                  (value) => setState(() => _cycleId = value),
                ),
                DropdownButton<String>(
                  value: _sort,
                  items: const [
                    DropdownMenuItem(
                      value: 'date',
                      child: Text('Newest first'),
                    ),
                    DropdownMenuItem(
                      value: 'amount_up',
                      child: Text('Amount low to high'),
                    ),
                    DropdownMenuItem(
                      value: 'amount_down',
                      child: Text('Amount high to low'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _sort = value!),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No matching transactions'))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final item = rows[index];
                      if (item is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            item,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        );
                      }
                      if (item is MergedTransfer) {
                        return MergedTransferCard(
                          mergedTransfer: item,
                          onTap: () => _openTransfer(item),
                        );
                      }
                      final tx = item as Transaction;
                      return TransactionCard(
                        tx: tx,
                        accountDisplayName: sms.getAccountDisplayName(
                          tx.accountId,
                          tx.accountLast4,
                        ),
                        onTap: () => TransactionDetailSheet.show(context, tx),
                        onSwipeIgnore: (tx) => _edit(tx, ignore: true),
                        onSwipeToggleType: _edit,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filter<T>(
    String title,
    List<T> values,
    T? selected,
    String Function(T) label,
    ValueChanged<T?> changed,
  ) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: DropdownButton<T>(
      value: values.contains(selected) ? selected : null,
      hint: Text(title),
      items: [
        DropdownMenuItem<T>(child: Text(title)),
        ...values.map(
          (value) =>
              DropdownMenuItem<T>(value: value, child: Text(label(value))),
        ),
      ],
      onChanged: changed,
    ),
  );
}
