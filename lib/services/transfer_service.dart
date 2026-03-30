// lib/services/transfer_service.dart

import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../models/merged_transfer.dart';
import 'local_storage_service.dart';
import '../constants/transfer_constants.dart';

/// Service for detecting and managing transfer transactions
class TransferService {
  static const _uuid = Uuid();

  /// Auto-detect potential transfer pairs from a list of transactions
  static List<TransferPair> detectPotentialTransfers(List<Transaction> transactions) {
    final potentialPairs = <TransferPair>[];

    // Skip if we have too few transactions to make meaningful pairs
    if (transactions.length < 2) return potentialPairs;

    // Group transactions by amount and date for efficient matching
    final transactionsByAmountAndDate = <String, List<Transaction>>{};

    for (final transaction in transactions) {
      // Skip already linked transactions
      if (transaction.isPartOfTransfer) continue;

      // Create compound key: amount + date (day level for efficiency)
      final dateKey = '${transaction.date.year}-${transaction.date.month}-${transaction.date.day}';
      final amountDateKey = '${transaction.amount}_$dateKey';

      transactionsByAmountAndDate.putIfAbsent(amountDateKey, () => []).add(transaction);
    }

    // Process each amount-date group
    for (final entry in transactionsByAmountAndDate.entries) {
      final transactionsWithAmountDate = entry.value;

      // Need at least 2 transactions to form a pair
      if (transactionsWithAmountDate.length < 2) continue;

      // Early termination for large groups (performance optimization)
      if (transactionsWithAmountDate.length > 20) {
        // For very large groups, only process the most recent transactions
        transactionsWithAmountDate.sort((a, b) => b.date.compareTo(a.date));
        transactionsWithAmountDate.removeRange(20, transactionsWithAmountDate.length);
      }

      // Find debit/credit pairs within this group
      final debits = transactionsWithAmountDate.where((t) => t.isDebit).toList();
      final credits = transactionsWithAmountDate.where((t) => t.isCredit).toList();

      // Optimize: process high-confidence matches first
      for (final debit in debits) {
        Transaction? bestMatch;
        double bestConfidence = 0.0;

        for (final credit in credits) {
          final pair = _evaluateTransferPair(debit, credit);
          if (pair != null && pair.confidence > bestConfidence) {
            bestConfidence = pair.confidence;
            bestMatch = credit;
          }

          // Early break for high-confidence matches
          if (bestConfidence > 0.8) break;
        }

        if (bestMatch != null && bestConfidence > 0.3) {
          final finalPair = _evaluateTransferPair(debit, bestMatch);
          if (finalPair != null) {
            potentialPairs.add(finalPair);
            // Remove matched credit to avoid duplicate pairs
            credits.remove(bestMatch);
          }
        }
      }
    }

    // Sort by confidence (highest first)
    potentialPairs.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Limit results for performance (avoid overwhelming UI)
    return potentialPairs.take(50).toList();
  }

