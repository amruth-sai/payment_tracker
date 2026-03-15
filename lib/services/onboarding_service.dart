// lib/services/onboarding_service.dart
// Service to handle first-time onboarding and sender setup

import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/sender_mapping.dart';
import '../services/local_storage_service.dart';
import '../services/sender_discovery_service.dart';

class OnboardingService {

  /// Check if user has completed the sender setup onboarding
  static Future<bool> hasCompletedSenderOnboarding() async {
    final val = await LocalStorageService.getSetting('has_completed_sender_onboarding');
    return val == 'true';
  }

  /// Mark sender onboarding as completed
  static Future<void> setSenderOnboardingCompleted(bool completed) async {
    if (completed) {
      await LocalStorageService.setSetting('has_completed_sender_onboarding', 'true');
    } else {
      final db = await LocalStorageService.database;
      await db.delete('user_settings',
          where: 'key = ?', whereArgs: ['has_completed_sender_onboarding']);
    }
  }

  /// Get or set the onboarding date range
  static Future<DateTimeRange?> getOnboardingDateRange() async {
    final startMs = await LocalStorageService.getSetting('onboarding_start_date');
    final endMs = await LocalStorageService.getSetting('onboarding_end_date');

    if (startMs != null && endMs != null) {
      final start = DateTime.fromMillisecondsSinceEpoch(int.parse(startMs));
      final end = DateTime.fromMillisecondsSinceEpoch(int.parse(endMs));
      return DateTimeRange(start: start, end: end);
    }

    return null;
  }

  /// Save the onboarding date range
  static Future<void> setOnboardingDateRange(DateTimeRange range) async {
    await LocalStorageService.setSetting(
        'onboarding_start_date', range.start.millisecondsSinceEpoch.toString());
    await LocalStorageService.setSetting(
        'onboarding_end_date', range.end.millisecondsSinceEpoch.toString());
  }

  /// Create default accounts for user's common banks
  static Future<List<Account>> createDefaultAccounts() async {
    final defaultAccounts = [
      Account(
        id: 'account_hdfc_${DateTime.now().millisecondsSinceEpoch}',
        name: 'HDFC Bank',
        type: AccountType.bankAccount,
        bankName: 'HDFC Bank',
        isManuallyAdded: true,
      ),
      Account(
        id: 'account_icici_${DateTime.now().millisecondsSinceEpoch}',
        name: 'ICICI Bank',
        type: AccountType.bankAccount,
        bankName: 'ICICI Bank',
        isManuallyAdded: true,
      ),
      Account(
        id: 'account_sbi_${DateTime.now().millisecondsSinceEpoch}',
        name: 'SBI',
        type: AccountType.bankAccount,
        bankName: 'State Bank of India',
        isManuallyAdded: true,
      ),
      Account(
        id: 'account_airtel_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Airtel Payments Bank',
        type: AccountType.bankAccount,
        bankName: 'Airtel Payments Bank',
        isManuallyAdded: true,
      ),
      Account(
        id: 'account_jio_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Jio Payments Bank',
        type: AccountType.bankAccount,
        bankName: 'Jio Payments Bank',
        isManuallyAdded: true,
      ),
    ];

    // Save accounts
    for (final account in defaultAccounts) {
      await LocalStorageService.saveAccount(account);
    }

    return defaultAccounts;
  }

  /// Auto-assign senders to accounts based on name matching
  static Future<List<SenderMapping>> autoAssignSenders({
    required List<DiscoveredSender> discoveredSenders,
    required List<Account> accounts,
  }) async {
    final autoAssignments = <SenderMapping>[];

    for (final sender in discoveredSenders) {
      final senderUpper = sender.senderId.toUpperCase();

      // Find matching account based on sender ID
      Account? matchingAccount;

      for (final account in accounts) {
        final bankName = account.bankName?.toUpperCase() ?? account.name.toUpperCase();

        // Check for direct matches
        if (_isMatchingBankSender(senderUpper, bankName)) {
          matchingAccount = account;
          break;
        }
      }

      // If we found a match, create the assignment
      if (matchingAccount != null) {
        await SenderDiscoveryService.assignSenderToAccount(
          senderId: sender.senderId,
          accountId: matchingAccount.id,
          isUserAssigned: false, // This is auto-assigned
        );

        autoAssignments.add(SenderMapping(
          id: 'auto_${DateTime.now().millisecondsSinceEpoch}_${sender.senderId}',
          senderId: sender.senderId,
          accountId: matchingAccount.id,
          createdAt: DateTime.now(),
          isUserAssigned: false,
        ));
      }
    }

    return autoAssignments;
  }

