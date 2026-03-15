// lib/services/sms_service.dart

import 'package:flutter/foundation.dart';
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/transaction.dart';
import 'sms_parser.dart';
import 'ai_sms_parser.dart';
import 'local_storage_service.dart';
import 'category_service.dart';

class SmsService extends ChangeNotifier {
  final Telephony _telephony = Telephony.instance;

  List<Transaction> _transactions = [];
  List<Transaction> _newlyFoundTransactions = []; // Feature 6: for review popup
  bool _isLoading = false;
  bool _hasPermission = false;
  String? _error;
  bool _useAI = false;
  int _aiParsedCount = 0;
  int _ruleParsedCount = 0;
  int _cachedCount = 0;
  int _newlyParsedCount = 0;
  String _loadingStatus = '';

  List<Transaction> get transactions => _transactions;
  List<Transaction> get newlyFoundTransactions => _newlyFoundTransactions;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  String? get error => _error;
  bool get useAI => _useAI;
  int get aiParsedCount => _aiParsedCount;
  int get ruleParsedCount => _ruleParsedCount;
  int get cachedCount => _cachedCount;
  int get newlyParsedCount => _newlyParsedCount;
  String get loadingStatus => _loadingStatus;

  List<Transaction> get credits =>
      _transactions.where((t) => t.isCredit).toList();

  List<Transaction> get debits =>
      _transactions.where((t) => t.isDebit).toList();

  double get totalCredits => credits.fold(0, (sum, t) => sum + t.amount);

  double get totalDebits => debits.fold(0, (sum, t) => sum + t.amount);

  // Feature 5: Current-month getters
  List<Transaction> get currentMonthTransactions {
    final now = DateTime.now();
    return _transactions
        .where((t) =>
            t.date.year == now.year && t.date.month == now.month)
        .toList();
  }

  double get currentMonthCredits => currentMonthTransactions
      .where((t) => t.isCredit)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get currentMonthDebits => currentMonthTransactions
      .where((t) => t.isDebit)
      .fold(0.0, (sum, t) => sum + t.amount);

  /// Feature 6: Call this after the review popup has been handled
  void clearNewlyFoundTransactions() {
    _newlyFoundTransactions = [];
    notifyListeners();
  }

  Future<bool> requestPermission() async {
    final status = await Permission.sms.request();
    _hasPermission = status.isGranted;
    notifyListeners();
    return _hasPermission;
  }

  /// Initialize AI parser if API key is available
  Future<void> initializeAI() async {
    _useAI = await AiSmsParser.loadSavedApiKey();
    notifyListeners();
  }

