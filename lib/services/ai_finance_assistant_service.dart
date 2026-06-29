import 'dart:convert';

import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/standard_category.dart';
import '../models/transaction.dart';
import '../utils/format_utils.dart';
import 'local_ai_config.dart';
import 'local_storage_service.dart';

enum FinancePeriod { thisMonth, lastMonth, last30Days, allTime }

class FinanceAssistantReply {
  final String text;
  final bool hasError;

  FinanceAssistantReply({required this.text, this.hasError = false});
}

class FinanceAssistantService {
  static const String _systemPrompt = '''
You are a personal finance assistant inside the Payment Tracker app.

Rules:
- Use tools whenever a question needs transaction, account, category, or budget data.
- Do not invent totals or balances. If a tool returns no data, say so clearly.
- Keep answers concise, practical, and grounded in the user's local data.
- If the user asks for a time period and it is not supplied, choose a sensible default.
- When reporting money, use rupees and keep formatting easy to scan.
- Do not mention internal tool names unless it helps explain the answer.
''';

  static const int _maxFunctionTurns = 8;

  static LiteLmEngine? _engine;
  static LiteLmConversation? _conversation;
  static bool _isInitialized = false;

  static final List<LiteLmTool> _tools = [
    LiteLmTool(
      name: 'get_spending_by_category',
      description: 'Summarize spending by standard category for a time period.',
      parameters: {
        'type': 'object',
        'properties': {
          'period': {
            'type': 'string',
            'enum': FinancePeriod.values.map((e) => e.name).toList(),
            'description':
                'Time period to analyze. Defaults to allTime when omitted.',
          },
        },
      },
    ),
    LiteLmTool(
      name: 'get_budget_status',
      description:
          'Return budget usage, remaining amount, and risk status for the current month.',
      parameters: {
        'type': 'object',
        'properties': {
          'period': {
            'type': 'string',
            'enum': FinancePeriod.values.map((e) => e.name).toList(),
            'description':
                'Time period to analyze. Defaults to thisMonth when omitted.',
          },
        },
      },
    ),
    LiteLmTool(
      name: 'get_top_expenses',
      description:
          'List the biggest debit transactions in descending order by amount.',
      parameters: {
        'type': 'object',
        'properties': {
          'period': {
            'type': 'string',
            'enum': FinancePeriod.values.map((e) => e.name).toList(),
            'description':
                'Time period to analyze. Defaults to allTime when omitted.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of transactions to return.',
          },
        },
      },
    ),
    LiteLmTool(
      name: 'get_recent_transactions',
      description:
          'Return the most recent transactions, optionally filtered by type.',
      parameters: {
        'type': 'object',
        'properties': {
          'period': {
            'type': 'string',
            'enum': FinancePeriod.values.map((e) => e.name).toList(),
            'description':
                'Time period to analyze. Defaults to last30Days when omitted.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of transactions to return.',
          },
          'type': {
            'type': 'string',
            'enum': ['credit', 'debit', 'all'],
            'description':
                'Optional transaction type filter. Defaults to all.',
          },
        },
      },
    ),
    LiteLmTool(
      name: 'get_account_summary',
      description:
          'Summarize spending and income grouped by account or sender.',
      parameters: {
        'type': 'object',
        'properties': {
          'period': {
            'type': 'string',
            'enum': FinancePeriod.values.map((e) => e.name).toList(),
            'description':
                'Time period to analyze. Defaults to allTime when omitted.',
          },
        },
      },
    ),
  ];

  static bool get isInitialized => _isInitialized;

