// lib/services/transaction_review_service.dart
// Service to handle the complete flow of SMS processing and sender-grouped review

import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/sms_parser.dart';
import '../services/local_storage_service.dart';
import '../widgets/sender_grouped_review_sheet.dart';
import '../widgets/new_transactions_review_sheet.dart';

/// Service to handle transaction processing and provide user review flows
class TransactionReviewService {

  /// Process SMS messages and show sender-grouped review for user's specific banks
  static Future<void> processAndReviewTransactions(
    BuildContext context, {
    required List<Map<String, dynamic>> smsMessages,
    VoidCallback? onCompleted,
  }) async {
    // Parse SMS messages into transactions
    final transactions = <Transaction>[];
    final processedSmsIds = <String>[];

    for (final sms in smsMessages) {
      final String body = sms['body'] ?? '';
      final String sender = sms['sender'] ?? '';
      final DateTime date = sms['date'] ?? DateTime.now();
      final String id = sms['id'] ?? '';

      // Check if SMS is already processed
      if (await LocalStorageService.isSmsProcessed(id)) {
        continue;
      }

      // Try to parse as transaction
      final transaction = await SmsParser.parse(body, sender, date, id);
      if (transaction != null) {
        transactions.add(transaction);
        processedSmsIds.add(id);
      }
    }

    if (transactions.isEmpty) {
      // No transactions found
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No new transactions found in recent messages'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      onCompleted?.call();
      return;
    }

    // Group transactions by user's banks vs others
    final userBankTransactions = <Transaction>[];
    final otherTransactions = <Transaction>[];

    for (final tx in transactions) {
      if (SmsParser.isUserBankSync(tx.sender)) {
        userBankTransactions.add(tx);
      } else {
        otherTransactions.add(tx);
      }
    }

    // Show appropriate review sheet based on what we found
    if (userBankTransactions.isNotEmpty) {
      // Show sender-grouped review for user's banks
      if (!context.mounted) return;
      await _showSenderGroupedReview(
        context,
        userBankTransactions,
        onCompleted: () async {
          // Save transactions
          await LocalStorageService.saveTransactions(userBankTransactions);
          await LocalStorageService.markSmsListAsProcessed(
            userBankTransactions.map((t) => t.id).toList(),
            isTransaction: true,
          );

          // If there are other transactions, show regular review
          if (otherTransactions.isNotEmpty) {
            if (!context.mounted) return;
            await _showRegularReview(context, otherTransactions, onCompleted);
          } else {
            onCompleted?.call();
          }
        },
      );
    } else if (otherTransactions.isNotEmpty) {
      // Only other transactions found, show regular review
      if (!context.mounted) return;
      await _showRegularReview(context, otherTransactions, onCompleted);
    }
  }

  /// Show sender-grouped review sheet
  static Future<void> _showSenderGroupedReview(
    BuildContext context,
    List<Transaction> transactions,
    {VoidCallback? onCompleted}
  ) async {
    return SenderGroupedReviewSheet.show(
      context,
      transactions: transactions,
      onDone: () {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✓ Processed ${transactions.length} transaction${transactions.length > 1 ? 's' : ''} from your banks'
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        onCompleted?.call();
      },
    );
  }

