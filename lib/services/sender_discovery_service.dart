// lib/services/sender_discovery_service.dart
// Service to discover and analyze SMS senders for account mapping

import 'dart:math';
import '../models/sender_mapping.dart';
import '../services/local_storage_service.dart';
import '../services/sms_parser.dart';

class SenderDiscoveryService {

  /// Analyze SMS messages within date range to discover all senders
  static Future<List<DiscoveredSender>> discoverSenders({
    required DateTime fromDate,
    required DateTime toDate,
    required List<Map<String, dynamic>> smsMessages,
  }) async {
    final Map<String, List<Map<String, dynamic>>> senderGroups = {};

    // Group SMS messages by sender
    for (final sms in smsMessages) {
      final String sender = sms['sender'] ?? '';
      final DateTime date = sms['date'] ?? DateTime.now();
      final String body = sms['body'] ?? '';

      // Skip if outside date range
      if (date.isBefore(fromDate) || date.isAfter(toDate)) continue;

      // Only consider bank-related SMS
      if (!SmsParser.isBankSms(sender)) continue;

      final cleanSender = SmsParser.cleanSender(sender);

      if (!senderGroups.containsKey(cleanSender)) {
        senderGroups[cleanSender] = [];
      }

      senderGroups[cleanSender]!.add({
        'sender': sender,
        'date': date,
        'body': body,
      });
    }

    // Convert to DiscoveredSender objects
    final discoveredSenders = <DiscoveredSender>[];

    for (final entry in senderGroups.entries) {
      final senderId = entry.key;
      final messages = entry.value;

      if (messages.isEmpty) continue;

      // Sort messages by date
      messages.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      final firstSeen = messages.first['date'] as DateTime;
      final lastSeen = messages.last['date'] as DateTime;

      // Get sample messages (up to 3)
      final sampleMessages = messages
          .take(3)
          .map((m) => m['body'] as String)
          .where((body) => body.isNotEmpty)
          .toList();

      // Generate suggestions based on sender ID and message content
      final suggestions = _generateAccountSuggestions(senderId, sampleMessages);

      discoveredSenders.add(DiscoveredSender(
        senderId: senderId,
        messageCount: messages.length,
        firstSeen: firstSeen,
        lastSeen: lastSeen,
        sampleMessages: sampleMessages,
        suggestedAccountName: suggestions['name'],
        suggestedAccountType: suggestions['type'],
      ));
    }

    // Sort by message count (most active senders first)
    discoveredSenders.sort((a, b) => b.messageCount.compareTo(a.messageCount));

    return discoveredSenders;
  }

  /// Generate intelligent suggestions for account name and type based on sender ID and messages
  static Map<String, String?> _generateAccountSuggestions(String senderId, List<String> sampleMessages) {
    final senderUpper = senderId.toUpperCase();

    // Bank name mapping
    final bankMappings = {
      'HDFC': 'HDFC Bank',
      'ICICI': 'ICICI Bank',
      'SBI': 'State Bank of India',
      'AXIS': 'Axis Bank',
      'KOTAK': 'Kotak Mahindra Bank',
      'PNB': 'Punjab National Bank',
      'BOI': 'Bank of India',
      'CANARA': 'Canara Bank',
      'UNION': 'Union Bank',
      'INDUS': 'IndusInd Bank',
      'YES': 'Yes Bank',
      'IDBI': 'IDBI Bank',
      'HSBC': 'HSBC',
      'STANDARD': 'Standard Chartered',
      'CITI': 'Citibank',
      'RBL': 'RBL Bank',
      'FEDERAL': 'Federal Bank',
      'BOB': 'Bank of Baroda',
      'AIRTEL': 'Airtel Payments Bank',
      'JIO': 'Jio Payments Bank',
      'PAYTM': 'Paytm Payments Bank',
      'ONECARD': 'OneCard',
    };

    String? suggestedName;
    String? suggestedType;

    // Find matching bank name
    for (final entry in bankMappings.entries) {
      if (senderUpper.contains(entry.key)) {
        suggestedName = entry.value;
        break;
      }
    }

    // Determine account type based on sender ID and message content
    final creditCardIndicators = ['CC', 'CARD', 'CREDIT', 'ONECARD', 'SLICE'];
    final bankAccountIndicators = ['BANK', 'SAVINGS', 'CURRENT', 'ACE'];

    bool hasCardIndicators = creditCardIndicators.any((indicator) => senderUpper.contains(indicator));
    bool hasBankIndicators = bankAccountIndicators.any((indicator) => senderUpper.contains(indicator));

    // Check message content for additional clues
    for (final message in sampleMessages) {
      final msgLower = message.toLowerCase();
      if (msgLower.contains('credit card') ||
          msgLower.contains('card ending') ||
          msgLower.contains('spent at') ||
          msgLower.contains('transaction at')) {
        hasCardIndicators = true;
      }
      if (msgLower.contains('savings account') ||
          msgLower.contains('current account') ||
          msgLower.contains('a/c credited') ||
          msgLower.contains('account debited')) {
        hasBankIndicators = true;
      }
    }

    // Determine type based on indicators
    if (hasCardIndicators && !hasBankIndicators) {
      suggestedType = 'credit_card';
    } else if (hasBankIndicators && !hasCardIndicators) {
      suggestedType = 'bank_account';
    } else {
      // Default based on common patterns
      if (senderUpper.contains('CARD') || senderUpper.contains('CC')) {
        suggestedType = 'credit_card';
      } else {
        suggestedType = 'bank_account';
      }
    }

    return {
      'name': suggestedName,
      'type': suggestedType,
    };
  }

