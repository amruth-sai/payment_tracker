import '../models/transaction.dart';
import 'category_service.dart';
import 'local_storage_service.dart';
import 'sms_fingerprint.dart';
import 'sms_parser.dart';

/// Parse copied SMS/RCS text without assuming access to a messaging app's history.
class MessageImportService {
  static DateTime? dateInMessage(String body) {
    final match = RegExp(
      r'\bon\s+(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})\b',
      caseSensitive: false,
    ).firstMatch(body);
    if (match == null) return null;
    final day = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    var year = int.parse(match[3]!);
    if (year < 100) year += 2000;
    final date = DateTime(year, month, day);
    return year >= 2000 &&
            date.year == year &&
            date.month == month &&
            date.day == day
        ? date
        : null;
  }

  static Future<Transaction> preview({
    required String body,
    required String sender,
    required DateTime date,
  }) async {
    if (body.trim().isEmpty || sender.trim().isEmpty) {
      throw const FormatException(
        'Enter the sender and paste one payment message.',
      );
    }
    if (date.isAfter(DateTime.now())) {
      throw const FormatException(
        'The original payment time cannot be in the future.',
      );
    }
    if (SmsParser.isSecurityMessage(body) || SmsParser.isNonTransaction(body)) {
      throw const FormatException(
        'This message does not confirm a completed payment.',
      );
    }
    if (!SmsParser.isLikelyPaymentMessage(sender, body)) {
      throw const FormatException('This does not look like a payment alert.');
    }
    final transaction = await SmsParser.parse(
      body.trim(),
      sender.trim(),
      date,
      SmsFingerprint.importedMessage(body: body, date: date),
    );
    if (transaction == null) {
      throw const FormatException(
        'Could not identify one payment amount and its direction. Paste one complete alert.',
      );
    }
    final rule = CategoryService.matchingMerchantRule(
      await LocalStorageService.getMerchantRules(enabledOnly: true),
      body,
    );
    final assignment = CategoryService.assign(transaction, merchantRule: rule);
    return transaction.copyWith(
      merchant: rule?.merchant,
      categoryId: assignment.categoryId,
      categorySource: assignment.source,
      tag: rule?.tag,
      isUserCorrected: true,
    );
  }
}