  /// Evaluate if two transactions could be a transfer pair
  static TransferPair? _evaluateTransferPair(Transaction debit, Transaction credit) {
    // Must be different transaction types
    if (debit.type == credit.type) return null;

    // Must have same amount
    if (debit.amount != credit.amount) return null;

    // Skip if they have the same account (not a transfer between accounts)
    if (debit.sender == credit.sender && debit.accountLast4 == credit.accountLast4) {
      return null;
    }

    double confidence = 0.0;
    final reasons = <String>[];

    // Time proximity (transactions close in time are more likely to be transfers)
    final timeDiff = debit.date.difference(credit.date).abs();
    if (timeDiff.inMinutes <= 5) {
      confidence += 0.4;
      reasons.add('Same time (${timeDiff.inMinutes}m apart)');
    } else if (timeDiff.inMinutes <= 30) {
      confidence += 0.3;
      reasons.add('Close time (${timeDiff.inMinutes}m apart)');
    } else if (timeDiff.inHours <= 2) {
      confidence += 0.2;
      reasons.add('Recent time (${timeDiff.inHours}h apart)');
    } else if (timeDiff.inDays <= 1) {
      confidence += 0.1;
      reasons.add('Same day');
    } else {
      confidence -= 0.1; // Penalty for being far apart
    }

    // Account information matching
    if (debit.accountId != null && credit.accountId != null && debit.accountId != credit.accountId) {
      confidence += 0.3;
      reasons.add('Different accounts');
    }

    // Reference ID matching (strong indicator)
    if (debit.referenceId != null && credit.referenceId != null) {
      if (debit.referenceId == credit.referenceId) {
        confidence += 0.5;
        reasons.add('Same reference ID');
      } else {
        confidence -= 0.2; // Different reference IDs is suspicious
      }
    }

    // Transfer category detection
    final debitHasTransferKeyword = TransferConstants.transferKeywords.any((keyword) =>
        debit.rawMessage.toLowerCase().contains(keyword) ||
        (debit.merchant?.toLowerCase().contains(keyword) ?? false));
    final creditHasTransferKeyword = TransferConstants.transferKeywords.any((keyword) =>
        credit.rawMessage.toLowerCase().contains(keyword) ||
        (credit.merchant?.toLowerCase().contains(keyword) ?? false));

    if (debitHasTransferKeyword || creditHasTransferKeyword) {
      confidence += 0.2;
      reasons.add('Transfer keywords detected');
    }

    // Same payment source (UPI to UPI, Bank to Bank)
    if (debit.source == credit.source) {
      confidence += 0.1;
      reasons.add('Same payment method');
    }

    // Round amounts are more likely to be transfers
    if (debit.amount % 100 == 0 || debit.amount % 50 == 0) {
      confidence += 0.1;
      reasons.add('Round amount');
    }

    return TransferPair(
      debitTransaction: debit,
      creditTransaction: credit,
      confidence: min(confidence, 1.0), // Cap at 1.0
      reasons: reasons,
    );
  }

  /// Merge two transactions as a transfer pair
  static Future<void> mergeAsTransfer(Transaction debit, Transaction credit) async {
    final transferGroupId = _uuid.v4();

    // Validate inputs before processing
    if (debit.amount != credit.amount) {
      throw Exception('Cannot merge transactions with different amounts');
    }
    if (debit.id == credit.id) {
      throw Exception('Cannot merge a transaction with itself');
    }
    if (debit.isPartOfTransfer || credit.isPartOfTransfer) {
      throw Exception('Cannot merge transactions that are already part of a transfer');
    }

    // Update the debit transaction
    final updatedDebit = debit.copyWith(
      transferGroupId: transferGroupId,
      transferPartnerId: credit.id,
      isTransferSource: true,
    );

    // Update the credit transaction
    final updatedCredit = credit.copyWith(
      transferGroupId: transferGroupId,
      transferPartnerId: debit.id,
      isTransferDestination: true,
    );

    try {
      // Save both transactions atomically
      await LocalStorageService.updateTransactionsAtomic([updatedDebit, updatedCredit]);
    } catch (e) {
      // If the atomic update fails, ensure data integrity by not having partial updates
      throw Exception('Failed to merge transactions: $e');
    }
  }

  /// Unmerge a transfer pair
  static Future<void> unmergeTransfer(Transaction transaction) async {
    if (!transaction.isPartOfTransfer) return;

    // Get the partner transaction if it exists
    Transaction? partner;
    if (transaction.transferPartnerId != null) {
      final allTransactions = await LocalStorageService.getAllTransactions();
      try {
        partner = allTransactions.firstWhere(
          (t) => t.id == transaction.transferPartnerId,
        );
      } catch (e) {
        // Partner not found - treat as orphaned transaction
        partner = null;
      }
    }

    // Prepare transactions for atomic update
    final transactionsToUpdate = <Transaction>[];

    // Clear transfer information from the main transaction
    final updatedTransaction = transaction.copyWith(
      clearTransferGroup: true,
      clearTransferPartner: true,
      isTransferSource: false,
      isTransferDestination: false,
    );
    transactionsToUpdate.add(updatedTransaction);

    // Clear transfer information from the partner transaction if it exists
    if (partner != null && partner.id != transaction.id) {
      final updatedPartner = partner.copyWith(
        clearTransferGroup: true,
        clearTransferPartner: true,
        isTransferSource: false,
        isTransferDestination: false,
      );
      transactionsToUpdate.add(updatedPartner);
    }

    try {
      // Update all transactions atomically
      await LocalStorageService.updateTransactionsAtomic(transactionsToUpdate);
    } catch (e) {
      throw Exception('Failed to unmerge transfer: $e');
    }
  }

