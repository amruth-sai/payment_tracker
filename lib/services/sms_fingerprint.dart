import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'sms_parser.dart';

/// Android row IDs change between devices. Message content is the durable key.
class SmsFingerprint {
  static String normalizedBody(String body) =>
      body.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Copied alerts do not expose an Android row ID or original sender address.
  /// Require the user to confirm the original minute to match any SMS copy.
  static String importedMessage({
    required String body,
    required DateTime date,
  }) {
    final minute = DateTime(
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
    );
    return 'import_${sha256.convert(utf8.encode(jsonEncode([normalizedBody(body), minute.millisecondsSinceEpoch])))}';
  }

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
