import '../utils/money.dart';
// lib/services/sms_service.dart

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/transaction.dart';
import '../models/app_category.dart';
import '../models/transaction_review.dart';
import '../models/sms_processing_record.dart';
import '../models/account.dart';
import '../models/salary_cycle.dart';
import 'local_storage_service.dart';
import 'sms_reader.dart';
import 'sms_fingerprint.dart';
import '../utils/date_utils.dart';
import 'sms_processing_service.dart';

class SmsService extends ChangeNotifier {
  final SmsReader _reader = SmsReader();

  List<Transaction> _transactions = [];
  Map<String, AppCategory> _categoriesById = {};
  Map<String, AppCategory> get categoriesById =>
      Map.unmodifiable(_categoriesById);
  List<Account> _accounts = [];
  Map<String, Account> _accountsMap = {};
  SalaryCycle? _currentCycle;
  int? _salaryCycleDay; // User-configured salary day (e.g. 25)
  List<Transaction> _newlyFoundTransactions = []; // Feature 6: for review popup
  bool _isLoading = false;
  bool _hasPermission = false;
  String? _error;
  int _ruleParsedCount = 0;
  int _cachedCount = 0;
  int _newlyParsedCount = 0;
  String _loadingStatus = '';

  List<Transaction> get transactions => List.unmodifiable(_transactions);
  List<Account> get accounts => _accounts;
  List<Transaction> get newlyFoundTransactions => _newlyFoundTransactions;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  String? get error => _error;
  int get ruleParsedCount => _ruleParsedCount;
  int get cachedCount => _cachedCount;
  int get newlyParsedCount => _newlyParsedCount;
  String get loadingStatus => _loadingStatus;

  List<Transaction> get credits =>
      _transactions.where((t) => t.isIncome).toList();

  List<Transaction> get debits =>
      _transactions.where((t) => t.isExpense).toList();

  double get totalCredits => credits.totalAmount;

  double get totalDebits => debits.totalAmount;

  // Current cycle (salary-based) or fallback to calendar month
  SalaryCycle? get currentCycle => _currentCycle;

  /// Transactions in the current cycle period, or current calendar month if no cycle
  List<Transaction> get currentCycleTransactions {
    if (_currentCycle != null) {
      return _transactions
          .where((t) => _currentCycle!.contains(t.date))
          .toList();
    }
    // Use salary cycle day if set, otherwise fall back to calendar month
    if (_salaryCycleDay != null) {
      final range = _getCycleDateRange(_salaryCycleDay!);
      return _transactions
          .where((t) => !t.date.isBefore(range.$1) && !t.date.isAfter(range.$2))
          .toList();
    }
    return currentMonthTransactions;
  }

  double get currentCycleCredits =>
      currentCycleTransactions.where((t) => t.isIncome).totalAmount;

  double get currentCycleDebits =>
      currentCycleTransactions.where((t) => t.isExpense).totalAmount;

  String get currentCycleLabel {
    if (_currentCycle != null) {
      return _currentCycle!.cycleLabel;
    }
    if (_salaryCycleDay != null) {
      return 'Current Cycle';
    }
    return 'This Month';
  }

