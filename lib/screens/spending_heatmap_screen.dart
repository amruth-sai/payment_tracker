import 'package:flutter/material.dart';
import '../models/app_category.dart';
import '../models/salary_cycle.dart';
import '../models/transaction.dart';
import '../services/local_storage_service.dart';
import '../utils/format_utils.dart';
import '../utils/money.dart';
import '../utils/transaction_filters.dart';

class SpendingHeatmapScreen extends StatefulWidget {
  const SpendingHeatmapScreen({super.key});

  @override
  State<SpendingHeatmapScreen> createState() => _SpendingHeatmapScreenState();
}

class _SpendingHeatmapScreenState extends State<SpendingHeatmapScreen> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<Transaction> _allTransactions = [];
  Map<String, AppCategory> _categories = {};
  List<SalaryCycle> _cycles = [];
  final _searchController = TextEditingController();
  final _senders = <String>{};
  final _categoryIds = <String>{};
  final _tags = <String>{};
  String _search = '';
  String? _cycleId;
  int _direction = 2; // Keep the existing spending-only view as the default.
  bool _includeTransfers = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        LocalStorageService.getTrackedTransactions(),
        LocalStorageService.getAllCategories(),
        LocalStorageService.getAllSalaryCycles(),
      ]);
      if (!mounted) return;
      setState(() {
        _allTransactions = results[0] as List<Transaction>;
        _categories = {
          for (final category in results[1] as List<AppCategory>)
            category.id: category,
        };
        _cycles = results[2] as List<SalaryCycle>;
        if (!_cycles.any((cycle) => cycle.id == _cycleId)) _cycleId = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load heatmap transactions. Please try again.';
        _isLoading = false;
      });
    }
  }

  List<Transaction> _matching({
    bool includeSenders = true,
    bool includeCategories = true,
    bool includeTags = true,
  }) {
    final cycle = _cycles.where((cycle) => cycle.id == _cycleId).firstOrNull;
    final eligible = _allTransactions.where((tx) {
      if (tx.isIgnored ||
          tx.date.year != _currentMonth.year ||
          tx.date.month != _currentMonth.month) {
        return false;
      }
      return _includeTransfers
          ? tx.isDebit || tx.isCredit
          : tx.isExpense || tx.isIncome;
    });
    return filterTransactions(
      eligible,
      direction: _direction,
      senders: includeSenders ? _senders : const {},
      categories: includeCategories ? _categoryIds : const {},
      tags: includeTags ? _tags : const {},
      cycle: cycle,
      search: _search,
    );
  }

  String _categoryLabel(String id) => id.isEmpty
      ? 'Uncategorized'
      : _categories[id]?.name ?? 'Deleted category';

  List<String> _options(
    Iterable<String> values,
    Set<String> selected, {
    String Function(String)? label,
  }) {
    return {...values, ...selected}.toList()..sort(
      (a, b) => (label?.call(a) ?? a).toLowerCase().compareTo(
        (label?.call(b) ?? b).toLowerCase(),
      ),
    );
  }

  bool get _hasFilters =>
      _direction != 2 ||
      _includeTransfers ||
      _search.isNotEmpty ||
      _senders.isNotEmpty ||
      _categoryIds.isNotEmpty ||
      _tags.isNotEmpty ||
      _cycleId != null;

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _direction = 2;
      _includeTransfers = false;
      _search = '';
      _senders.clear();
      _categoryIds.clear();
      _tags.clear();
      _cycleId = null;
    });
  }

  Color get _heatColor => switch (_direction) {
    1 => Colors.green.shade700,
    2 => Colors.red.shade700,
    _ => Theme.of(context).colorScheme.primary,
  };

  String get _metric => switch (_direction) {
    1 => 'money in',
    2 => 'money out',
    _ => 'activity',
  };

  @override
  Widget build(BuildContext context) {
    final matching = _matching();
    final daily = <int, double>{};
    for (final tx in matching) {
      daily[tx.date.day] = Money.sum([daily[tx.date.day] ?? 0, tx.amount]);
    }
    final maxDaily = daily.values.fold<double>(
      0,
      (peak, amount) => amount > peak ? amount : peak,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending Heatmap'),
        actions: [
          TextButton(
            key: const ValueKey('heatmap-reset'),
            onPressed: _hasFilters ? _resetFilters : null,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadData,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                key: const PageStorageKey('heatmap-scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFilters(),
                        _buildMonthSelector(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '${matching.length} matching transactions. ${_direction == 0 ? 'All adds credit and debit amounts. ' : ''}${_includeTransfers ? 'Internal transfers included.' : 'Internal transfers excluded.'}',
                            key: const ValueKey('heatmap-matches'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (_cycleId != null)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                            child: Text(
                              'The selected salary cycle and calendar month both apply.',
                            ),
                          ),
                        _buildLegend(),
                        _buildCalendarGrid(daily, maxDaily, matching),
                        _buildMonthSummary(daily),
                        if (matching.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Text(
                              'No transactions match this month and these filters.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilters() {
    final senders = _options(
      _matching(includeSenders: false).map((tx) => tx.sender),
      _senders,
    );
    final categories = _options(
      _matching(includeCategories: false).map((tx) => tx.categoryId ?? ''),
      _categoryIds,
      label: _categoryLabel,
    );
    final tags = _options(
      _matching(
        includeTags: false,
      ).map((tx) => tx.tag).whereType<String>().where((tag) => tag.isNotEmpty),
      _tags,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SearchBar(
            controller: _searchController,
            hintText: 'Search merchant, bank, amount or notes...',
            leading: const Icon(Icons.search_rounded),
            onChanged: (value) =>
                setState(() => _search = value.toLowerCase().trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in {
                0: 'All',
                1: 'Money In',
                2: 'Money Out',
              }.entries)
                ChoiceChip(
                  key: ValueKey('heatmap-direction-${entry.key}'),
                  label: Text(entry.value),
                  selected: _direction == entry.key,
                  onSelected: (_) => setState(() => _direction = entry.key),
                ),
              FilterChip(
                key: const ValueKey('heatmap-transfers'),
                avatar: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Include internal transfers'),
                selected: _includeTransfers,
                onSelected: (value) =>
                    setState(() => _includeTransfers = value),
              ),
            ],
          ),
        ),
        if (senders.isNotEmpty)
          _chipRow(
            'banks',
            'All Banks',
            Icons.account_balance,
            senders,
            _senders,
            (id) => id,
          ),
        if (categories.isNotEmpty)
          _chipRow(
            'categories',
            'All Categories',
            Icons.category_outlined,
            categories,
            _categoryIds,
            _categoryLabel,
          ),
        if (tags.isNotEmpty)
          _chipRow(
            'tags',
            'All Tags',
            Icons.sell_outlined,
            tags,
            _tags,
            (id) => id,
          ),
        if (_cycles.isNotEmpty)
          _chipStrip('periods', [
            FilterChip(
              key: const ValueKey('heatmap-period-all'),
              label: const Text('All Time'),
              selected: _cycleId == null,
              onSelected: (_) => setState(() => _cycleId = null),
            ),
            for (final cycle in _cycles)
              FilterChip(
                key: ValueKey('heatmap-period-${cycle.id}'),
                label: Text(cycle.cycleLabel),
                selected: _cycleId == cycle.id,
                onSelected: (_) => setState(
                  () => _cycleId = _cycleId == cycle.id ? null : cycle.id,
                ),
              ),
          ]),
      ],
    );
  }

  Widget _chipRow(
    String id,
    String allLabel,
    IconData icon,
    List<String> options,
    Set<String> selected,
    String Function(String) label,
  ) => _chipStrip(id, [
    FilterChip(
      key: ValueKey('heatmap-$id-all'),
      avatar: Icon(icon, size: 16),
      label: Text(allLabel),
      selected: selected.isEmpty,
      onSelected: (_) => setState(selected.clear),
    ),
    for (final value in options)
      FilterChip(
        key: ValueKey('heatmap-$id-$value'),
        avatar: id == 'categories' && _categories[value] != null
            ? Text(_categories[value]!.emoji)
            : null,
        label: Text(label(value)),
        selected: selected.contains(value),
        onSelected: (enabled) => setState(() {
          if (enabled) {
            selected.add(value);
          } else {
            selected.remove(value);
          }
        }),
      ),
  ]);

  Widget _chipStrip(String id, List<Widget> chips) => SizedBox(
    height: 28 + MediaQuery.textScalerOf(context).scale(24),
    child: ListView(
      key: PageStorageKey('heatmap-filter-$id'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final chip in chips)
          Padding(padding: const EdgeInsets.only(right: 8), child: chip),
      ],
    ),
  );

  Widget _buildMonthSelector() {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    final canGoNext = _currentMonth.isBefore(DateTime(now.year, now.month));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(
              () => _currentMonth = DateTime(
                _currentMonth.year,
                _currentMonth.month - 1,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${months[_currentMonth.month - 1]} ${_currentMonth.year}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoNext
                ? () => setState(
                    () => _currentMonth = DateTime(
                      _currentMonth.year,
                      _currentMonth.month + 1,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Color _colorFor(double intensity) {
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return intensity <= 0
        ? surface
        : Color.lerp(surface, _heatColor, 0.15 + 0.85 * intensity)!;
  }

  Widget _buildLegend() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Less', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 4),
        for (final intensity in [0.0, 0.25, 0.5, 0.75, 1.0])
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _colorFor(intensity),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 4),
        const Text('More', style: TextStyle(fontSize: 11)),
      ],
    ),
  );

  Widget _buildCalendarGrid(
    Map<int, double> daily,
    double maxDaily,
    List<Transaction> matching,
  ) {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday;
    final now = DateTime.now();
    final cellCount = firstWeekday - 1 + daysInMonth;
    Widget cell(int index) {
      if (index >= cellCount) return const SizedBox.shrink();
      if (index < firstWeekday - 1) return const SizedBox.shrink();
      final day = index - (firstWeekday - 1) + 1;
      final amount = daily[day] ?? 0;
      final intensity = maxDaily > 0 ? amount / maxDaily : 0.0;
      final isToday = now.year == year && now.month == month && now.day == day;
      final label =
          '$day/$month/$year, ${FormatUtils.formatCurrency(amount)} $_metric';
      return Semantics(
        label: label,
        button: true,
        child: Material(
          color: _colorFor(intensity),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            key: ValueKey('heatmap-day-$day'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => _showDayDetail(day, matching),
            child: Container(
              key: ValueKey('heatmap-cell-$day'),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: isToday
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color:
                      ThemeData.estimateBrightnessForColor(
                            _colorFor(intensity),
                          ) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              for (final day in [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun',
              ])
                Expanded(
                  child: Center(
                    child: Text(day, style: const TextStyle(fontSize: 11)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < (cellCount / 7).ceil(); row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (var column = 0; column < 7; column++) ...[
                    if (column > 0) const SizedBox(width: 4),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: cell(row * 7 + column),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthSummary(Map<int, double> daily) {
    final total = Money.sum(daily.values);
    final activeDays = daily.values.where((amount) => amount > 0).length;
    final peak = daily.entries.fold<MapEntry<int, double>?>(
      null,
      (best, day) =>
          best == null ||
              day.value > best.value ||
              (day.value == best.value && day.key < best.key)
          ? day
          : best,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth >= 480 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 20
              ? 4
              : 2;
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              _summaryItem(
                'total',
                'Total $_metric',
                FormatUtils.formatCurrency(total),
                width,
              ),
              _summaryItem(
                'average',
                'Avg / active day',
                FormatUtils.formatCurrency(
                  activeDays > 0 ? total / activeDays : 0,
                ),
                width,
              ),
              _summaryItem(
                'peak',
                peak == null ? 'Peak' : 'Peak (Day ${peak.key})',
                FormatUtils.formatCurrency(peak?.value ?? 0),
                width,
              ),
              _summaryItem('active', 'Active days', '$activeDays', width),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryItem(String id, String label, String value, double width) =>
      SizedBox(
        width: width,
        child: Column(
          children: [
            Text(
              value,
              key: ValueKey('heatmap-$id'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );

  Future<void> _showDayDetail(int day, List<Transaction> matching) async {
    final txs = matching.where((tx) => tx.date.day == day).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final total = Money.sum(txs.map((tx) => tx.amount));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${_currentMonth.month}/$day - ${FormatUtils.formatCurrency(total)} $_metric',
                key: const ValueKey('heatmap-day-total'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: txs.isEmpty
                  ? const Center(
                      child: Text('No matching transactions this day'),
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: txs.length,
                      itemBuilder: (context, index) {
                        final tx = txs[index];
                        final color = tx.isCredit
                            ? Colors.green
                            : Theme.of(context).colorScheme.error;
                        return ListTile(
                          key: ValueKey('heatmap-transaction-${tx.id}'),
                          leading: Icon(
                            tx.isPartOfTransfer
                                ? Icons.swap_horiz
                                : tx.isCredit
                                ? Icons.south_west
                                : Icons.north_east,
                            color: color,
                          ),
                          title: Text(tx.displayName),
                          subtitle: Text(
                            '${tx.sender}${tx.isPartOfTransfer ? ' - Internal transfer' : ''}',
                          ),
                          trailing: Text(
                            '${tx.isCredit ? '+' : '-'}${FormatUtils.formatCurrency(tx.amount)}',
                            style: TextStyle(color: color),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