  /// Show regular review sheet for non-user banks
  static Future<void> _showRegularReview(
    BuildContext context,
    List<Transaction> transactions,
    VoidCallback? onCompleted,
  ) async {
    return NewTransactionsReviewSheet.show(
      context,
      transactions: transactions,
      onDone: () async {
        // Save other transactions
        await LocalStorageService.saveTransactions(transactions);
        await LocalStorageService.markSmsListAsProcessed(
          transactions.map((t) => t.id).toList(),
          isTransaction: true,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✓ Processed ${transactions.length} other transaction${transactions.length > 1 ? 's' : ''}'
              ),
              backgroundColor: Colors.blue,
            ),
          );
        }
        onCompleted?.call();
      },
    );
  }

  /// Get summary of transactions grouped by sender
  static Map<String, TransactionSummary> getTransactionSummaryBySender(
    List<Transaction> transactions,
  ) {
    final grouped = SmsParser.groupTransactionsBySender(transactions);
    final summaries = <String, TransactionSummary>{};

    for (final entry in grouped.entries) {
      final senderName = entry.key;
      final senderTransactions = entry.value;

      double totalCredit = 0;
      double totalDebit = 0;
      int creditCount = 0;
      int debitCount = 0;

      for (final tx in senderTransactions) {
        if (tx.isCredit) {
          totalCredit += tx.amount;
          creditCount++;
        } else {
          totalDebit += tx.amount;
          debitCount++;
        }
      }

      summaries[senderName] = TransactionSummary(
        senderName: senderName,
        accountType: SmsParser.getAccountTypeSync(senderName),
        isUserBank: SmsParser.isUserBankSync(senderName),
        totalTransactions: senderTransactions.length,
        totalCredit: totalCredit,
        totalDebit: totalDebit,
        creditCount: creditCount,
        debitCount: debitCount,
        netAmount: totalCredit - totalDebit,
        dateRange: senderTransactions.isEmpty
            ? null
            : DateRange(
                start: senderTransactions.last.date,
                end: senderTransactions.first.date,
              ),
      );
    }

    return summaries;
  }

  /// Check if SMS processing is needed based on recent activity
  static Future<bool> shouldProcessSms() async {
    // Check when we last processed SMS
    final lastProcess = await LocalStorageService.getSetting('last_sms_process');
    if (lastProcess == null) return true;

    final lastProcessTime = DateTime.tryParse(lastProcess);
    if (lastProcessTime == null) return true;

    // Process if it's been more than 1 hour since last check
    final hoursSince = DateTime.now().difference(lastProcessTime).inHours;
    return hoursSince >= 1;
  }

  /// Mark SMS processing as completed
  static Future<void> markSmsProcessingCompleted() async {
    await LocalStorageService.setSetting(
      'last_sms_process',
      DateTime.now().toIso8601String(),
    );
  }

  /// Get user's banks that have transactions
  static Future<List<String>> getUserBanksWithTransactions() async {
    final transactions = await LocalStorageService.getAllTransactions();
    final grouped = SmsParser.groupTransactionsBySender(transactions);

    return grouped.keys
        .where((sender) => SmsParser.isUserBankSync(sender))
        .toList();
  }

  /// Get transactions for a specific sender
  static Future<List<Transaction>> getTransactionsForSender(String senderName) async {
    final allTransactions = await LocalStorageService.getAllTransactions();
    return allTransactions
        .where((tx) => SmsParser.getUnifiedSenderNameSync(tx.sender) == senderName)
        .toList();
  }
}

/// Summary information for transactions from a specific sender
class TransactionSummary {
  final String senderName;
  final String accountType;
  final bool isUserBank;
  final int totalTransactions;
  final double totalCredit;
  final double totalDebit;
  final int creditCount;
  final int debitCount;
  final double netAmount;
  final DateRange? dateRange;

  TransactionSummary({
    required this.senderName,
    required this.accountType,
    required this.isUserBank,
    required this.totalTransactions,
    required this.totalCredit,
    required this.totalDebit,
    required this.creditCount,
    required this.debitCount,
    required this.netAmount,
    this.dateRange,
  });

  bool get hasCredits => creditCount > 0;
  bool get hasDebits => debitCount > 0;
  bool get isNetPositive => netAmount > 0;

  String get summaryText {
    if (hasCredits && hasDebits) {
      return '$creditCount credit${creditCount > 1 ? 's' : ''}, $debitCount debit${debitCount > 1 ? 's' : ''}';
    } else if (hasCredits) {
      return '$creditCount credit transaction${creditCount > 1 ? 's' : ''}';
    } else {
      return '$debitCount debit transaction${debitCount > 1 ? 's' : ''}';
    }
  }
}

/// Date range for transaction summaries
class DateRange {
  final DateTime start;
  final DateTime end;

  DateRange({required this.start, required this.end});

  Duration get duration => end.difference(start);

  String get description {
    final days = duration.inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday - Today';
    if (days < 30) return '$days days';
    if (days < 365) return '${(days / 30).round()} months';
    return '${(days / 365).round()} year${days >= 730 ? 's' : ''}';
  }
}