  static Future<void> initialize({
    required String modelPath,
    LiteLmBackend backend = LiteLmBackend.cpu,
  }) async {
    _engine = await LiteLmEngine.create(
      LiteLmEngineConfig(
        modelPath: modelPath,
        backend: backend,
      ),
    );
    _conversation = await _engine!.createConversation(
      LiteLmConversationConfig(
        systemInstruction: _systemPrompt,
        tools: _tools,
        automaticToolCalling: false,
        samplerConfig: const LiteLmSamplerConfig(
          temperature: 0.4,
          topK: 40,
          topP: 0.95,
        ),
      ),
    );
    _isInitialized = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLocalAssistantModelPathKey, modelPath);
    await prefs.setString(kLocalAssistantBackendKey, backend.name);
  }

  static Future<bool> loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final modelPath = prefs.getString(kLocalAssistantModelPathKey);
    if (modelPath == null || modelPath.isEmpty) return false;

    final backendName = prefs.getString(kLocalAssistantBackendKey) ??
        kDefaultLocalAssistantBackend;
    final backend = switch (backendName) {
      'gpu' => LiteLmBackend.gpu,
      'npu' => LiteLmBackend.npu,
      _ => LiteLmBackend.cpu,
    };

    await initialize(modelPath: modelPath, backend: backend);
    return true;
  }

  static Future<FinanceAssistantReply> sendMessage(String message) async {
    if (!_isInitialized || _engine == null || _conversation == null) {
      final loaded = await loadSavedConfig();
      if (!loaded) {
        return FinanceAssistantReply(
          text:
              'Local AI is not configured yet. Open Settings and add the path to your downloaded Gemma model file first.',
          hasError: true,
        );
      }
    }

    try {
      final response = await _runChatLoop(message);
      final text = response.text.trim();
      if (text.isEmpty) {
        return FinanceAssistantReply(
          text: 'I retrieved the data, but I could not compose a final answer.',
          hasError: true,
        );
      }

      return FinanceAssistantReply(text: text);
    } catch (e) {
      return FinanceAssistantReply(
        text: 'I could not answer that request right now: $e',
        hasError: true,
      );
    }
  }

  static Future<LiteLmMessage> _runChatLoop(String message) async {
    final conversation = _conversation!;
    var response = await conversation.sendMessage(message);

    var turns = 0;
    while (response.toolCalls.isNotEmpty && turns < _maxFunctionTurns) {
      for (final call in response.toolCalls) {
        final result = await FinanceToolExecutor.execute(call.name, call.arguments);
        response = await conversation.sendToolResponse(
          call.name,
          jsonEncode(result),
        );
      }
      turns++;
    }

    return response;
  }
}

class FinanceToolExecutor {
  static Future<Map<String, Object?>> execute(
    String functionName,
    Map<String, Object?> args,
  ) async {
    switch (functionName) {
      case 'get_spending_by_category':
        return _getSpendingByCategory(args);
      case 'get_budget_status':
        return _getBudgetStatus(args);
      case 'get_top_expenses':
        return _getTopExpenses(args);
      case 'get_recent_transactions':
        return _getRecentTransactions(args);
      case 'get_account_summary':
        return _getAccountSummary(args);
      default:
        return {
          'error': 'Unsupported tool: $functionName',
        };
    }
  }

  static Future<Map<String, Object?>> _getSpendingByCategory(
    Map<String, Object?> args,
  ) async {
    final range = _resolvePeriod(args['period'] as String?,
        defaultPeriod: FinancePeriod.allTime);
    final transactions = await _loadTransactions(range);
    final debits = transactions.where((tx) => tx.isDebit).toList();
    final categoryMap = await _loadStandardCategoryMap();

    final buckets = <String, _CategoryBucket>{};
    for (final tx in debits) {
      final categoryId = tx.effectiveStandardCategoryId ?? 'uncategorized';
      final label = _displayNameForCategory(categoryId, categoryMap);
      final bucket = buckets.putIfAbsent(
        categoryId,
        () => _CategoryBucket(categoryId: categoryId, label: label),
      );
      bucket.add(tx.amount);
    }

    final totalSpent = debits.fold<double>(0, (sum, tx) => sum + tx.amount);
    final sorted = buckets.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return {
      'period': _periodPayload(range),
      'summary': {
        'total_spent': totalSpent,
        'transaction_count': debits.length,
      },
      'categories': sorted
          .map(
            (bucket) => {
              'category_id': bucket.categoryId,
              'category_name': bucket.label,
              'total_spent': bucket.total,
              'transaction_count': bucket.count,
              'share_percent': totalSpent > 0
                  ? (bucket.total / totalSpent) * 100
                  : 0.0,
            },
          )
          .toList(),
    };
  }