  String get currentCycleSubtitle {
    if (_currentCycle != null) {
      final start = _currentCycle!.startDate;
      final end = _currentCycle!.endDate ?? DateTime.now();
      final months = [
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
      return '${start.day} ${months[start.month - 1]} – ${end.day} ${months[end.month - 1]} ${end.year}';
    }
    if (_salaryCycleDay != null) {
      final range = _getCycleDateRange(_salaryCycleDay!);
      final months = [
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
      return '${range.$1.day} ${months[range.$1.month - 1]} – ${range.$2.day} ${months[range.$2.month - 1]} ${range.$2.year}';
    }
    return _monthYearNow();
  }

  static String _monthYearNow() {
    final now = DateTime.now();
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[now.month - 1]} ${now.year}';
  }

  // Feature 5: Current-month getters (calendar month fallback)
  List<Transaction> get currentMonthTransactions {
    final now = DateTime.now();
    return _transactions
        .where((t) => t.date.year == now.year && t.date.month == now.month)
        .toList();
  }

  double get currentMonthCredits =>
      currentMonthTransactions.where((t) => t.isIncome).totalAmount;

  double get currentMonthDebits =>
      currentMonthTransactions.where((t) => t.isExpense).totalAmount;

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

  /// Load transactions - uses cache first, then parses only new SMS
  Future<void> loadTransactions({
    int? daysBack,
    bool scanFromBeginning = false,
  }) async {
    if (_isLoading) return;
    final scanStartedAt = DateTime.now();
    _isLoading = true;
    _error = null;
    _ruleParsedCount = 0;
    _cachedCount = 0;
    _newlyParsedCount = 0;
    _loadingStatus = 'Loading cached data...';
    notifyListeners();

    try {
      // Step 1: Load cached transactions first (instant display!)
      final cached = await _getFilteredTransactions();
      _transactions = cached;
      _newlyFoundTransactions = [];
      if (cached.isNotEmpty) {
        _transactions = cached;
        _cachedCount = cached.length;
        _loadingStatus = 'Found $_cachedCount cached transactions';
        notifyListeners();
      }

      await _loadAccounts();
      await _loadCurrentCycle();

      // Step 2: Request SMS permission
      _loadingStatus = 'Checking permissions...';
      notifyListeners();

      final granted = await requestPermission();
      if (!granted) {
        _error = 'SMS permission denied. Please grant it in Settings.';
        _isLoading = false;
        notifyListeners();
        return;
      }
      _hasPermission = true;

      // Step 3: Get already processed SMS IDs
      _loadingStatus = 'Checking for new messages...';
      notifyListeners();

      final processedIds = await LocalStorageService.getProcessedSmsIds();

      final lastScanAt = await LocalStorageService.getLastSmsScanAt();
      final cutoff = daysBack != null
          ? scanStartedAt.subtract(Duration(days: daysBack))
          : scanFromBeginning || lastScanAt == null
          ? null
          : lastScanAt.subtract(const Duration(days: 2));
      final allSms = await _reader.read(after: cutoff);

      // Step 5: Filter out already processed SMS
      final newSms = allSms.where((item) {
        final sms = item.message;
        if (sms.date == null || sms.body == null || sms.address == null) {
          return false;
        }
        final id = SmsFingerprint.of(
          sender: sms.address!,
          body: sms.body!,
          date: DateTime.fromMillisecondsSinceEpoch(sms.date!),
          isSent: item.isSent,
        );
        return !processedIds.contains(id);
      }).toList();

      if (newSms.isEmpty) {
        _loadingStatus = 'No new messages to process';
        await LocalStorageService.setLastSmsScanAt(scanStartedAt);
        await _loadAccounts();
        await _loadCurrentCycle();
        _isLoading = false;
        notifyListeners();
        return;
      }

      _loadingStatus = 'Processing ${newSms.length} new messages...';
      notifyListeners();

      // Step 6: Parse only new SMS. Writes are batched after parsing so a
      // large inbox does not pay a database round-trip for every message.
      final newTransactions = <Transaction>[];
      final pendingTransactions = <Transaction>[];
      final pendingReviews = <TransactionReview>[];
      final pendingRecords = <SmsProcessingRecord>[];
      final seenSmsIds = <String>{};
      final processor = SmsProcessingService(
        merchantRules: await LocalStorageService.getMerchantRules(
          enabledOnly: true,
        ),
      );

      Future<void> flushPending() async {
        if (pendingRecords.isEmpty) return;
        await LocalStorageService.saveScanResults(
          transactions: pendingTransactions,
          reviews: pendingReviews,
          records: pendingRecords,
        );
        pendingTransactions.clear();
        pendingReviews.clear();
        pendingRecords.clear();
      }

      for (int i = 0; i < newSms.length; i++) {
        if (i > 0 && i % 100 == 0) {
          _loadingStatus = 'Processing $i of ${newSms.length} messages...';
          notifyListeners();
        }
        final item = newSms[i];
        final sms = item.message;
        final sender = sms.address ?? '';
        final body = sms.body ?? '';
        final dateMs = int.tryParse(sms.date?.toString() ?? '0') ?? 0;
        final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
        final id = SmsFingerprint.of(
          sender: sender,
          body: body,
          date: date,
          isSent: item.isSent,
        );
        if (!seenSmsIds.add(id)) continue;

        final result = await processor.process(
          id: id,
          sender: sender,
          body: body,
          date: date,
          isSent: item.isSent,
        );
        if (result.transaction != null) {
          newTransactions.add(result.transaction!);
          pendingTransactions.add(result.transaction!);
          _ruleParsedCount++;
        }
        if (result.review != null) pendingReviews.add(result.review!);
        pendingRecords.add(result.record);
        if (pendingRecords.length >= 250) await flushPending();
      }

      await flushPending();
      await LocalStorageService.setLastSmsScanAt(scanStartedAt);

      _newlyParsedCount = newTransactions.length;
      _newlyFoundTransactions = List.unmodifiable(newTransactions); // Feature 6

      // Step 7: Merge new transactions with cached ones
      if (newTransactions.isNotEmpty) {
        // Reload all from cache to get sorted & deduplicated list
        _transactions = await _getFilteredTransactions();
      }

      _loadingStatus = 'Done! $_newlyParsedCount new transactions found';
    } catch (_) {
      _error = 'Unable to read messages right now. Please try again.';
    }

    try {
      await _loadAccounts();
      await _loadCurrentCycle();
    } catch (_) {
      _error = 'Unable to refresh saved data. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Recheck SMS without deleting user edits or ignored decisions. Previously
  /// processed messages remain immutable; new parsing rules apply to new SMS.
  Future<void> recheckSkippedMessages({int? daysBack}) async {
    if (_isLoading) {
      throw StateError('A message scan is already running.');
    }
    await LocalStorageService.prepareSkippedMessagesForRescan();
    await loadTransactions(daysBack: daysBack, scanFromBeginning: true);
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
    for (final tx in _transactions.where(
      (t) => type == TransactionType.debit ? t.isExpense : t.isIncome,
    )) {
      final key = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      map[key] = Money.sum([map[key] ?? 0, tx.amount]);
    }
    return map;
  }

  /// Feature 4: Load all transactions applying trackFromDate + isIgnored filters
  Future<List<Transaction>> _getFilteredTransactions() async {
    return LocalStorageService.getTrackedTransactions();
  }

  Future<void> _loadAccounts() async {
    _categoriesById = {
      for (final category in await LocalStorageService.getAllCategories())
        category.id: category,
    };
    _accounts = await LocalStorageService.getAllAccounts();
    _accountsMap = {for (final a in _accounts) a.id: a};
  }

  Future<void> _loadCurrentCycle() async {
    final cycles = await LocalStorageService.generateSalaryCycles();
    _currentCycle = cycles.isEmpty
        ? null
        : cycles.firstWhere((c) => c.isCurrent, orElse: () => cycles.first);
    _salaryCycleDay = await LocalStorageService.getSalaryCycleDay();
  }

  /// Compute the current cycle date range from a salary day.
  /// E.g. if salary day is 25, and today is Mar 10, the cycle is Feb 25 – Mar 24.
  /// If today is Mar 28, the cycle is Mar 25 – Apr 24.
  static (DateTime, DateTime) _getCycleDateRange(int salaryDay) {
    final now = DateTime.now();
    final range = AppDateUtils.salaryPeriod(now, salaryDay);
    final inclusiveEnd = range.$2.subtract(const Duration(milliseconds: 1));
    return (range.$1, inclusiveEnd.isAfter(now) ? now : inclusiveEnd);
  }

  String? getAccountDisplayName(String? accountId, String? accountLast4) {
    if (accountId != null) {
      final account = _accountsMap[accountId];
      if (account != null) return account.displayName;
    }
    if (accountLast4 != null) return 'Account ending $accountLast4';
    return null;
  }

  /// Feature 4: Re-apply tracking filters and refresh in-memory list
  Future<void> reloadFromCache() async {
    _transactions = await _getFilteredTransactions();
    await _loadAccounts();
    await _loadCurrentCycle();
    notifyListeners();
  }
}