  /// Check if sender matches bank name
  static bool _isMatchingBankSender(String senderUpper, String bankNameUpper) {
    final bankPatterns = {
      'HDFC': ['HDFC'],
      'ICICI': ['ICICI'],
      'SBI': ['SBI'],
      'AIRTEL': ['AIRTEL', 'ARTL'],
      'JIO': ['JIO'],
      'AXIS': ['AXIS'],
      'KOTAK': ['KOTAK'],
      'PNB': ['PNB'],
      'BOI': ['BOI'],
      'CANARA': ['CANARA'],
      'UNION': ['UNION'],
      'INDUS': ['INDUS'],
      'YES': ['YES'],
      'IDBI': ['IDBI'],
      'HSBC': ['HSBC'],
      'STANDARD': ['STANDARD', 'SCB'],
      'CITI': ['CITI'],
      'RBL': ['RBL'],
      'FEDERAL': ['FEDERAL', 'FEDRAL'],
      'BOB': ['BOB'],
      'ONECARD': ['ONECARD', 'ONECRD'],
    };

    for (final entry in bankPatterns.entries) {
      final bankKey = entry.key;
      final patterns = entry.value;

      if (bankNameUpper.contains(bankKey)) {
        return patterns.any((pattern) => senderUpper.contains(pattern));
      }
    }

    return false;
  }

  /// Generate smart account suggestions based on discovered senders
  static List<Account> generateAccountSuggestions(List<DiscoveredSender> discoveredSenders) {
    final suggestions = <Account>[];
    final banksSeen = <String>{};

    for (final sender in discoveredSenders) {
      if (sender.suggestedAccountName != null && sender.suggestedAccountType != null) {
        final bankKey = sender.suggestedAccountName!.toLowerCase();

        // Avoid duplicate suggestions
        if (banksSeen.contains(bankKey)) continue;
        banksSeen.add(bankKey);

        final accountType = sender.suggestedAccountType == 'credit_card'
            ? AccountType.creditCard
            : AccountType.bankAccount;

        suggestions.add(Account(
          id: 'suggested_${DateTime.now().millisecondsSinceEpoch}_${suggestions.length}',
          name: sender.suggestedAccountName!,
          type: accountType,
          bankName: sender.suggestedAccountName!,
          isManuallyAdded: false,
        ));
      }
    }

    return suggestions;
  }

  /// Get onboarding progress statistics
  static Future<Map<String, dynamic>> getOnboardingProgress() async {
    final stats = await SenderDiscoveryService.getSenderAssignmentStats();
    final hasCompletedOnboarding = await hasCompletedSenderOnboarding();
    final dateRange = await getOnboardingDateRange();

    return {
      'completed_onboarding': hasCompletedOnboarding,
      'date_range': dateRange,
      'total_senders': stats['total_senders'] ?? 0,
      'assigned_senders': stats['assigned_senders'] ?? 0,
      'user_assigned': stats['user_assigned'] ?? 0,
      'assignment_percentage': stats['total_senders'] != null && stats['total_senders']! > 0
          ? (stats['assigned_senders']! / stats['total_senders']! * 100).round()
          : 0,
    };
  }

  /// Reset onboarding (useful for testing or re-setup)
  static Future<void> resetOnboarding() async {
    final db = await LocalStorageService.database;

    // Delete onboarding settings
    await db.delete('user_settings',
        where: 'key IN (?, ?, ?)',
        whereArgs: ['has_completed_sender_onboarding', 'onboarding_start_date', 'onboarding_end_date']);

    // Clear sender mappings
    await db.delete('sender_mappings');

    // Note: We don't delete accounts as user might want to keep them
  }

  /// Quick setup using recommended time periods
  static DateTimeRange getRecommendedDateRange(String period) {
    final now = DateTime.now();

    switch (period.toLowerCase()) {
      case 'last_week':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      case 'last_month':
        return DateTimeRange(
          start: DateTime(now.year, now.month - 1, now.day),
          end: now,
        );
      case 'last_3_months':
        return DateTimeRange(
          start: DateTime(now.year, now.month - 3, now.day),
          end: now,
        );
      case 'last_6_months':
        return DateTimeRange(
          start: DateTime(now.year, now.month - 6, now.day),
          end: now,
        );
      default: // 'last_month'
        return DateTimeRange(
          start: DateTime(now.year, now.month - 1, now.day),
          end: now,
        );
    }
  }

  /// Validate if the setup is ready for use
  static Future<bool> validateSetup() async {
    final stats = await SenderDiscoveryService.getSenderAssignmentStats();
    final accounts = await LocalStorageService.getAllAccounts();

    // At least one account and some senders assigned
    return accounts.isNotEmpty &&
           (stats['assigned_senders'] ?? 0) > 0;
  }
}