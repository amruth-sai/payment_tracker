/// The outcome of scanning one Android SMS. This is separate from a user's
/// decision to ignore a transaction or a review item.
enum SmsProcessingOutcome { transaction, needsReview, skipped }

class SmsProcessingRecord {
  const SmsProcessingRecord({
    required this.smsId,
    required this.sender,
    required this.date,
    required this.outcome,
    required this.reason,
    this.folder = 'unknown',
    this.rawMessage,
  });

  final String smsId;
  final String sender;
  final DateTime date;
  final SmsProcessingOutcome outcome;
  final String reason;
  final String folder;

  /// Retained only for payment-like messages so they can be reviewed again.
  final String? rawMessage;

  Map<String, Object?> toMap() => {
    'sms_id': smsId,
    'sender': sender,
    'date': date.millisecondsSinceEpoch,
    'outcome': outcome.name,
    'reason': reason,
    'folder': folder,
    'raw_message': rawMessage,
    'parser_version': 1,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  };

  factory SmsProcessingRecord.fromMap(Map<String, dynamic> row) {
    return SmsProcessingRecord(
      smsId: row['sms_id'] as String,
      sender: row['sender'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
      outcome: SmsProcessingOutcome.values.firstWhere(
        (value) => value.name == row['outcome'],
      ),
      reason: row['reason'] as String,
      folder: row['folder'] as String? ?? 'unknown',
      rawMessage: row['raw_message'] as String?,
    );
  }
}
