import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'sms_parser.dart';

/// Android row IDs change between devices. Message content is the durable key.
class SmsFingerprint {
  static String of({
    required String sender,
    required String body,
    required DateTime date,
    required bool isSent,
  }) {
    final canonical = jsonEncode([
      SmsParser.cleanSender(sender).toUpperCase(),
      body.replaceAll(RegExp(r'\s+'), ' ').trim(),
      date.millisecondsSinceEpoch,
      isSent ? 'sent' : 'inbox',
    ]);
    return 'sms_${sha256.convert(utf8.encode(canonical))}';
  }
}
