import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/local_backup.dart';
import 'local_storage_service.dart';

/// Coordinates the local SQLite snapshot with Android's encrypted document I/O.
class BackupService {
  static const _channel = MethodChannel('payment_tracker/backup');

  static Future<void> createEncryptedBackup(String password) async {
    final backup = await LocalStorageService.createBackup();
    final timestamp = backup.createdAt.toIso8601String().split('T').first;
    await _channel.invokeMethod<void>('createEncryptedBackup', {
      'payload': jsonEncode(backup.toJson()),
      'password': password,
      'suggestedName': 'payment-tracker-backup-$timestamp.ptbackup',
    });
  }

  static Future<String?> chooseEncryptedBackup() {
    return _channel.invokeMethod<String>('chooseEncryptedBackup');
  }

  static Future<LocalBackup> decryptBackup(
    String encryptedContent,
    String password,
  ) async {
    final plaintext = await _channel.invokeMethod<String>('decryptBackup', {
      'encryptedContent': encryptedContent,
      'password': password,
    });
    if (plaintext == null) {
      throw const FormatException('Could not read the backup file.');
    }

    final decoded = jsonDecode(plaintext);
    if (decoded is! Map) {
      throw const FormatException('The decrypted backup is not valid data.');
    }
    return LocalBackup.fromJson(Map<String, dynamic>.from(decoded));
  }
}
