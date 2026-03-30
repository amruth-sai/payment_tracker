// lib/models/merged_transfer.dart

import 'package:flutter/foundation.dart';

import 'transaction.dart';

/// Represents a merged view of two related transfer transactions (debit + credit)
class MergedTransfer {
  final String transferGroupId;
  final Transaction sourceTransaction; // The debit transaction (money out)
  final Transaction destinationTransaction; // The credit transaction (money in)
  final DateTime date; // Use the earlier of the two dates
  final double amount; // Should be the same for both transactions
  final String? note; // Combined notes if any

  MergedTransfer({
    required this.transferGroupId,
    required this.sourceTransaction,
    required this.destinationTransaction,
  })  : date = sourceTransaction.date.isBefore(destinationTransaction.date)
            ? sourceTransaction.date
            : destinationTransaction.date,
        amount = sourceTransaction.amount,
        note = _combineNotes(sourceTransaction.note, destinationTransaction.note);

  /// Get the source account name (where money is coming from)
  String get sourceAccountName => sourceTransaction.accountId != null
      ? 'Account ending ${sourceTransaction.accountLast4 ?? '****'}'
      : (sourceTransaction.sender.isNotEmpty
            ? sourceTransaction.sender
            : 'Unknown Account');

  /// Get the destination account name (where money is going to)
  String get destinationAccountName => destinationTransaction.accountId != null
      ? 'Account ending ${destinationTransaction.accountLast4 ?? '****'}'
      : (destinationTransaction.sender.isNotEmpty
            ? destinationTransaction.sender
            : 'Unknown Account');

  /// Get a display name for the transfer
  String get displayName =>
      'Transfer: $sourceAccountName -> $destinationAccountName';

  /// Get the transfer description
  String get description =>
      'Transfer from $sourceAccountName to $destinationAccountName';

  /// Check if both transactions have account IDs
  bool get hasFullAccountInfo =>
      sourceTransaction.accountId != null &&
      destinationTransaction.accountId != null;

  /// Get the payment source (prefer the more specific one)
  PaymentSource get paymentSource {
    // Prefer bank transfers over UPI if one is bank and other is UPI
    if (sourceTransaction.source == PaymentSource.bank ||
        destinationTransaction.source == PaymentSource.bank) {
      return PaymentSource.bank;
    }
    return sourceTransaction.source;
  }

  /// Get combined tags from both transactions
  List<String> get combinedTags {
    final tags = <String>[];
    if (sourceTransaction.tag != null && sourceTransaction.tag!.isNotEmpty) {
      tags.add(sourceTransaction.tag!);
    }
    if (destinationTransaction.tag != null &&
        destinationTransaction.tag!.isNotEmpty &&
        !tags.contains(destinationTransaction.tag!)) {
      tags.add(destinationTransaction.tag!);
    }
    return tags;
  }

  /// Check if either transaction is marked as salary
  bool get isSalary =>
      sourceTransaction.isSalary || destinationTransaction.isSalary;

  /// Check if either transaction is ignored
  bool get isIgnored =>
      sourceTransaction.isIgnored || destinationTransaction.isIgnored;

  /// Check if either transaction has been user corrected
  bool get isUserCorrected =>
      sourceTransaction.isUserCorrected ||
      destinationTransaction.isUserCorrected;

  /// Get the reference ID (prefer the one that exists)
  String? get referenceId =>
      sourceTransaction.referenceId ?? destinationTransaction.referenceId;

  static String? _combineNotes(String? note1, String? note2) {
    if (note1 == null && note2 == null) return null;
    if (note1 == null) return note2;
    if (note2 == null) return note1;
    if (note1 == note2) return note1;
    return '$note1; $note2';
  }