  /// Get all merged transfers from a list of transactions
  static List<MergedTransfer> getMergedTransfers(List<Transaction> transactions) {
    return transactions.getMergedTransfers();
  }

  /// Get standalone transactions (not part of transfers) from a list
  static List<Transaction> getStandaloneTransactions(List<Transaction> transactions) {
    return transactions.getStandaloneTransactions();
  }

  /// Verify data integrity of transfer system and report issues
  static TransferIntegrityReport verifyDataIntegrity(List<Transaction> transactions) {
    final report = TransferIntegrityReport();
    final transferGroups = <String, List<Transaction>>{};

    // Group transactions by transfer ID
    for (final transaction in transactions) {
      if (transaction.transferGroupId != null) {
        transferGroups.putIfAbsent(transaction.transferGroupId!, () => [])
          .add(transaction);
      }
    }

    // Analyze each transfer group
    for (final entry in transferGroups.entries) {
      final groupId = entry.key;
      final group = entry.value;

      if (group.length == 1) {
        // Orphaned transaction - has transfer group but no partner
        report.orphanedTransactions.add(OrphanedTransfer(
          groupId: groupId,
          transaction: group[0],
          issue: 'Single transaction in transfer group (missing partner)',
        ));
      } else if (group.length == 2) {
        final t1 = group[0];
        final t2 = group[1];

        // Validate amounts match
        if (t1.amount != t2.amount) {
          report.invalidTransfers.add(InvalidTransfer(
            groupId: groupId,
            transactions: group,
            issue: 'Amount mismatch: ${t1.amount} != ${t2.amount}',
          ));
        }

        // Validate transaction types
        bool hasDebitCredit = (t1.isDebit && t2.isCredit) || (t1.isCredit && t2.isDebit);
        if (!hasDebitCredit) {
          report.invalidTransfers.add(InvalidTransfer(
            groupId: groupId,
            transactions: group,
            issue: 'Invalid transaction types: ${t1.type.name} & ${t2.type.name}',
          ));
        }

        // Validate transfer flags
        bool hasSourceDest = (t1.isTransferSource || t2.isTransferSource) &&
                            (t1.isTransferDestination || t2.isTransferDestination);
        if (!hasSourceDest) {
          report.validationWarnings.add(ValidationWarning(
            groupId: groupId,
            issue: 'Missing transfer source/destination flags',
          ));
        }

        // Validate partner IDs
        if (t1.transferPartnerId != t2.id || t2.transferPartnerId != t1.id) {
          report.validationWarnings.add(ValidationWarning(
            groupId: groupId,
            issue: 'Partner ID mismatch',
          ));
        }

      } else {
        // Multiple transactions with same group ID
        report.corruptedGroups.add(CorruptedTransferGroup(
          groupId: groupId,
          transactions: group,
          issue: 'Multiple transactions (${group.length}) with same transfer group ID',
        ));
      }
    }

    return report;
  }

  /// Attempt to fix data integrity issues
  static Future<TransferCleanupResult> cleanupDataIntegrity(List<Transaction> transactions) async {
    final result = TransferCleanupResult();
    final report = verifyDataIntegrity(transactions);

    try {
      // Fix orphaned transactions
      final orphanedUpdates = <Transaction>[];
      for (final orphan in report.orphanedTransactions) {
        final cleanedTransaction = orphan.transaction.copyWith(
          clearTransferGroup: true,
          clearTransferPartner: true,
          isTransferSource: false,
          isTransferDestination: false,
        );
        orphanedUpdates.add(cleanedTransaction);
        result.fixedOrphans++;
      }

      // Fix corrupted groups by breaking them apart
      final corruptedUpdates = <Transaction>[];
      for (final corrupted in report.corruptedGroups) {
        for (final transaction in corrupted.transactions) {
          final cleanedTransaction = transaction.copyWith(
            clearTransferGroup: true,
            clearTransferPartner: true,
            isTransferSource: false,
            isTransferDestination: false,
          );
          corruptedUpdates.add(cleanedTransaction);
          result.fixedCorrupted++;
        }
      }

      // Apply fixes atomically if any
      final allUpdates = [...orphanedUpdates, ...corruptedUpdates];
      if (allUpdates.isNotEmpty) {
        await LocalStorageService.updateTransactionsAtomic(allUpdates);
        result.wasSuccessful = true;
      } else {
        result.wasSuccessful = true; // No issues to fix
      }

      result.unfixableIssues = report.invalidTransfers.length + report.validationWarnings.length;

    } catch (e) {
      result.wasSuccessful = false;
      result.errorMessage = 'Failed to apply fixes: $e';
    }

    return result;
  }
}

