// lib/services/local_storage_service.dart

import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/transaction.dart';

/// Local SQLite database for caching parsed transactions
/// Avoids re-parsing already processed SMS messages
class LocalStorageService {
  static Database? _db;
  static const String _dbName = 'payment_tracker.db';
  static const int _dbVersion = 1;

  /// Initialize the database
  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Table for cached transactions
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        sms_id TEXT UNIQUE,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        source TEXT NOT NULL,
        sender TEXT,
        merchant TEXT,
        account_last4 TEXT,
        date INTEGER NOT NULL,
        raw_message TEXT,
        reference_id TEXT,
        balance REAL,
        parsed_by TEXT DEFAULT 'rule',
        created_at INTEGER NOT NULL
      )
    ''');

    // Table to track processed SMS IDs (even those that weren't transactions)
    await db.execute('''
      CREATE TABLE processed_sms (
        sms_id TEXT PRIMARY KEY,
        processed_at INTEGER NOT NULL,
        is_transaction INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Index for faster lookups
    await db.execute('CREATE INDEX idx_transactions_date ON transactions(date DESC)');
    await db.execute('CREATE INDEX idx_transactions_type ON transactions(type)');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future schema migrations here
  }

  // ==================== TRANSACTION OPERATIONS ====================

  /// Save a parsed transaction to local storage
  static Future<void> saveTransaction(Transaction tx, {String parsedBy = 'rule'}) async {
    final db = await database;
    
    await db.insert(
      'transactions',
      {
        'id': tx.id,
        'sms_id': tx.id, // Using SMS ID as the unique identifier
        'amount': tx.amount,
        'type': tx.type.name,
        'source': tx.source.name,
        'sender': tx.sender,
        'merchant': tx.merchant,
        'account_last4': tx.accountLast4,
        'date': tx.date.millisecondsSinceEpoch,
        'raw_message': tx.rawMessage,
        'reference_id': tx.referenceId,
        'balance': tx.balance,
        'parsed_by': parsedBy,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Save multiple transactions in a batch
  static Future<void> saveTransactions(List<Transaction> transactions, {String parsedBy = 'rule'}) async {
    final db = await database;
    final batch = db.batch();

    for (final tx in transactions) {
      batch.insert(
        'transactions',
        {
          'id': tx.id,
          'sms_id': tx.id,
          'amount': tx.amount,
          'type': tx.type.name,
          'source': tx.source.name,
          'sender': tx.sender,
          'merchant': tx.merchant,
          'account_last4': tx.accountLast4,
          'date': tx.date.millisecondsSinceEpoch,
          'raw_message': tx.rawMessage,
          'reference_id': tx.referenceId,
          'balance': tx.balance,
          'parsed_by': parsedBy,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get all cached transactions
  static Future<List<Transaction>> getAllTransactions() async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      orderBy: 'date DESC',
    );

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
      where: 'date >= ? AND date <= ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'date DESC',
    );

    return rows.map(_rowToTransaction).toList();
  }

  /// Convert database row to Transaction object
  static Transaction _rowToTransaction(Map<String, dynamic> row) {
    return Transaction(
      id: row['id'] as String,
      amount: row['amount'] as double,
      type: TransactionType.values.firstWhere(
        (t) => t.name == row['type'],
        orElse: () => TransactionType.unknown,
      ),
      source: PaymentSource.values.firstWhere(
        (s) => s.name == row['source'],
        orElse: () => PaymentSource.bank,
      ),
      sender: (row['sender'] as String?) ?? 'Unknown',
      merchant: row['merchant'] as String?,
      accountLast4: row['account_last4'] as String?,
      date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
      rawMessage: (row['raw_message'] as String?) ?? '',
      referenceId: row['reference_id'] as String?,
      balance: row['balance'] as double?,
    );
  }

  // ==================== PROCESSED SMS TRACKING ====================

  /// Mark an SMS as processed (whether it was a transaction or not)
  static Future<void> markSmsAsProcessed(String smsId, {bool isTransaction = false}) async {
    final db = await database;
    await db.insert(
      'processed_sms',
      {
        'sms_id': smsId,
        'processed_at': DateTime.now().millisecondsSinceEpoch,
        'is_transaction': isTransaction ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
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
      batch.insert(
        'processed_sms',
        {
          'sms_id': smsId,
          'processed_at': now,
          'is_transaction': isTransaction ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
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

  /// Get count of processed messages
  static Future<Map<String, int>> getStats() async {
    final db = await database;
    
    final txCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM transactions'),
    ) ?? 0;
    
    final processedCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM processed_sms'),
    ) ?? 0;
    
    final aiParsedCount = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM transactions WHERE parsed_by = 'ai'"),
    ) ?? 0;

    return {
      'transactions': txCount,
      'processed_sms': processedCount,
      'ai_parsed': aiParsedCount,
    };
  }

  // ==================== MAINTENANCE ====================

  /// Clear all cached data
  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('processed_sms');
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
    }
  }
}