  /// Get existing sender mappings from database
  static Future<List<SenderMapping>> getAllSenderMappings() async {
    final db = await LocalStorageService.database;
    final rows = await db.query('sender_mappings', orderBy: 'created_at ASC');
    return rows.map((r) => SenderMapping.fromMap(r)).toList();
  }

  /// Get accounts with their assigned senders
  static Future<List<AccountWithSenders>> getAccountsWithSenders() async {
    final accounts = await LocalStorageService.getAllAccounts();
    final senderMappings = await getAllSenderMappings();

    final accountsWithSenders = <AccountWithSenders>[];

    for (final account in accounts) {
      final accountSenders = senderMappings
          .where((mapping) => mapping.accountId == account.id)
          .toList();

      accountsWithSenders.add(AccountWithSenders(
        account: account,
        senderMappings: accountSenders,
      ));
    }

    return accountsWithSenders;
  }

  /// Assign a sender to an account
  static Future<void> assignSenderToAccount({
    required String senderId,
    required String accountId,
    bool isUserAssigned = true,
  }) async {
    final mapping = SenderMapping(
      id: 'mapping_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
      senderId: senderId,
      accountId: accountId,
      createdAt: DateTime.now(),
      isUserAssigned: isUserAssigned,
    );

    final db = await LocalStorageService.database;
    await db.insert('sender_mappings', mapping.toMap());
  }

  /// Remove sender assignment from an account
  static Future<void> removeSenderFromAccount(String senderId, String accountId) async {
    final db = await LocalStorageService.database;
    await db.delete(
      'sender_mappings',
      where: 'sender_id = ? AND account_id = ?',
      whereArgs: [senderId, accountId],
    );
  }

  /// Move a sender from one account to another
  static Future<void> moveSenderToAccount({
    required String senderId,
    required String fromAccountId,
    required String toAccountId,
  }) async {
    final db = await LocalStorageService.database;

    await db.transaction((txn) async {
      // Remove from old account
      await txn.delete(
        'sender_mappings',
        where: 'sender_id = ? AND account_id = ?',
        whereArgs: [senderId, fromAccountId],
      );

      // Add to new account
      final mapping = SenderMapping(
        id: 'mapping_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
        senderId: senderId,
        accountId: toAccountId,
        createdAt: DateTime.now(),
        isUserAssigned: true,
      );

      await txn.insert('sender_mappings', mapping.toMap());
    });
  }

  /// Get the account ID for a given sender
  static Future<String?> getAccountForSender(String senderId) async {
    final db = await LocalStorageService.database;
    final result = await db.query(
      'sender_mappings',
      columns: ['account_id'],
      where: 'sender_id = ?',
      whereArgs: [senderId],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['account_id'] as String;
    }

    return null;
  }

  /// Get all unassigned senders (senders that don't have an account mapping)
  static Future<List<String>> getUnassignedSenders() async {
    final db = await LocalStorageService.database;

    // Get all unique senders from transactions
    final senderRows = await db.rawQuery('''
      SELECT DISTINCT sender
      FROM transactions
      WHERE sender IS NOT NULL
    ''');

    final allSenders = senderRows
        .map((row) => row['sender'] as String)
        .toSet();

    // Get already assigned senders
    final mappingRows = await db.query('sender_mappings', columns: ['sender_id']);
    final assignedSenders = mappingRows
        .map((row) => row['sender_id'] as String)
        .toSet();

    // Return unassigned senders
    return allSenders.difference(assignedSenders).toList();
  }

  /// Reassign transactions when a sender is moved between accounts
  static Future<void> reassignTransactionsForSender(String senderId, String newAccountId) async {
    final db = await LocalStorageService.database;

    await db.update(
      'transactions',
      {'account_id': newAccountId},
      where: 'sender = ?',
      whereArgs: [senderId],
    );
  }

  /// Get statistics about sender assignments
  static Future<Map<String, int>> getSenderAssignmentStats() async {
    final db = await LocalStorageService.database;

    final totalSenders = await db.rawQuery('SELECT COUNT(DISTINCT sender) as count FROM transactions WHERE sender IS NOT NULL');
    final assignedSenders = await db.rawQuery('SELECT COUNT(*) as count FROM sender_mappings');
    final userAssigned = await db.rawQuery('SELECT COUNT(*) as count FROM sender_mappings WHERE is_user_assigned = 1');

    return {
      'total_senders': (totalSenders.first['count'] as int?) ?? 0,
      'assigned_senders': (assignedSenders.first['count'] as int?) ?? 0,
      'user_assigned': (userAssigned.first['count'] as int?) ?? 0,
    };
  }
}