/// Represents a potential transfer pair with confidence score
class TransferPair {
  final Transaction debitTransaction;
  final Transaction creditTransaction;
  final double confidence; // 0.0 to 1.0
  final List<String> reasons;

  TransferPair({
    required this.debitTransaction,
    required this.creditTransaction,
    required this.confidence,
    required this.reasons,
  });

  /// Get confidence as a percentage string
  String get confidencePercentage => '${(confidence * 100).round()}%';

  /// Get a display description of why this is a potential transfer
  String get description {
    final timeDiff = debitTransaction.date.difference(creditTransaction.date).abs();
    return 'Same amount (₹${debitTransaction.amount.toStringAsFixed(2)}) • ${timeDiff.inMinutes <= 60 ? '${timeDiff.inMinutes}m apart' : '${timeDiff.inHours}h apart'}';
  }

  /// Get the transfer amount
  double get amount => debitTransaction.amount;

  /// Get the earlier of the two transaction dates
  DateTime get earliestDate => debitTransaction.date.isBefore(creditTransaction.date)
      ? debitTransaction.date
      : creditTransaction.date;
}

/// Data integrity report for transfer system
class TransferIntegrityReport {
  final List<OrphanedTransfer> orphanedTransactions = [];
  final List<InvalidTransfer> invalidTransfers = [];
  final List<CorruptedTransferGroup> corruptedGroups = [];
  final List<ValidationWarning> validationWarnings = [];

  bool get hasIssues => orphanedTransactions.isNotEmpty ||
                       invalidTransfers.isNotEmpty ||
                       corruptedGroups.isNotEmpty ||
                       validationWarnings.isNotEmpty;

  int get totalIssues => orphanedTransactions.length +
                        invalidTransfers.length +
                        corruptedGroups.length +
                        validationWarnings.length;

  String get summary {
    if (!hasIssues) return 'No data integrity issues found';

    final parts = <String>[];
    if (orphanedTransactions.isNotEmpty) parts.add('${orphanedTransactions.length} orphaned');
    if (invalidTransfers.isNotEmpty) parts.add('${invalidTransfers.length} invalid');
    if (corruptedGroups.isNotEmpty) parts.add('${corruptedGroups.length} corrupted groups');
    if (validationWarnings.isNotEmpty) parts.add('${validationWarnings.length} warnings');

    return 'Found ${parts.join(', ')} transfer issues';
  }
}

class OrphanedTransfer {
  final String groupId;
  final Transaction transaction;
  final String issue;

  OrphanedTransfer({
    required this.groupId,
    required this.transaction,
    required this.issue,
  });
}

class InvalidTransfer {
  final String groupId;
  final List<Transaction> transactions;
  final String issue;

  InvalidTransfer({
    required this.groupId,
    required this.transactions,
    required this.issue,
  });
}

class CorruptedTransferGroup {
  final String groupId;
  final List<Transaction> transactions;
  final String issue;

  CorruptedTransferGroup({
    required this.groupId,
    required this.transactions,
    required this.issue,
  });
}

class ValidationWarning {
  final String groupId;
  final String issue;

  ValidationWarning({
    required this.groupId,
    required this.issue,
  });
}

class TransferCleanupResult {
  bool wasSuccessful = false;
  int fixedOrphans = 0;
  int fixedCorrupted = 0;
  int unfixableIssues = 0;
  String? errorMessage;

  String get summary {
    if (!wasSuccessful) {
      return 'Cleanup failed: ${errorMessage ?? 'Unknown error'}';
    }

    if (fixedOrphans == 0 && fixedCorrupted == 0 && unfixableIssues == 0) {
      return 'No issues found - data is clean';
    }

    final parts = <String>[];
    if (fixedOrphans > 0) parts.add('Fixed $fixedOrphans orphaned transactions');
    if (fixedCorrupted > 0) parts.add('Fixed $fixedCorrupted corrupted groups');
    if (unfixableIssues > 0) parts.add('$unfixableIssues issues require manual review');

    return parts.join(', ');
  }
}