  /// Load transactions - uses cache first, then parses only new SMS
  Future<void> loadTransactions(
      {int daysBack = 90, bool forceRefresh = false}) async {
    _isLoading = true;
    _error = null;
    _aiParsedCount = 0;
    _ruleParsedCount = 0;
    _cachedCount = 0;
    _newlyParsedCount = 0;
    _loadingStatus = 'Loading cached data...';
    notifyListeners();

    try {
      // Step 1: Load cached transactions first (instant display!)
      if (!forceRefresh) {
        final cached = await _getFilteredTransactions();
        if (cached.isNotEmpty) {
          _transactions = cached;
          _cachedCount = cached.length;
          _loadingStatus = 'Found $_cachedCount cached transactions';
          notifyListeners();
        }
      }

      // Step 2: Request SMS permission
      _loadingStatus = 'Checking permissions...';
      notifyListeners();

      final granted = await _telephony.requestPhoneAndSmsPermissions;
      if (granted == null || !granted) {
        _error = 'SMS permission denied. Please grant it in Settings.';
        _isLoading = false;
        notifyListeners();
        return;
      }
      _hasPermission = true;

      // Step 3: Check if AI is available
      _useAI = AiSmsParser.isInitialized;

      // Step 4: Get already processed SMS IDs
      _loadingStatus = 'Checking for new messages...';
      notifyListeners();

      final processedIds = await LocalStorageService.getProcessedSmsIds();

      final cutoff = DateTime.now().subtract(Duration(days: daysBack));
      final cutoffMs = cutoff.millisecondsSinceEpoch;

      // Step 5: Fetch SMS from inbox
      final inbox = await _telephony.getInboxSms(
        columns: [
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
          SmsColumn.ID
        ],
        filter:
            SmsFilter.where(SmsColumn.DATE).greaterThan(cutoffMs.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final sent = await _telephony.getSentSms(
        columns: [
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
          SmsColumn.ID
        ],
        filter:
            SmsFilter.where(SmsColumn.DATE).greaterThan(cutoffMs.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final allSms = [...inbox, ...sent];

      // Step 6: Filter out already processed SMS
      final newSms = allSms.where((sms) {
        final id = sms.id?.toString() ?? '';
        return id.isNotEmpty && !processedIds.contains(id);
      }).toList();

      if (newSms.isEmpty) {
        _loadingStatus = 'No new messages to process';
        _isLoading = false;
        notifyListeners();
        return;
      }

      _loadingStatus = 'Processing ${newSms.length} new messages...';
      notifyListeners();

      // Step 7: Parse only new SMS
      final newTransactions = <Transaction>[];
      final nonTransactionIds = <String>[];

      for (int i = 0; i < newSms.length; i++) {
        final sms = newSms[i];
        final sender = sms.address ?? '';
        final body = sms.body ?? '';
        final dateMs = int.tryParse(sms.date?.toString() ?? '0') ?? 0;
        final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
        final id = sms.id?.toString() ?? UniqueKey().toString();

        Transaction? tx;
        String parsedBy = 'rule';

        if (_useAI) {
          // Use AI parser - it can detect ANY transaction
          if (AiSmsParser.mightBeTransaction(body)) {
            _loadingStatus = 'AI parsing ${i + 1}/${newSms.length}...';
            notifyListeners();

            tx = await AiSmsParser.parse(body, sender, date, id);
            if (tx != null) {
              _aiParsedCount++;
              parsedBy = 'ai';
            }
          }
        } else {
          // Use rule-based parser - limited to known senders
          if (SmsParser.isBankSms(sender)) {
            tx = await SmsParser.parse(body, sender, date, id);
            if (tx != null) {
              _ruleParsedCount++;
              parsedBy = 'rule';
            }
          }
        }

        if (tx != null) {
          // Auto-categorize the transaction
          final category = CategoryService.categorize(tx);
          final categorizedTx = tx.copyWith(category: category);
          newTransactions.add(categorizedTx);
          // Save transaction to cache
          await LocalStorageService.saveTransaction(categorizedTx, parsedBy: parsedBy);
          await LocalStorageService.markSmsAsProcessed(id, isTransaction: true);
        } else {
          // Mark as processed but not a transaction
          nonTransactionIds.add(id);
        }
      }

      // Mark non-transaction SMS as processed in batch
      if (nonTransactionIds.isNotEmpty) {
        await LocalStorageService.markSmsListAsProcessed(nonTransactionIds);
      }

      _newlyParsedCount = newTransactions.length;
      _newlyFoundTransactions = List.unmodifiable(newTransactions); // Feature 6

      // Step 8: Merge new transactions with cached ones
      if (newTransactions.isNotEmpty) {
        // Reload all from cache to get sorted & deduplicated list
        _transactions = await _getFilteredTransactions();
      }

      _loadingStatus = 'Done! $_newlyParsedCount new transactions found';
    } catch (e) {
      _error = 'Failed to read SMS: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Force re-parse all SMS (ignores cache)
  Future<void> forceReparse({int daysBack = 90}) async {
    // Clear all cached data
    await LocalStorageService.clearAll();
    // Reload everything
    await loadTransactions(daysBack: daysBack, forceRefresh: true);
  }

  /// Get storage statistics
  Future<Map<String, int>> getStorageStats() async {
    return await LocalStorageService.getStats();
  }

  /// Filter transactions by date range
  List<Transaction> getByDateRange(DateTime start, DateTime end) {
    return _transactions
        .where((t) => t.date.isAfter(start) && t.date.isBefore(end))
        .toList();
  }

  /// Group transactions by month for chart
  Map<String, double> getMonthlySummary(TransactionType type) {
    final map = <String, double>{};
    for (final tx in _transactions.where((t) => t.type == type)) {
      final key = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      map[key] = (map[key] ?? 0) + tx.amount;
    }
    return map;
  }

  /// Feature 4: Load all transactions applying trackFromDate + isIgnored filters
  Future<List<Transaction>> _getFilteredTransactions() async {
    final trackFromDate = await LocalStorageService.getTrackFromDate();
    final trackFromTxId = await LocalStorageService.getTrackFromTransactionId();

    List<Transaction> all;
    if (trackFromDate != null) {
      all = await LocalStorageService.getTransactionsSince(trackFromDate);
    } else {
      all = await LocalStorageService.getAllTransactions();
    }

    // If trackFromTransactionId is set, trim list to start from that txn
    if (trackFromTxId != null && trackFromTxId.isNotEmpty) {
      final idx = all.indexWhere((t) => t.id == trackFromTxId);
      if (idx != -1) {
        // all is sorted DESC by date; transactions at idx and after are older
        all = all.sublist(0, idx + 1);
      }
    }

    // Feature 2: exclude ignored transactions from active lists
    return all.where((t) => !t.isIgnored).toList();
  }

  /// Feature 4: Re-apply tracking filters and refresh in-memory list
  Future<void> reloadFromCache() async {
    _transactions = await _getFilteredTransactions();
    notifyListeners();
  }
}