  static Future<Map<String, Object?>> _getBudgetStatus(
    Map<String, Object?> args,
  ) async {
    final requestedPeriod = _resolvePeriod(args['period'] as String?,
        defaultPeriod: FinancePeriod.thisMonth);
    final range = requestedPeriod.period == FinancePeriod.allTime
        ? _resolvePeriod(null, defaultPeriod: FinancePeriod.thisMonth)
        : requestedPeriod;

    final transactions = await _loadTransactions(range);
    final debits = transactions.where((tx) => tx.isDebit).toList();
    final budgets = await LocalStorageService.getAllBudgets();
    final categoryMap = await _loadStandardCategoryMap();

    final spentByCategory = <String, double>{};
    for (final tx in debits) {
      final categoryId = tx.effectiveStandardCategoryId ?? 'uncategorized';
      spentByCategory[categoryId] =
          (spentByCategory[categoryId] ?? 0) + tx.amount;
    }

    final budgetRows = budgets.map((budget) {
      final categoryId = budget.standardCategoryId;
      final spent = spentByCategory[categoryId] ?? 0;
      final remaining = budget.monthlyLimit - spent;
      final usage = budget.monthlyLimit <= 0
          ? 0.0
          : (spent / budget.monthlyLimit) * 100;
      final status = spent > budget.monthlyLimit
          ? 'over_budget'
          : usage >= 80
              ? 'watchlist'
              : 'on_track';

      return {
        'category_id': categoryId,
        'category_name': _displayNameForCategory(categoryId, categoryMap),
        'budget_limit': budget.monthlyLimit,
        'spent': spent,
        'remaining': remaining,
        'usage_percent': usage,
        'status': status,
      };
    }).toList();

    budgetRows.sort((a, b) => (b['usage_percent'] as double)
        .compareTo(a['usage_percent'] as double));

    return {
      'period': _periodPayload(range),
      'summary': {
        'budget_count': budgets.length,
        'total_budget': budgets.fold<double>(0, (sum, budget) => sum + budget.monthlyLimit),
        'total_spent': debits.fold<double>(0, (sum, tx) => sum + tx.amount),
      },
      'budgets': budgetRows,
    };
  }

  static Future<Map<String, Object?>> _getTopExpenses(
    Map<String, Object?> args,
  ) async {
    final range = _resolvePeriod(args['period'] as String?,
        defaultPeriod: FinancePeriod.allTime);
    final limit = _normalizeLimit(args['limit'], 5, max: 20);
    final transactions = await _loadTransactions(range);
    final debits = transactions.where((tx) => tx.isDebit).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final categoryMap = await _loadStandardCategoryMap();
    final rows = debits.take(limit).map((tx) {
      return _serializeTransaction(tx, categoryMap);
    }).toList();

    return {
      'period': _periodPayload(range),
      'limit': limit,
      'transactions': rows,
    };
  }

