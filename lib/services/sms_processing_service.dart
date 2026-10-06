import '../models/sms_processing_record.dart';
import '../models/transaction.dart';
import '../models/transaction_review.dart';
import 'category_service.dart';
import 'sms_parser.dart';

typedef SmsTransactionParser = Future<Transaction?> Function(
  String body,
  String sender,
  DateTime date,
  String id,
);

class SmsProcessingResult {
  const SmsProcessingResult({
    required this.record,
    this.transaction,
    this.review,
  });

  final SmsProcessingRecord record;
  final Transaction? transaction;
  final TransactionReview? review;
}

/// Converts one SMS into a transaction, review item, or explained skip.
class SmsProcessingService {
  SmsProcessingService({
    this.merchantRules = const [],
    SmsTransactionParser? transactionParser,
  }) : _transactionParser = transactionParser ?? SmsParser.parse;

  final List<MerchantRule> merchantRules;
  final SmsTransactionParser _transactionParser;

  Future<SmsProcessingResult> process({
    required String id,
    required String sender,
    required String body,
    required DateTime date,
    bool isSent = false,
  }) async {
    if (SmsParser.isSecurityMessage(body)) {
      return SmsProcessingResult(
        record: SmsProcessingRecord(
          smsId: id,
          sender: sender,
          date: date,
          outcome: SmsProcessingOutcome.skipped,
          reason: 'security_message',
          folder: isSent ? 'sent' : 'inbox',
        ),
      );
    }
    Transaction? transaction;
    TransactionReview? review;
    final isCandidate = (!isSent || SmsParser.isBankSms(sender)) &&
        SmsParser.isLikelyPaymentMessage(sender, body);
    if (isCandidate) {
      transaction = await _transactionParser(body, sender, date, id);
      if (transaction == null) {
        review = SmsParser.buildReviewCandidate(body, sender, date, id);
      }
    }

    if (transaction != null) {
      final rule = CategoryService.matchingMerchantRule(merchantRules, body);
      final assignment = CategoryService.assign(transaction, merchantRule: rule);
      final legacyCategory = TransactionCategory.fromStandardCategoryId(
        assignment.categoryId,
      );
      return SmsProcessingResult(
        transaction: transaction.copyWith(
          merchant: rule?.merchant,
          category: legacyCategory,
          standardCategoryId: assignment.categoryId,
          categorySource: assignment.source,
          tag: rule?.tag,
          clearCategory: legacyCategory == null,
        ),
        record: SmsProcessingRecord(
          smsId: id,
          sender: sender,
          date: date,
          outcome: SmsProcessingOutcome.transaction,
          reason: 'parsed',
          folder: isSent ? 'sent' : 'inbox',
        ),
      );
    }

    if (review != null) {
      final rule = CategoryService.matchingMerchantRule(merchantRules, body);
      return SmsProcessingResult(
        review: review.copyWith(
          merchant: rule?.merchant,
          standardCategoryId: rule?.standardCategoryId,
          categorySource: rule?.standardCategoryId == null
              ? null
              : 'merchant_rule',
          tag: rule?.tag,
        ),
        record: SmsProcessingRecord(
          smsId: id,
          sender: sender,
          date: date,
          outcome: SmsProcessingOutcome.needsReview,
          reason: 'direction_unclear',
          folder: isSent ? 'sent' : 'inbox',
        ),
      );
    }

    return SmsProcessingResult(
      record: SmsProcessingRecord(
        smsId: id,
        sender: sender,
        date: date,
        outcome: SmsProcessingOutcome.skipped,
        reason: isSent && !SmsParser.isBankSms(sender)
            ? 'sent_unrecognized'
            : SmsParser.skipReason(body, sender),
        folder: isSent ? 'sent' : 'inbox',
        rawMessage: isCandidate && SmsParser.hasAmountIndicator(body)
            ? body
            : null,
      ),
    );
  }
}