  /// Create a MergedTransfer from two transactions
  static MergedTransfer? fromTransactions(Transaction t1, Transaction t2) {
    if (t1.transferGroupId == null ||
        t2.transferGroupId == null ||
        t1.transferGroupId != t2.transferGroupId) {
      return null;
    }

    if (t1.amount != t2.amount) {
      assert(() {
        debugPrint(
          'Error: Transfer transactions have different amounts: ${t1.amount} != ${t2.amount}',
        );
        return true;
      }());
      return null;
    }

    if (t1.id == t2.id) {
      assert(() {
        debugPrint('Error: Attempting to merge transaction with itself: ${t1.id}');
        return true;
      }());
      return null;
    }

    Transaction source;
    Transaction destination;

    if (t1.isTransferSource && t2.isTransferDestination) {
      source = t1;
      destination = t2;
    } else if (t1.isTransferDestination && t2.isTransferSource) {
      source = t2;
      destination = t1;
    } else if (t1.isDebit && t2.isCredit) {
      source = t1;
      destination = t2;
    } else if (t1.isCredit && t2.isDebit) {
      source = t2;
      destination = t1;
    } else {
      assert(() {
        debugPrint(
          'Error: Cannot determine transfer roles for transactions ${t1.id} and ${t2.id}',
        );
        debugPrint(
          '  T1: ${t1.type.name}, source: ${t1.isTransferSource}, dest: ${t1.isTransferDestination}',
        );
        debugPrint(
          '  T2: ${t2.type.name}, source: ${t2.isTransferSource}, dest: ${t2.isTransferDestination}',
        );
        return true;
      }());
      return null;
    }

    if (source.transferPartnerId != null &&
        source.transferPartnerId != destination.id) {
      assert(() {
        debugPrint('Warning: Transfer partner ID mismatch for ${source.id}');
        return true;
      }());
    }

    if (destination.transferPartnerId != null &&
        destination.transferPartnerId != source.id) {
      assert(() {
        debugPrint('Warning: Transfer partner ID mismatch for ${destination.id}');
        return true;
      }());
    }

    return MergedTransfer(
      transferGroupId: t1.transferGroupId!,
      sourceTransaction: source,
      destinationTransaction: destination,
    );
  }
}

/// Extension to help with transfer merging in lists
extension TransferMerging on List<Transaction> {
  /// Group transactions by transfer group and return merged transfers
  List<MergedTransfer> getMergedTransfers() {
    final transferGroups = <String, List<Transaction>>{};

    for (final transaction in this) {
      if (transaction.transferGroupId != null) {
        transferGroups
            .putIfAbsent(transaction.transferGroupId!, () => [])
            .add(transaction);
      }
    }

    final mergedTransfers = <MergedTransfer>[];
    for (final entry in transferGroups.entries) {
      final groupId = entry.key;
      final group = entry.value;

      if (group.length == 2) {
        final merged = MergedTransfer.fromTransactions(group[0], group[1]);
        if (merged != null) {
          mergedTransfers.add(merged);
        } else {
          assert(() {
            debugPrint(
              'Warning: Transfer group $groupId has 2 transactions but cannot be merged',
            );
            debugPrint(
              '  Transaction 1: ${group[0].id} (${group[0].type.name}, amount: ${group[0].amount})',
            );
            debugPrint(
              '  Transaction 2: ${group[1].id} (${group[1].type.name}, amount: ${group[1].amount})',
            );
            return true;
          }());
        }
      } else if (group.length > 2) {
        assert(() {
          debugPrint(
            'Error: Transfer group $groupId has ${group.length} transactions (expected 2)',
          );
          return true;
        }());
      }
    }

    return mergedTransfers;
  }

  /// Get transactions that are not part of complete transfer pairs
  List<Transaction> getStandaloneTransactions() {
    final transferGroups = <String, List<Transaction>>{};
    final validMergedTransferIds = <String>{};

    for (final transaction in this) {
      if (transaction.transferGroupId != null) {
        transferGroups
            .putIfAbsent(transaction.transferGroupId!, () => [])
            .add(transaction);
      }
    }

    for (final entry in transferGroups.entries) {
      final groupId = entry.key;
      final transactions = entry.value;

      if (transactions.length == 2) {
        final t1 = transactions[0];
        final t2 = transactions[1];

        var isValidGroup = false;

        if ((t1.isTransferSource && t2.isTransferDestination) ||
            (t1.isTransferDestination && t2.isTransferSource)) {
          isValidGroup = true;
        } else if ((t1.isDebit && t2.isCredit) ||
            (t1.isCredit && t2.isDebit)) {
          isValidGroup = true;
        }

        if (isValidGroup && t1.amount == t2.amount) {
          validMergedTransferIds.add(groupId);
        }
      }
    }

    final standalone = <Transaction>[];
    for (final transaction in this) {
      if (transaction.transferGroupId == null) {
        standalone.add(transaction);
      } else if (!validMergedTransferIds.contains(transaction.transferGroupId)) {
        standalone.add(transaction);

        assert(() {
          debugPrint(
            'Warning: Transaction ${transaction.id} has transferGroupId ${transaction.transferGroupId} but is not part of valid transfer pair',
          );
          return true;
        }());
      }
    }

    return standalone;
  }
}
