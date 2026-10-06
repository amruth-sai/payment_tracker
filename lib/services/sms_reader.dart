import 'package:another_telephony/telephony.dart';

class SmsReadMessage {
  const SmsReadMessage(this.message, {required this.isSent});

  final SmsMessage message;
  final bool isSent;
}

/// Android SMS access. The caller owns permissions, deduplication, and storage.
class SmsReader {
  SmsReader({Telephony? telephony}) : _telephony = telephony ?? Telephony.instance;

  final Telephony _telephony;

  Future<List<SmsReadMessage>> read({DateTime? after}) async {
    final filter = after == null
        ? null
        : SmsFilter.where(SmsColumn.DATE)
            .greaterThan(after.millisecondsSinceEpoch.toString());
    final inbox = await _telephony.getInboxSms(
      columns: const [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ID],
      filter: filter,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    final sent = await _telephony.getSentSms(
      columns: const [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ID],
      filter: filter,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    return [
      ...inbox.map((message) => SmsReadMessage(message, isSent: false)),
      ...sent.map((message) => SmsReadMessage(message, isSent: true)),
    ];
  }
}
