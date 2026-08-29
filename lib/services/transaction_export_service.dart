import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import '../models/transaction.dart';
import 'local_storage_service.dart';

class TransactionExportService {
  TransactionExportService._();

  /// Shares the active transaction set used by the app's summaries, optionally
  /// limited to a selected date range or salary cycle.
  static Future<int> shareTrackedTransactions({
    DateTime? start,
    DateTime? end,
    String? periodLabel,
  }) async {
    final transactions = await LocalStorageService.getTrackedTransactions(
      start: start,
      end: end,
    );
    final export = buildExport(
      transactions,
      start: start,
      end: end,
      periodLabel: periodLabel,
    );
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'payment_tracker_transactions_$timestamp.json';

    await SharePlus.instance.share(
      ShareParams(
        title: 'Payment Tracker transactions',
        subject: 'Payment Tracker transaction export',
        text: 'Transaction export for spending analysis. Raw SMS content is excluded.',
        files: [
          XFile.fromData(
            utf8.encode(const JsonEncoder.withIndent('  ').convert(export)),
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: [fileName],
      ),
    );

    return export['transaction_count'] as int;
  }

  static Map<String, dynamic> buildExport(
    List<Transaction> transactions, {
    DateTime? start,
    DateTime? end,
    String? periodLabel,
  }) {
    final includedTransactions = transactions.where((tx) => !tx.isIgnored).toList();

    return {
      'format': 'payment_tracker_transaction_export',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'transaction_count': includedTransactions.length,
      'period': {
        'label': periodLabel ?? 'All active transactions',
        'start': start?.toIso8601String(),
        'end': end?.toIso8601String(),
      },
      'privacy_note': 'Raw SMS messages, balances, and reference IDs are excluded.',
      'transactions': includedTransactions.map(_transactionToExport).toList(),
    };
  }

  static Map<String, dynamic> _transactionToExport(Transaction tx) {
    return {
      'date': tx.date.toIso8601String(),
      'amount': tx.amount,
      'type': tx.type.name,
      'source': tx.source.name,
      'merchant': tx.merchant,
      'sender': tx.sender,
      'account_last4': tx.accountLast4,
      'category_id': tx.effectiveStandardCategoryId,
      'custom_category_id': tx.customCategoryId,
      'tag': tx.tag,
      'note': tx.note,
      'is_salary': tx.isSalary,
      'is_transfer': tx.isPartOfTransfer,
      'transfer_group_id': tx.transferGroupId,
    };
  }
}