  static Future<Map<String, Object?>> _getRecentTransactions(
    Map<String, Object?> args,
  ) async {
    final range = _resolvePeriod(args['period'] as String?,
        defaultPeriod: FinancePeriod.last30Days);
    final limit = _normalizeLimit(args['limit'], 10, max: 20);
    final requestedType = (args['type'] as String?)?.toLowerCase();
    final transactions = await _loadTransactions(range);
    final filtered = transactions.where((tx) {
      return switch (requestedType) {
        'credit' => tx.isCredit,
        'debit' => tx.isDebit,
        _ => true,
      };
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final categoryMap = await _loadStandardCategoryMap();
    return {
      'period': _periodPayload(range),
      'limit': limit,
      'type': requestedType ?? 'all',
      'transactions': filtered
          .take(limit)
          .map((tx) => _serializeTransaction(tx, categoryMap))
          .toList(),
    };
  }

  static Future<Map<String, Object?>> _getAccountSummary(
    Map<String, Object?> args,
  ) async {
    final range = _resolvePeriod(args['period'] as String?,
        defaultPeriod: FinancePeriod.allTime);
    final transactions = await _loadTransactions(range);
    final categoryMap = await _loadStandardCategoryMap();

    final buckets = <String, _AccountBucket>{};
    for (final tx in transactions) {
      final key = _accountKeyForTransaction(tx);
      final label = _accountLabelForTransaction(tx);
      final bucket = buckets.putIfAbsent(
        key,
        () => _AccountBucket(key: key, label: label),
      );
      bucket.add(tx);
    }

    final rows = buckets.values.map((bucket) {
      return {
        'account_key': bucket.key,
        'account_name': bucket.label,
        'transaction_count': bucket.count,
        'total_in': bucket.totalIn,
        'total_out': bucket.totalOut,
        'net': bucket.totalIn - bucket.totalOut,
      };
    }).toList()
      ..sort((a, b) => (b['total_out'] as double).compareTo(a['total_out'] as double));

    return {
      'period': _periodPayload(range),
      'accounts': rows,
      'currency': 'INR',
      'category_preview': transactions
          .where((tx) => tx.isDebit)
          .take(5)
          .map((tx) => _serializeTransaction(tx, categoryMap))
          .toList(),
    };
  }

  static Future<List<Transaction>> _loadTransactions(_PeriodRange range) async {
    final transactions = await LocalStorageService.getTrackedTransactions(
      start: range.start,
      end: range.end,
    );
    return transactions.where((tx) => !tx.isIgnored).toList();
  }

  static Future<Map<String, StandardCategory>> _loadStandardCategoryMap() async {
    final categories = await LocalStorageService.getAllStandardCategories();
    return {
      for (final category in categories) category.id: category,
    };
  }

  static Map<String, Object?> _serializeTransaction(
    Transaction tx,
    Map<String, StandardCategory> categoryMap,
  ) {
    final categoryId = tx.effectiveStandardCategoryId;
    return {
      'id': tx.id,
      'date': tx.date.toIso8601String(),
      'amount': tx.amount,
      'type': tx.type.name,
      'source': tx.source.name,
      'sender': tx.sender,
      'merchant': tx.merchant,
      'display_name': tx.displayName,
      'account_last4': tx.accountLast4,
      'category_id': categoryId,
      'category_name': _displayNameForCategory(categoryId, categoryMap),
      'custom_category_id': tx.customCategoryId,
      'tag': tx.tag,
      'note': tx.note,
      'formatted_amount': FormatUtils.formatCurrency(tx.amount),
    };
  }

  static String _displayNameForCategory(
    String? categoryId,
    Map<String, StandardCategory> categoryMap,
  ) {
    if (categoryId == null || categoryId.isEmpty) {
      return TransactionCategory.uncategorized.displayName;
    }

    final category = categoryMap[categoryId];
    if (category != null) {
      return category.displayName;
    }

    final legacy = TransactionCategory.fromStandardCategoryId(categoryId);
    if (legacy != null) {
      return legacy.displayName;
    }

    return categoryId;
  }

  static _PeriodRange _resolvePeriod(
    String? periodName, {
    required FinancePeriod defaultPeriod,
  }) {
    final period = FinancePeriod.values.firstWhere(
      (value) => value.name == periodName,
      orElse: () => defaultPeriod,
    );

    final now = DateTime.now();
    switch (period) {
      case FinancePeriod.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1)
            .subtract(const Duration(milliseconds: 1));
        return _PeriodRange(
          period: period,
          start: start,
          end: end,
        );
      case FinancePeriod.lastMonth:
        final start = DateTime(now.year, now.month - 1, 1);
        final end = DateTime(now.year, now.month, 1)
            .subtract(const Duration(milliseconds: 1));
        return _PeriodRange(
          period: period,
          start: start,
          end: end,
        );
      case FinancePeriod.last30Days:
        return _PeriodRange(
          period: period,
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
      case FinancePeriod.allTime:
        return _PeriodRange(period: period, start: null, end: null);
    }
  }

  static Map<String, Object?> _periodPayload(_PeriodRange range) {
    return {
      'period': range.period.name,
      'start': range.start?.toIso8601String(),
      'end': range.end?.toIso8601String(),
    };
  }

  static int _normalizeLimit(dynamic value, int fallback, {required int max}) {
    final raw = value is num ? value.toInt() : int.tryParse('$value');
    final normalized = raw ?? fallback;
    if (normalized < 1) return fallback;
    return normalized > max ? max : normalized;
  }

  static String _accountKeyForTransaction(Transaction tx) {
    if (tx.accountId != null && tx.accountId!.isNotEmpty) {
      return tx.accountId!;
    }
    if (tx.accountLast4 != null && tx.accountLast4!.isNotEmpty) {
      return tx.accountLast4!;
    }
    return tx.sender;
  }

  static String _accountLabelForTransaction(Transaction tx) {
    if (tx.accountLast4 != null && tx.accountLast4!.isNotEmpty) {
      return '${tx.sender} •••• ${tx.accountLast4}';
    }
    return tx.sender;
  }
}

class _PeriodRange {
  final FinancePeriod period;
  final DateTime? start;
  final DateTime? end;

  _PeriodRange({required this.period, required this.start, required this.end});
}

class _CategoryBucket {
  final String categoryId;
  final String label;
  double total = 0;
  int count = 0;

  _CategoryBucket({required this.categoryId, required this.label});

  void add(double amount) {
    total += amount;
    count += 1;
  }
}

class _AccountBucket {
  final String key;
  final String label;
  double totalIn = 0;
  double totalOut = 0;
  int count = 0;

  _AccountBucket({required this.key, required this.label});

  void add(Transaction tx) {
    count += 1;
    if (tx.isCredit) {
      totalIn += tx.amount;
    } else if (tx.isDebit) {
      totalOut += tx.amount;
    }
  }
}