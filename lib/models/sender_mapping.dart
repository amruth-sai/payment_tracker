// lib/models/sender_mapping.dart
// Model for mapping SMS senders to user accounts (parent-child relationship)

import 'account.dart';

class SenderMapping {
  final String id;
  final String senderId; // The SMS sender ID (e.g., HDFCBK, ICICIB)
  final String accountId; // The parent account ID this sender belongs to
  final DateTime createdAt;
  final bool isUserAssigned; // true if user manually assigned, false if auto-detected

  SenderMapping({
    required this.id,
    required this.senderId,
    required this.accountId,
    required this.createdAt,
    this.isUserAssigned = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'account_id': accountId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'is_user_assigned': isUserAssigned ? 1 : 0,
    };
  }

  static SenderMapping fromMap(Map<String, dynamic> map) {
    return SenderMapping(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      accountId: map['account_id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      isUserAssigned: (map['is_user_assigned'] as int?) == 1,
    );
  }

  SenderMapping copyWith({
    String? id,
    String? senderId,
    String? accountId,
    DateTime? createdAt,
    bool? isUserAssigned,
  }) {
    return SenderMapping(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      accountId: accountId ?? this.accountId,
      createdAt: createdAt ?? this.createdAt,
      isUserAssigned: isUserAssigned ?? this.isUserAssigned,
    );
  }
}

/// Information about a sender discovered from SMS analysis
class DiscoveredSender {
  final String senderId;
  final int messageCount;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final List<String> sampleMessages; // Sample SMS bodies for user to identify
  final String? suggestedAccountName; // AI/rule-based suggestion for account name
  final String? suggestedAccountType; // 'bank_account' or 'credit_card'

  DiscoveredSender({
    required this.senderId,
    required this.messageCount,
    required this.firstSeen,
    required this.lastSeen,
    required this.sampleMessages,
    this.suggestedAccountName,
    this.suggestedAccountType,
  });

  Map<String, dynamic> toMap() {
    return {
      'sender_id': senderId,
      'message_count': messageCount,
      'first_seen': firstSeen.millisecondsSinceEpoch,
      'last_seen': lastSeen.millisecondsSinceEpoch,
      'sample_messages': sampleMessages.join('|||'), // Use delimiter to store list
      'suggested_account_name': suggestedAccountName,
      'suggested_account_type': suggestedAccountType,
    };
  }

  static DiscoveredSender fromMap(Map<String, dynamic> map) {
    return DiscoveredSender(
      senderId: map['sender_id'] as String,
      messageCount: map['message_count'] as int,
      firstSeen: DateTime.fromMillisecondsSinceEpoch(map['first_seen'] as int),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['last_seen'] as int),
      sampleMessages: (map['sample_messages'] as String? ?? '').split('|||').where((s) => s.isNotEmpty).toList(),
      suggestedAccountName: map['suggested_account_name'] as String?,
      suggestedAccountType: map['suggested_account_type'] as String?,
    );
  }

  String get timeRangeDescription {
    final now = DateTime.now();
    final daysSinceFirst = now.difference(firstSeen).inDays;
    final daysSinceLast = now.difference(lastSeen).inDays;

    if (daysSinceFirst == 0 && daysSinceLast == 0) {
      return 'Today';
    } else if (daysSinceFirst <= 7) {
      return 'This week';
    } else if (daysSinceFirst <= 30) {
      return 'This month';
    } else if (daysSinceFirst <= 90) {
      return 'Last 3 months';
    } else {
      return '$daysSinceFirst days ago';
    }
  }
}

/// Account with its assigned senders (parent-child relationship)
class AccountWithSenders {
  final Account account;
  final List<SenderMapping> senderMappings;
  final List<String> senderIds; // Convenient list of just the sender IDs

  AccountWithSenders({
    required this.account,
    required this.senderMappings,
  }) : senderIds = senderMappings.map((m) => m.senderId).toList();

  bool hasSender(String senderId) {
    return senderIds.contains(senderId);
  }

  int get totalSenders => senderMappings.length;
  int get userAssignedSenders => senderMappings.where((m) => m.isUserAssigned).length;
  int get autoAssignedSenders => senderMappings.where((m) => !m.isUserAssigned).length;
}