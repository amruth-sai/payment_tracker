import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../models/sender_mapping.dart';
import '../models/salary_cycle.dart';
import '../models/budget.dart';
import '../models/app_alert.dart';
import '../models/app_category.dart';
import '../models/local_backup.dart';
import '../models/transaction_review.dart';
import '../models/sms_processing_record.dart';
import '../utils/money.dart';
import 'category_service.dart';
import 'database_schema.dart';
import 'sms_parser.dart';
import '../constants/transfer_constants.dart';

class LocalStorageService {
  static Database? _db;
  static Future<Database>? _opening;
  static const int _dbVersion = DatabaseSchema.version;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    return _opening ??= _open();
  }

  static Future<Database> _open() async {
    try {
      _db = await openDatabase(
        join(await getDatabasesPath(), DatabaseSchema.fileName),
        version: DatabaseSchema.version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.create,
      );
      return _db!;
    } finally {
      _opening = null;
    }
  }

  /// Allows integration tests to use the production schema with real SQLite.
  static void useDatabaseForTesting(Database db) {
    _db = db;
  }

  static Future<LocalBackup> createBackup() async {
    final db = await database;
    return db.transaction((txn) async {
      final data = <String, List<Map<String, dynamic>>>{};
      for (final table in DatabaseSchema.tables) {
        data[table] = (await txn.query(
          table,
        )).map((row) => Map<String, dynamic>.from(row)).toList();
      }
      return LocalBackup(
        createdAt: DateTime.now().toUtc(),
        databaseVersion: _dbVersion,
        tables: data,
      );
    });
  }

  static Future<int> restoreBackup(
    LocalBackup backup,
    BackupRestoreMode mode,
  ) async {
    if (backup.databaseVersion != _dbVersion ||
        backup.tables.length != DatabaseSchema.tables.length ||
        !DatabaseSchema.tables.every(backup.tables.containsKey)) {
      throw const FormatException(
        'Only complete first-release backups are supported.',
      );
    }
    final db = await database;
    final restored = await db.transaction((txn) async {
      if (mode == BackupRestoreMode.replace) {
        for (final table in DatabaseSchema.tables.reversed) {
          await txn.delete(table);
        }
      }
      var inserted = 0;
      for (final table in DatabaseSchema.tables) {
        final columns = await txn.rawQuery('PRAGMA table_info($table)');
        final allowed = columns
            .map((column) => column['name'] as String)
            .toSet();
        final primaryKey =
            columns.firstWhere((column) => column['pk'] == 1)['name'] as String;
        for (final row in backup.tables[table]!) {
          if (row.keys.toSet().difference(allowed).isNotEmpty ||
              row.length != allowed.length ||
              row[primaryKey] == null) {
            throw FormatException('Invalid $table record in backup.');
          }
          final existing = await txn.query(
            table,
            where: '$primaryKey = ?',
            whereArgs: [row[primaryKey]],
            limit: 1,
          );
          if (mode == BackupRestoreMode.merge && existing.isNotEmpty) continue;
          await txn.insert(table, row);
          inserted++;
        }
      }
      if ((await txn.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const FormatException('The backup contains broken record links.');
      }
      // Scan cursors belong to the current SMS database. Fingerprints prevent duplicates.
      await txn.delete(
        'user_settings',
        where: 'key = ?',
        whereArgs: ['last_sms_scan_at'],
      );
      return inserted;
    });
    SmsParser.clearSenderMappingCache();
    return restored;
  }

  // ==================== TRANSACTION OPERATIONS ====================

  /// Save a parsed transaction to local storage
  static Future<void> saveTransaction(Transaction tx) => saveTransactions([tx]);

  static Future<void> saveTransactions(List<Transaction> transactions) async {
    await (await database).transaction((txn) async {
      for (final tx in transactions) {
        final changed = await txn.update(
          'transactions',
          _transactionValues(tx),
          where: 'id = ?',
          whereArgs: [tx.id],
        );
        if (changed == 0) {
          await txn.insert('transactions', _transactionValues(tx));
        }
      }
    });
  }

  /// Commits the result of an SMS scan as one unit. A message is never marked
  /// processed without its transaction, review item, or skip reason.
  static Future<void> saveScanResults({
    required List<Transaction> transactions,
    required List<TransactionReview> reviews,
    required List<SmsProcessingRecord> records,
  }) async {
    if (records.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final transaction in transactions) {
        batch.insert(
          'transactions',
          _transactionValues(transaction),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final review in reviews) {
        batch.insert(
          'transaction_reviews',
          review.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final record in records) {
        batch.insert(
          'sms_processing',
          record.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        batch.insert('processed_sms', {
          'sms_id': record.smsId,
          'processed_at': now,
          'is_transaction': record.outcome == SmsProcessingOutcome.transaction
              ? 1
              : 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<List<SmsProcessingRecord>> getSkippedPaymentMessages() async {
    final db = await database;
    final rows = await db.query(
      'sms_processing',
      where: 'outcome = ? AND raw_message IS NOT NULL',
      whereArgs: [SmsProcessingOutcome.skipped.name],
      orderBy: 'date DESC',
    );
    return rows.map(SmsProcessingRecord.fromMap).toList();
  }

  static Future<int> countSkippedMessages() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sms_processing WHERE outcome = ?',
            [SmsProcessingOutcome.skipped.name],
          ),
        ) ??
        0;
  }

  /// Allows a user to supply an amount when local rules could not read one.
  /// The review inbox then collects the direction and optional category.
  static Future<void> sendSkippedMessageToReview(
    SmsProcessingRecord record,
    double amount,
  ) async {
    if (record.rawMessage == null || !amount.isFinite || amount < 0.01) {
      throw ArgumentError(
        'A payment-like message and a positive amount are required.',
      );
    }
    final db = await database;
    final review = TransactionReview(
      id: record.smsId,
      amount: amount,
      source: record.rawMessage!.toLowerCase().contains('upi')
          ? PaymentSource.upi
          : PaymentSource.bank,
      sender: record.sender,
      date: record.date,
      rawMessage: record.rawMessage!,
      createdAt: DateTime.now(),
    );
    await db.transaction((txn) async {
      final updated = await txn.update(
        'sms_processing',
        {
          'outcome': SmsProcessingOutcome.needsReview.name,
          'reason': 'sent_to_review_by_user',
          'raw_message': null,
        },
        where: 'sms_id = ? AND outcome = ?',
        whereArgs: [record.smsId, SmsProcessingOutcome.skipped.name],
      );
      if (updated != 1) {
        throw StateError('This message is no longer skipped.');
      }
      await txn.insert(
        'transaction_reviews',
        review.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  // ==================== TRANSACTION REVIEW OPERATIONS ====================

  static Future<void> saveTransactionReviews(
    List<TransactionReview> reviews,
  ) async {
    if (reviews.isEmpty) return;

    final db = await database;
    final batch = db.batch();
    for (final review in reviews) {
      batch.insert(
        'transaction_reviews',
        review.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<TransactionReview>> getTransactionReviews({
    bool ignored = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      'transaction_reviews',
      where: 'is_ignored = ?',
      whereArgs: [ignored ? 1 : 0],
      orderBy: 'date DESC',
    );
    return rows.map(TransactionReview.fromMap).toList();
  }

  static Future<void> updateTransactionReviewCategory(
    String reviewId,
    String? categoryId,
  ) async {
    final db = await database;
    await db.update(
      'transaction_reviews',
      {'category_id': categoryId, 'category_source': 'user'},
      where: 'id = ?',
      whereArgs: [reviewId],
    );
  }

  static Future<void> updateTransactionReviewMerchant(
    String reviewId,
    String merchant,
    String? tag,
  ) async {
    final db = await database;
    await db.update(
      'transaction_reviews',
      {'merchant': merchant, 'tag': tag},
      where: 'id = ?',
      whereArgs: [reviewId],
    );
  }

  static Future<void> ignoreTransactionReview(String reviewId) async {
    final db = await database;
    await db.update(
      'transaction_reviews',
      {'is_ignored': 1},
      where: 'id = ?',
      whereArgs: [reviewId],
    );
  }

  static Future<void> restoreTransactionReview(String reviewId) async {
    final db = await database;
    await db.update(
      'transaction_reviews',
      {'is_ignored': 0},
      where: 'id = ?',
      whereArgs: [reviewId],
    );
  }

  static Future<void> resolveTransactionReview(
    String reviewId,
    Transaction transaction,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'transactions',
        _transactionValues(transaction),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'transaction_reviews',
        where: 'id = ?',
        whereArgs: [reviewId],
      );
      await txn.update(
        'sms_processing',
        {
          'outcome': SmsProcessingOutcome.transaction.name,
          'reason': 'confirmed_by_user',
        },
        where: 'sms_id = ?',
        whereArgs: [reviewId],
      );
      await txn.update(
        'processed_sms',
        {'is_transaction': 1},
        where: 'sms_id = ?',
        whereArgs: [reviewId],
      );
    });
  }

  static Future<void> saveMerchantRule(MerchantRule rule) async {
    final db = await database;
    await db.insert(
      'merchant_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<MerchantRule>> getMerchantRules({
    bool enabledOnly = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      'merchant_rules',
      where: enabledOnly ? 'is_enabled = 1' : null,
      orderBy: 'created_at DESC',
    );
    return rows.map(MerchantRule.fromMap).toList();
  }

  static Future<void> deleteMerchantRule(String ruleId) async {
    final db = await database;
    await db.delete('merchant_rules', where: 'id = ?', whereArgs: [ruleId]);
  }

  static Future<int> countTransactionsMatchingMerchantRule(
    MerchantRule rule,
  ) async {
    final db = await database;
    final rows = await db.query('transactions', columns: ['raw_message']);
    final matchText = rule.matchText.toLowerCase();
    return rows
        .where(
          (row) => ((row['raw_message'] as String?) ?? '')
              .toLowerCase()
              .contains(matchText),
        )
        .length;
  }

  /// Applies only the fields the rule defines, leaving amount, direction, and
  /// any unspecified category or tag untouched.
  static Future<int> applyMerchantRuleToExistingTransactions(
    MerchantRule rule,
  ) async {
    if (!rule.isEnabled) {
      throw StateError('Enable this merchant rule before applying it.');
    }
    final db = await database;
    final rows = await db.query('transactions', columns: ['id', 'raw_message']);
    final matchText = rule.matchText.toLowerCase();
    final matchingIds = rows
        .where(
          (row) => ((row['raw_message'] as String?) ?? '')
              .toLowerCase()
              .contains(matchText),
        )
        .map((row) => row['id'] as String)
        .toList();
    if (matchingIds.isEmpty) return 0;

    final values = <String, Object?>{
      'merchant': rule.merchant,
      'is_user_corrected': 1,
    };
    if (rule.tag != null) {
      values['tag'] = rule.tag;
    }

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in matchingIds) {
        batch.update('transactions', values, where: 'id = ?', whereArgs: [id]);
        if (rule.categoryId != null) {
          batch.update(
            'transactions',
            {
              'category_id': rule.categoryId,
              'category_source': 'merchant_rule',
            },
            where: "id = ? AND COALESCE(category_source, '') != 'user'",
            whereArgs: [id],
          );
        }
      }
      await batch.commit(noResult: true);
    });
    return matchingIds.length;
  }

  static Future<MerchantRule?> getMatchingMerchantRule(
    String rawMessage,
  ) async {
    return CategoryService.matchingMerchantRule(
      await getMerchantRules(enabledOnly: true),
      rawMessage,
    );
  }

  /// Preview recategorization without changing older or user-selected labels.
  static Future<List<RuleCategoryChange>> previewRuleCategories() async {
    final transactions = await getAllTransactions();
    final rules = await getMerchantRules(enabledOnly: true);
    final changes = <RuleCategoryChange>[];
    for (final transaction in transactions) {
      if (transaction.categorySource == 'user') {
        continue;
      }
      final matchingRule = CategoryService.matchingMerchantRule(
        rules,
        transaction.rawMessage,
      );
      final assignment = CategoryService.assign(
        transaction.copyWith(clearCategory: true),
        merchantRule: matchingRule,
      );
      if (transaction.categoryId == assignment.categoryId &&
          transaction.categorySource == assignment.source) {
        continue;
      }
      changes.add(
        RuleCategoryChange(
          transactionId: transaction.id,
          merchant: transaction.displayName,
          oldCategoryId: transaction.categoryId,
          assignment: assignment,
        ),
      );
    }
    return changes;
  }

  static Future<void> applyRuleCategories(
    List<RuleCategoryChange> changes,
  ) async {
    if (changes.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final change in changes) {
        batch.update(
          'transactions',
          {
            'category_id': change.assignment.categoryId,
            'category_source': change.assignment.source,
          },
          where:
              "id = ? AND (category_source IS NULL OR category_source = 'merchant_rule')",
          whereArgs: [change.transactionId],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  static Map<String, dynamic> _transactionValues(Transaction tx) {
    return {
      'id': tx.id,
      'sms_id': tx.id,
      'amount': Money.toPaise(tx.amount),
      'type': tx.type.name,
      'source': tx.source.name,
      'sender': tx.sender,
      'merchant': tx.merchant,
      'account_last4': tx.accountLast4,
      'date': tx.date.millisecondsSinceEpoch,
      'raw_message': tx.rawMessage,
      'reference_id': tx.referenceId,
      'balance': tx.balance == null ? null : Money.toPaise(tx.balance!),
      'account_id': tx.accountId,
      'is_user_corrected': tx.isUserCorrected ? 1 : 0,
      'is_salary': tx.isSalary ? 1 : 0,
      'category_id': tx.categoryId,
      'category_source': tx.categorySource,
      'note': tx.note,
      'tag': tx.tag,
      'is_ignored': tx.isIgnored ? 1 : 0,
      TransferConstants.transferGroupIdField: tx.transferGroupId,
      TransferConstants.transferPartnerIdField: tx.transferPartnerId,
      TransferConstants.isTransferSourceField: tx.isTransferSource ? 1 : 0,
      TransferConstants.isTransferDestinationField: tx.isTransferDestination
          ? 1
          : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Links pairs atomically without overwriting notes, categories, or other edits.
  /// A stale or overlapping suggestion aborts the entire batch.
  static Future<void> mergeTransferPairsAtomic(
    List<({String debitId, String creditId, String groupId})> pairs,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final usedIds = <String>{};
      final usedGroups = <String>{};
      for (final pair in pairs) {
        if (!usedIds.add(pair.debitId) ||
            !usedIds.add(pair.creditId) ||
            !usedGroups.add(pair.groupId)) {
          throw StateError('A transaction can belong to only one transfer.');
        }
        final rows = await txn.query(
          'transactions',
          where: 'id IN (?, ?)',
          whereArgs: [pair.debitId, pair.creditId],
        );
        if (rows.length != 2) {
          throw StateError('A suggested transaction no longer exists.');
        }
        final current = {
          for (final row in rows) row['id']: _rowToTransaction(row),
        };
        final debit = current[pair.debitId]!;
        final credit = current[pair.creditId]!;
        if (!debit.isDebit ||
            !credit.isCredit ||
            debit.isIgnored ||
            credit.isIgnored ||
            debit.isSalary ||
            credit.isSalary ||
            debit.isPartOfTransfer ||
            credit.isPartOfTransfer ||
            Money.toPaise(debit.amount) != Money.toPaise(credit.amount) ||
            (debit.accountId != null && debit.accountId == credit.accountId) ||
            (debit.sender == credit.sender &&
                debit.accountLast4 == credit.accountLast4) ||
            debit.date.difference(credit.date).abs() >
                const Duration(days: 1)) {
          throw StateError('A suggestion has changed. Refresh and try again.');
        }
        for (final tx in [debit, credit]) {
          await txn.update(
            'transactions',
            {
              'transfer_group_id': pair.groupId,
              'transfer_partner_id': tx.isDebit ? credit.id : debit.id,
              'is_transfer_source': tx.isDebit ? 1 : 0,
              'is_transfer_destination': tx.isCredit ? 1 : 0,
              'is_user_corrected': 1,
            },
            where: 'id = ?',
            whereArgs: [tx.id],
          );
        }
      }
    });
  }

  /// Update multiple transactions atomically (for transfer operations)
  static Future<void> updateTransactionsAtomic(
    List<Transaction> transactions,
  ) async {
    final db = await database;

    // Use database transaction for atomic operation
    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final tx in transactions) {
        batch.update(
          'transactions',
          {
            'type': tx.type.name,
            'source': tx.source.name,
            'merchant': tx.merchant,
            'account_id': tx.accountId,
            'is_user_corrected': 1,
            'is_salary': tx.isSalary ? 1 : 0,
            'category_id': tx.categoryId,
            'category_source': tx.categorySource,
            'note': tx.note,
            'tag': tx.tag,
            'is_ignored': tx.isIgnored ? 1 : 0,
            'transfer_group_id': tx.transferGroupId,
            'transfer_partner_id': tx.transferPartnerId,
            'is_transfer_source': tx.isTransferSource ? 1 : 0,
            'is_transfer_destination': tx.isTransferDestination ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [tx.id],
        );
      }

      await batch.commit(noResult: true);
    });
  }

  /// Get all cached transactions
  static Future<List<Transaction>> getAllTransactions() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'date DESC');

    return rows.map(_rowToTransaction).toList();
  }

  /// Get transactions within a date range
  static Future<List<Transaction>> getTransactionsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'date >= ? AND date <= ? AND is_ignored = 0',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'date DESC',
    );

    return rows.map(_rowToTransaction).toList();
  }

  /// Get active transactions after applying tracking settings and ignored filters.
  static Future<List<Transaction>> getTrackedTransactions({
    DateTime? start,
    DateTime? end,
  }) async {
    final trackFromDate = await getTrackFromDate();
    final trackFromTxId = await getTrackFromTransactionId();

    DateTime? effectiveStart = start;
    if (trackFromDate != null &&
        (effectiveStart == null || trackFromDate.isAfter(effectiveStart))) {
      effectiveStart = trackFromDate;
    }

    List<Transaction> transactions = effectiveStart != null
        ? await getTransactionsSince(effectiveStart)
        : await getAllTransactions();

    if (end != null) {
      transactions = transactions.where((t) => !t.date.isAfter(end)).toList();
    }

    if (start != null) {
      transactions = transactions
          .where((t) => !t.date.isBefore(start))
          .toList();
    }

    if (trackFromTxId != null && trackFromTxId.isNotEmpty) {
      final idx = transactions.indexWhere((t) => t.id == trackFromTxId);
      if (idx != -1) {
        transactions = transactions.sublist(0, idx + 1);
      }
    }

    return transactions.where((t) => !t.isIgnored).toList();
  }

  /// Convert database row to Transaction object
  static Transaction _rowToTransaction(Map<String, dynamic> row) {
    return Transaction(
      id: row['id'] as String,
      amount: Money.fromPaise(row['amount']!),
      type: TransactionType.values.firstWhere((t) => t.name == row['type']),
      source: PaymentSource.values.firstWhere((s) => s.name == row['source']),
      sender: row['sender'] as String,
      merchant: row['merchant'] as String?,
      accountLast4: row['account_last4'] as String?,
      date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
      rawMessage: row['raw_message'] as String,
      referenceId: row['reference_id'] as String?,
      balance: row['balance'] == null ? null : Money.fromPaise(row['balance']!),
      accountId: row['account_id'] as String?,
      isUserCorrected: (row['is_user_corrected'] as int?) == 1,
      isSalary: (row['is_salary'] as int?) == 1,
      categoryId: row['category_id'] as String?,
      categorySource: row['category_source'] as String?,
      note: row['note'] as String?,
      tag: row['tag'] as String?,
      isIgnored: (row['is_ignored'] as int?) == 1,
      transferGroupId: row[TransferConstants.transferGroupIdField] as String?,
      transferPartnerId:
          row[TransferConstants.transferPartnerIdField] as String?,
      isTransferSource:
          (row[TransferConstants.isTransferSourceField] as int?) == 1,
      isTransferDestination:
          (row[TransferConstants.isTransferDestinationField] as int?) == 1,
    );
  }

  // ==================== ACCOUNT OPERATIONS ====================

  /// Save an account
  static Future<void> saveAccount(Account account) async {
    final db = await database;
    await db.transaction((txn) async {
      final changed = await txn.update(
        'accounts',
        account.toMap(),
        where: 'id = ?',
        whereArgs: [account.id],
      );
      if (changed == 0) await txn.insert('accounts', account.toMap());
    });
    SmsParser.clearSenderMappingCache();
  }

  /// Get all accounts
  static Future<List<Account>> getAllAccounts() async {
    final db = await database;
    final rows = await db.query('accounts', orderBy: 'created_at DESC');
    return rows.map((r) => Account.fromMap(r)).toList();
  }

  /// Delete an account
  static Future<void> deleteAccount(String accountId) async {
    await (await database).delete(
      'accounts',
      where: 'id = ?',
      whereArgs: [accountId],
    );
    SmsParser.clearSenderMappingCache();
  }

  /// Auto-detect accounts from transactions
  static Future<List<Account>> detectAccountsFromTransactions() async {
    final db = await database;

    // Get unique account_last4 and sender combinations
    final rows = await db.rawQuery('''
      SELECT DISTINCT account_last4, sender, source
      FROM transactions 
      WHERE account_last4 IS NOT NULL
    ''');

    final existingAccounts = await getAllAccounts();
    final existingKeys = existingAccounts
        .map((a) => '${a.bankName}:${a.last4Digits}:${a.type.name}')
        .toSet();

    final newAccounts = <Account>[];
    for (final row in rows) {
      final last4 = row['account_last4'] as String?;
      if (last4 != null) {
        final sender = (row['sender'] as String?) ?? 'Unknown';
        final source = row['source'] as String?;

        final type = source == 'card'
            ? AccountType.creditCard
            : AccountType.bankAccount;
        final name = _extractBankName(sender);
        final key = '$name:$last4:${type.name}';
        if (!existingKeys.add(key)) continue;

        newAccounts.add(
          Account(
            id: 'auto_${sender}_${last4}_${type.name}',
            name: name,
            type: type,
            last4Digits: last4,
            bankName: name,
            isManuallyAdded: false,
          ),
        );
      }
    }

    // Save new accounts
    for (final account in newAccounts) {
      await saveAccount(account);
    }

    return newAccounts;
  }

  static String _extractBankName(String sender) {
    final bankNames = {
      'HDFC': 'HDFC Bank',
      'SBI': 'SBI',
      'ICICI': 'ICICI Bank',
      'AXIS': 'Axis Bank',
      'KOTAK': 'Kotak Bank',
      'BOB': 'Bank of Baroda',
      'BOBONE': 'OneCard (BOB)',
      'ONECARD': 'OneCard',
      'AIRTEL': 'Airtel Payments Bank',
      'JIO': 'Jio Payments Bank',
      'PAYTM': 'Paytm',
      'GPAY': 'Google Pay',
    };

    for (final entry in bankNames.entries) {
      if (sender.toUpperCase().contains(entry.key)) {
        return entry.value;
      }
    }
    return sender;
  }

  // ==================== SENDER MAPPING OPERATIONS ====================

  /// Save a sender mapping
  static Future<void> saveSenderMapping(SenderMapping mapping) async {
    final db = await database;
    await db.insert(
      'sender_mappings',
      mapping.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    SmsParser.clearSenderMappingCache();
  }

  /// Get all sender mappings
  static Future<List<SenderMapping>> getAllSenderMappings() async {
    final db = await database;
    final rows = await db.query('sender_mappings');
    return rows.map((r) => SenderMapping.fromMap(r)).toList();
  }

  /// Delete all sender mappings for an account
  static Future<void> deleteSenderMappingsForAccount(String accountId) async {
    final db = await database;
    await db.delete(
      'sender_mappings',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    SmsParser.clearSenderMappingCache();
  }

  /// Get transactions by account
  static Future<List<Transaction>> getTransactionsByAccount(
    String accountId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'date DESC',
    );
    return rows.map(_rowToTransaction).toList();
  }

  /// Get spending summary by account
  static Future<Map<String, Map<String, double>>> getSpendingByAccount() async {
    final db = await database;

    final rows = await db.rawQuery('''
      SELECT 
        COALESCE(account_id, sender || ':' || COALESCE(account_last4, '')) as account_key,
        type,
        SUM(amount) as total
      FROM transactions
      WHERE is_ignored = 0
      GROUP BY account_key, type
    ''');

    final result = <String, Map<String, double>>{};
    for (final row in rows) {
      final key = row['account_key'] as String;
      final type = row['type'] as String;
      final total = Money.fromPaise(row['total']!);

      result.putIfAbsent(key, () => {'credit': 0.0, 'debit': 0.0});
      result[key]![type] = total;
    }

    return result;
  }

  // ==================== SALARY CYCLE OPERATIONS ====================

  /// Save a salary cycle
  static Future<void> saveSalaryCycle(SalaryCycle cycle) async {
    final db = await database;
    await db.insert('salary_cycles', {
      ...cycle.toMap(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get all salary cycles with transactions
  static Future<List<SalaryCycle>> getAllSalaryCycles() async {
    final db = await database;
    final rows = await db.query('salary_cycles', orderBy: 'start_date DESC');

    final cycles = <SalaryCycle>[];
    for (final row in rows) {
      final cycle = SalaryCycle.fromMap(row);

      // Load transactions for this cycle
      final endDate = cycle.endDate ?? DateTime.now();
      final transactions = await getTransactionsByDateRange(
        cycle.startDate,
        endDate,
      );

      cycles.add(
        cycle.copyWith(
          transactions: transactions
              .where((tx) => cycle.contains(tx.date))
              .toList(),
        ),
      );
    }

    return cycles;
  }

  /// Mark a transaction as salary
  static Future<void> markAsSalary(String transactionId, bool isSalary) async {
    final db = await database;
    await db.update(
      'transactions',
      {'is_salary': isSalary ? 1 : 0},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  /// Get potential salary transactions (large credits)
  static Future<List<Transaction>> getPotentialSalaryTransactions({
    List<String> employerKeywords = const ['SALARY'],
    double? minimumAmount,
  }) async {
    final db = await database;

    String whereClause = "type = 'credit' AND is_ignored = 0";
    final whereArgs = <dynamic>[];

    if (minimumAmount != null) {
      whereClause += ' AND amount >= ?';
      whereArgs.add(Money.toPaise(minimumAmount));
    }

    final rows = await db.query(
      'transactions',
      where: whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'amount DESC, date DESC',
    );

    final transactions = rows.map(_rowToTransaction).toList();

    // Score transactions by likelihood of being salary
    final scored = transactions.map((tx) {
      int score = 0;
      final rawLower = tx.rawMessage.toLowerCase();
      final merchantLower = (tx.merchant ?? '').toLowerCase();

      // Check for employer keywords
      for (final keyword in employerKeywords) {
        if (rawLower.contains(keyword.toLowerCase()) ||
            merchantLower.contains(keyword.toLowerCase())) {
          score += 10;
        }
      }

      // Large amounts are more likely to be salary
      if (tx.amount > 50000) score += 5;
      if (tx.amount > 100000) score += 5;

      // Already marked as salary
      if (tx.isSalary) score += 20;

      return (tx: tx, score: score);
    }).toList();

    // Sort by score and return top candidates
    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.map((s) => s.tx).toList();
  }

  /// Auto-generate salary cycles from marked salary transactions
  static Future<List<SalaryCycle>> generateSalaryCycles() async {
    final db = await database;

    // Get all salary transactions sorted by date
    final rows = await db.query(
      'transactions',
      where:
          "is_salary = 1 AND type = 'credit' AND is_ignored = 0 AND transfer_group_id IS NULL",
      orderBy: 'date ASC',
    );

    final salaryTransactions = rows.map(_rowToTransaction).toList();

    final cycles = <SalaryCycle>[];

    for (int i = 0; i < salaryTransactions.length; i++) {
      final current = salaryTransactions[i];
      final next = i + 1 < salaryTransactions.length
          ? salaryTransactions[i + 1]
          : null;

      final cycle = SalaryCycle(
        id: 'cycle_${current.id}',
        startDate: current.date,
        endDate: next?.date,
        salaryAmount: current.amount,
        salaryTransactionId: current.id,
        employer: current.merchant,
      );

      cycles.add(cycle);
    }

    await db.transaction((txn) async {
      await txn.delete('salary_cycles');
      for (final cycle in cycles) {
        await txn.insert('salary_cycles', {
          ...cycle.toMap(),
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });

    return await getAllSalaryCycles();
  }

  // ==================== USER SETTINGS ====================

  static Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('user_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  static Future<DateTime?> getLastSmsScanAt() async {
    final value = await getSetting('last_sms_scan_at');
    final milliseconds = int.tryParse(value ?? '');
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  static Future<void> setLastSmsScanAt(DateTime date) =>
      setSetting('last_sms_scan_at', date.millisecondsSinceEpoch.toString());

  // ==================== PROCESSED SMS TRACKING ====================

  /// Mark an SMS as processed (whether it was a transaction or not)
  static Future<void> markSmsAsProcessed(
    String smsId, {
    bool isTransaction = false,
  }) async {
    final db = await database;
    await db.insert('processed_sms', {
      'sms_id': smsId,
      'processed_at': DateTime.now().millisecondsSinceEpoch,
      'is_transaction': isTransaction ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Mark multiple SMS as processed in a batch
  static Future<void> markSmsListAsProcessed(
    List<String> smsIds, {
    bool isTransaction = false,
  }) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final smsId in smsIds) {
      batch.insert('processed_sms', {
        'sms_id': smsId,
        'processed_at': now,
        'is_transaction': isTransaction ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await batch.commit(noResult: true);
  }

  /// Check if an SMS has already been processed
  static Future<bool> isSmsProcessed(String smsId) async {
    final db = await database;
    final result = await db.query(
      'processed_sms',
      where: 'sms_id = ?',
      whereArgs: [smsId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Get all processed SMS IDs (for filtering)
  static Future<Set<String>> getProcessedSmsIds() async {
    final db = await database;
    final rows = await db.query('processed_sms', columns: ['sms_id']);
    return rows.map((r) => r['sms_id'] as String).toSet();
  }

  /// Recheck previously skipped messages while retaining every user decision.
  /// Android SMS is the source for their bodies on the next scan.
  static Future<void> prepareSkippedMessagesForRescan() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawDelete(
        '''
        DELETE FROM processed_sms WHERE sms_id IN
        (SELECT sms_id FROM sms_processing
         WHERE outcome = ? AND
           raw_message IS NOT NULL)
      ''',
        [SmsProcessingOutcome.skipped.name],
      );
    });
  }

  /// Get count of processed messages
  static Future<Map<String, int>> getStats() async {
    final db = await database;

    final txCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM transactions'),
        ) ??
        0;

    final processedCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM processed_sms'),
        ) ??
        0;

    return {'transactions': txCount, 'processed_sms': processedCount};
  }

  // ==================== MAINTENANCE ====================

  /// Clear all cached data
  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('transaction_reviews');
    await db.delete('processed_sms');
    await db.delete('sms_processing');
  }

  /// Delete transactions older than specified days
  static Future<int> deleteOldTransactions(int daysOld) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: daysOld))
        .millisecondsSinceEpoch;

    return await db.delete(
      'transactions',
      where: 'date < ?',
      whereArgs: [cutoff],
    );
  }

  /// Close the database connection
  static Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
      _opening = null;
    }
  }

  // ==================== BUDGET OPERATIONS ====================

  /// Save a budget
  static Future<void> saveBudget(Budget budget) async {
    final db = await database;
    await db.transaction((txn) async {
      final count = await txn.update(
        'budgets',
        budget.toMap(),
        where: 'id = ?',
        whereArgs: [budget.id],
      );
      if (count == 0) await txn.insert('budgets', budget.toMap());
    });
  }

  /// Get all budgets
  static Future<List<Budget>> getAllBudgets() async {
    final db = await database;
    final rows = await db.query('budgets', orderBy: 'created_at DESC');
    return rows.map((r) => Budget.fromMap(r)).toList();
  }

  /// Delete a budget
  static Future<void> deleteBudget(String budgetId) async {
    final db = await database;
    await db.delete('budgets', where: 'id = ?', whereArgs: [budgetId]);
  }

  /// Clear all budgets
  static Future<void> clearBudgets() async {
    final db = await database;
    await db.delete('budgets');
  }

  // ==================== ALERT OPERATIONS ====================

  /// Save an alert
  static Future<void> saveAlert(AppAlert alert) async {
    final db = await database;
    await db.insert(
      'alerts',
      alert.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Save multiple alerts
  static Future<void> saveAlerts(List<AppAlert> alerts) async {
    final db = await database;
    final batch = db.batch();
    for (final alert in alerts) {
      batch.insert(
        'alerts',
        alert.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get unread alerts
  static Future<List<AppAlert>> getUnreadAlerts() async {
    final db = await database;
    final rows = await db.query(
      'alerts',
      where: 'is_read = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => AppAlert.fromMap(r)).toList();
  }

  /// Get all alerts
  static Future<List<AppAlert>> getAllAlerts() async {
    final db = await database;
    final rows = await db.query('alerts', orderBy: 'created_at DESC');
    return rows.map((r) => AppAlert.fromMap(r)).toList();
  }

  /// Mark alert as read
  static Future<void> markAlertRead(String alertId) async {
    final db = await database;
    await db.update(
      'alerts',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [alertId],
    );
  }

  /// Mark all alerts as read
  static Future<void> markAllAlertsRead() async {
    final db = await database;
    await db.update('alerts', {'is_read': 1});
  }

  /// Delete old alerts (older than 30 days)
  static Future<void> cleanOldAlerts() async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await db.delete('alerts', where: 'created_at < ?', whereArgs: [cutoff]);
  }

  // ==================== EMI OPERATIONS ====================

  /// Save detected EMIs
  static Future<void> saveEMIs(List<Map<String, dynamic>> emis) async {
    final db = await database;
    await db.delete('emis'); // Replace all
    final batch = db.batch();
    for (final emi in emis) {
      batch.insert('emis', emi, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ==================== CATEGORY OPERATIONS ====================

  /// Update transaction type (credit/debit)
  static Future<void> updateTransactionType(
    String txId,
    TransactionType type,
  ) async {
    if (type == TransactionType.unknown) {
      throw ArgumentError('Choose debit or credit.');
    }
    await (await database).transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [txId],
      );
      if (rows.isEmpty) throw StateError('Transaction no longer exists.');
      final group = rows.single['transfer_group_id'];
      if (group != null) {
        await txn.update(
          'transactions',
          {
            'transfer_group_id': null,
            'transfer_partner_id': null,
            'is_transfer_source': 0,
            'is_transfer_destination': 0,
          },
          where: 'transfer_group_id = ?',
          whereArgs: [group],
        );
      }
      await txn.update(
        'transactions',
        {
          'type': type.name,
          'is_user_corrected': 1,
          if (type == TransactionType.debit) 'is_salary': 0,
        },
        where: 'id = ?',
        whereArgs: [txId],
      );
    });
  }

  /// Update transaction note
  static Future<void> updateTransactionNote(String txId, String? note) async {
    final db = await database;
    await db.update(
      'transactions',
      {'note': note},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Update transaction tag (Feature 1)
  static Future<void> updateTransactionTag(String txId, String? tag) async {
    final db = await database;
    await db.update(
      'transactions',
      {'tag': tag},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Update transaction ignored status (Feature 2)
  static Future<void> updateTransactionIgnored(
    String txId,
    bool isIgnored,
  ) async {
    final db = await database;
    await db.update(
      'transactions',
      {'is_ignored': isIgnored ? 1 : 0},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Assigns a Category and trip tag to exactly the previewed active rows.
  /// The whole window succeeds or fails together.
  static Future<int> applyCategoryToTransactions({
    required Iterable<String> transactionIds,
    required String categoryId,
    required String tag,
  }) async {
    final ids = transactionIds.toSet().toList(growable: false);
    final cleanTag = tag.trim();
    if (ids.isEmpty) return 0;
    if (cleanTag.isEmpty) {
      throw ArgumentError.value(tag, 'tag', 'Enter a trip tag.');
    }

    final db = await database;
    return db.transaction((txn) async {
      final category = await txn.query(
        'categories',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [categoryId],
        limit: 1,
      );
      if (category.isEmpty) {
        throw StateError('The selected Category no longer exists.');
      }

      final batch = txn.batch();
      for (final id in ids) {
        batch.update(
          'transactions',
          {
            'category_id': categoryId,
            'category_source': 'user',
            'tag': cleanTag,
          },
          where: 'id = ? AND COALESCE(is_ignored, 0) = 0',
          whereArgs: [id],
        );
      }
      final results = await batch.commit();
      return results.fold<int>(0, (count, result) => count + (result as int));
    });
  }

  /// Update transaction payment source
  static Future<void> updateTransactionSource(
    String txId,
    PaymentSource source,
  ) async {
    final db = await database;
    await db.update(
      'transactions',
      {'source': source.name},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Update transaction account assignment
  static Future<void> updateTransactionAccountId(
    String txId,
    String? accountId,
  ) async {
    final db = await database;
    await db.update(
      'transactions',
      {'account_id': accountId},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  static Future<List<AppCategory>> getAllCategories() async {
    final rows = await (await database).query(
      'categories',
      orderBy: 'name COLLATE NOCASE, id',
    );
    return rows.map(AppCategory.fromMap).toList();
  }

  static Future<AppCategory?> getCategoryById(String id) async {
    final rows = await (await database).query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : AppCategory.fromMap(rows.single);
  }

  static Future<void> saveCategory(AppCategory category) async {
    if (category.name.trim().isEmpty) {
      throw ArgumentError('Enter a category name.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final changed = await txn.update(
        'categories',
        category.toMap(),
        where: 'id = ?',
        whereArgs: [category.id],
      );
      if (changed == 0) await txn.insert('categories', category.toMap());
    });
  }

  static Future<void> deleteCategory(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in ['transactions', 'transaction_reviews']) {
        await txn.update(
          table,
          {'category_id': null, 'category_source': null},
          where: 'category_id = ?',
          whereArgs: [id],
        );
      }
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<void> updateTransactionCategory(
    String id,
    String? categoryId,
  ) async {
    await (await database).update(
      'transactions',
      {
        'category_id': categoryId,
        'category_source': 'user',
        'is_user_corrected': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<bool> hasCompletedOnboarding() async {
    final val = await getSetting('has_completed_onboarding');
    return val == 'true';
  }

  /// Mark onboarding as completed
  static Future<void> setOnboardingCompleted(bool completed) async {
    if (completed) {
      await setSetting('has_completed_onboarding', 'true');
    } else {
      final db = await database;
      await db.delete(
        'user_settings',
        where: 'key = ?',
        whereArgs: ['has_completed_onboarding'],
      );
    }
  }

  // ==================== TRACKING SETTINGS HELPERS (Feature 4) ====================

  /// Get the tracking start date (null = no restriction)
  static Future<DateTime?> getTrackFromDate() async {
    final val = await getSetting('track_from_date');
    if (val == null) return null;
    final ms = int.tryParse(val);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Save the tracking start date
  static Future<void> setTrackFromDate(DateTime? date) async {
    if (date == null) {
      final db = await database;
      await db.delete(
        'user_settings',
        where: 'key = ?',
        whereArgs: ['track_from_date'],
      );
    } else {
      await setSetting(
        'track_from_date',
        date.millisecondsSinceEpoch.toString(),
      );
    }
  }

  /// Get the tracking start transaction ID (null = no restriction)
  static Future<String?> getTrackFromTransactionId() async {
    return getSetting('track_from_transaction_id');
  }

  /// Save the tracking start transaction ID
  static Future<void> setTrackFromTransactionId(String? txId) async {
    if (txId == null) {
      final db = await database;
      await db.delete(
        'user_settings',
        where: 'key = ?',
        whereArgs: ['track_from_transaction_id'],
      );
    } else {
      await setSetting('track_from_transaction_id', txId);
    }
  }

  /// Get the salary cycle day (e.g. 25 means cycle runs from 25th to 24th next month)
  static Future<int?> getSalaryCycleDay() async {
    final val = await getSetting('salary_cycle_day');
    if (val == null) return null;
    return int.tryParse(val);
  }

  /// Set the salary cycle day (1-31), or null to clear
  static Future<void> setSalaryCycleDay(int? day) async {
    if (day == null) {
      final db = await database;
      await db.delete(
        'user_settings',
        where: 'key = ?',
        whereArgs: ['salary_cycle_day'],
      );
    } else {
      if (day < 1 || day > 31) throw ArgumentError('Salary day must be 1-31.');
      await setSetting('salary_cycle_day', day.toString());
    }
  }

  /// Get all transactions at or after the given date (used with tracking settings)
  static Future<List<Transaction>> getTransactionsSince(DateTime from) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'date >= ?',
      whereArgs: [from.millisecondsSinceEpoch],
      orderBy: 'date DESC',
    );
    return rows.map(_rowToTransaction).toList();
  }

  /// Batch update categories for uncategorized transactions
}
