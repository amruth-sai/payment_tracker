// lib/services/sms_service.dart

import 'package:flutter/foundation.dart';
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/transaction.dart';
import 'sms_parser.dart';
import 'ai_sms_parser.dart';

class SmsService extends ChangeNotifier {
  final Telephony _telephony = Telephony.instance;

  List<Transaction> _transactions = [];
  bool _isLoading = false;
  bool _hasPermission = false;
  String? _error;
  bool _useAI = false;
  int _aiParsedCount = 0;
  int _ruleParsedCount = 0;

  List<Transaction> get transactions => _transactions;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  String? get error => _error;
  bool get useAI => _useAI;
  int get aiParsedCount => _aiParsedCount;
  int get ruleParsedCount => _ruleParsedCount;

  List<Transaction> get credits =>
      _transactions.where((t) => t.isCredit).toList();

  List<Transaction> get debits =>
      _transactions.where((t) => t.isDebit).toList();

  double get totalCredits =>
      credits.fold(0, (sum, t) => sum + t.amount);

  double get totalDebits =>
      debits.fold(0, (sum, t) => sum + t.amount);

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

  Future<void> loadTransactions({int daysBack = 90, bool forceAI = false}) async {
    _isLoading = true;
    _error = null;
    _aiParsedCount = 0;
    _ruleParsedCount = 0;
    notifyListeners();

    try {
      final granted = await _telephony.requestPhoneAndSmsPermissions;
      if (granted == null || !granted) {
        _error = 'SMS permission denied. Please grant it in Settings.';
        _isLoading = false;
        notifyListeners();
        return;
      }
      _hasPermission = true;

      // Check if AI should be used
      _useAI = AiSmsParser.isInitialized || forceAI;

      final cutoff = DateTime.now().subtract(Duration(days: daysBack));
      final cutoffMs = cutoff.millisecondsSinceEpoch;

      // Fetch inbox + sent
      final inbox = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ID],
        filter: SmsFilter.where(SmsColumn.DATE).greaterThan(cutoffMs.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final sent = await _telephony.getSentSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ID],
        filter: SmsFilter.where(SmsColumn.DATE).greaterThan(cutoffMs.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final allSms = [...inbox, ...sent];
      final parsed = <Transaction>[];

      for (final sms in allSms) {
        final sender = sms.address ?? '';
        final body = sms.body ?? '';
        final dateMs = int.tryParse(sms.date?.toString() ?? '0') ?? 0;
        final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
        final id = sms.id?.toString() ?? UniqueKey().toString();

        Transaction? tx;

        if (_useAI) {
          // Use AI parser - it can detect ANY transaction
          if (AiSmsParser.mightBeTransaction(body)) {
            tx = await AiSmsParser.parse(body, sender, date, id);
            if (tx != null) _aiParsedCount++;
          }
        } else {
          // Use rule-based parser - limited to known senders
          if (!SmsParser.isBankSms(sender)) continue;
          tx = SmsParser.parse(body, sender, date, id);
          if (tx != null) _ruleParsedCount++;
        }

        if (tx != null) parsed.add(tx);
      }

      // Sort by date descending
      parsed.sort((a, b) => b.date.compareTo(a.date));
      _transactions = parsed;
    } catch (e) {
      _error = 'Failed to read SMS: $e';
    }

    _isLoading = false;
    notifyListeners();
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
}
