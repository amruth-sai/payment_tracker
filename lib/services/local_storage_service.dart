// lib/services/local_storage_service.dart

import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../models/sender_mapping.dart';
import '../models/salary_cycle.dart';
import '../models/budget.dart';
import '../models/app_alert.dart';
import '../models/custom_category.dart';

/// Local SQLite database for caching parsed transactions
/// Avoids re-parsing already processed SMS messages
class LocalStorageService {
  static Database? _db;
  static const String _dbName = 'payment_tracker.db';
  static const int _dbVersion = 5; // v5: sender_mappings table for dynamic sender assignments

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
        account_id TEXT,
        is_user_corrected INTEGER DEFAULT 0,
        is_salary INTEGER DEFAULT 0,
        category TEXT,
        note TEXT,
        tag TEXT,
        is_ignored INTEGER DEFAULT 0,
        custom_category_id TEXT,
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

    // Table for user accounts (bank accounts, credit cards)
    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        last4_digits TEXT,
        bank_name TEXT,
        card_network TEXT,
        is_manually_added INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // Table for salary cycles
    await db.execute('''
      CREATE TABLE salary_cycles (
        id TEXT PRIMARY KEY,
        start_date INTEGER NOT NULL,
        end_date INTEGER,
        salary_amount REAL NOT NULL,
        salary_transaction_id TEXT NOT NULL,
        employer TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    // Table for user preferences
    await db.execute('''
      CREATE TABLE user_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Table for budgets
    await db.execute('''
      CREATE TABLE budgets (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        monthly_limit REAL NOT NULL,
        is_ai_suggested INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // Table for alerts
    await db.execute('''
      CREATE TABLE alerts (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        severity TEXT NOT NULL,
        transaction_id TEXT,
        is_read INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // Table for detected EMIs
    await db.execute('''
      CREATE TABLE emis (
        id TEXT PRIMARY KEY,
        merchant TEXT NOT NULL,
        amount REAL NOT NULL,
        day_of_month INTEGER NOT NULL,
        occurrences TEXT,
        total_detected INTEGER NOT NULL,
        estimated_total INTEGER,
        is_active INTEGER DEFAULT 1
      )
    ''');

    // Table for user-created custom categories (Feature 3)
    await db.execute('''
      CREATE TABLE custom_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL DEFAULT '🏷️',
        color_value INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // Table for sender mappings (dynamic parent-child relationships)
    await db.execute('''
      CREATE TABLE sender_mappings (
        id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_user_assigned INTEGER DEFAULT 0,
        FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
      )
    ''');

    // Indexes for faster lookups
    await db.execute(
        'CREATE INDEX idx_transactions_date ON transactions(date DESC)');
    await db
        .execute('CREATE INDEX idx_transactions_type ON transactions(type)');
    await db.execute(
        'CREATE INDEX idx_transactions_account ON transactions(account_id)');
    await db.execute(
        'CREATE INDEX idx_transactions_salary ON transactions(is_salary)');
    await db.execute(
        'CREATE INDEX idx_transactions_category ON transactions(category)');
    await db.execute(
        'CREATE INDEX idx_alerts_read ON alerts(is_read)');
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns to transactions table
      await db.execute('ALTER TABLE transactions ADD COLUMN account_id TEXT');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN is_user_corrected INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN is_salary INTEGER DEFAULT 0');

      // Create new tables
      await db.execute('''
        CREATE TABLE IF NOT EXISTS accounts (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          last4_digits TEXT,
          bank_name TEXT,
          card_network TEXT,
          is_manually_added INTEGER DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS salary_cycles (
          id TEXT PRIMARY KEY,
          start_date INTEGER NOT NULL,
          end_date INTEGER,
          salary_amount REAL NOT NULL,
          salary_transaction_id TEXT NOT NULL,
          employer TEXT,
          created_at INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      // Create new indexes
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_account ON transactions(account_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_salary ON transactions(is_salary)');
    }
    if (oldVersion < 3) {
      // Add category and note columns
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN category TEXT');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN note TEXT');

      // Create budgets table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS budgets (
          id TEXT PRIMARY KEY,
          category TEXT NOT NULL,
          monthly_limit REAL NOT NULL,
          is_ai_suggested INTEGER DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');

      // Create alerts table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS alerts (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          title TEXT NOT NULL,
          message TEXT NOT NULL,
          severity TEXT NOT NULL,
          transaction_id TEXT,
          is_read INTEGER DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');

      // Create EMIs table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS emis (
          id TEXT PRIMARY KEY,
          merchant TEXT NOT NULL,
          amount REAL NOT NULL,
          day_of_month INTEGER NOT NULL,
          occurrences TEXT,
          total_detected INTEGER NOT NULL,
          estimated_total INTEGER,
          is_active INTEGER DEFAULT 1
        )
      ''');

      // New indexes
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_alerts_read ON alerts(is_read)');
    }
    if (oldVersion < 4) {
      // Add tag, is_ignored, custom_category_id columns to transactions
      await db.execute('ALTER TABLE transactions ADD COLUMN tag TEXT');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN is_ignored INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN custom_category_id TEXT');

      // Create custom_categories table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS custom_categories (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          emoji TEXT NOT NULL DEFAULT '🏷️',
          color_value INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');

      // Index on is_ignored for fast filtering
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_ignored ON transactions(is_ignored)');
    }
    if (oldVersion < 5) {
      // Create sender_mappings table for dynamic sender assignments
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sender_mappings (
          id TEXT PRIMARY KEY,
          sender_id TEXT NOT NULL,
          account_id TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          is_user_assigned INTEGER DEFAULT 0,
          FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
        )
      ''');

      // Indexes for sender mappings
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sender_mappings_sender ON sender_mappings(sender_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sender_mappings_account ON sender_mappings(account_id)');
    }
  }

  // ==================== TRANSACTION OPERATIONS ====================

  /// Save a parsed transaction to local storage
  static Future<void> saveTransaction(Transaction tx,
      {String parsedBy = 'rule'}) async {
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
        'account_id': tx.accountId,
        'is_user_corrected': tx.isUserCorrected ? 1 : 0,
        'is_salary': tx.isSalary ? 1 : 0,
        'category': tx.category?.name,
        'note': tx.note,
        'tag': tx.tag,
        'is_ignored': tx.isIgnored ? 1 : 0,
        'custom_category_id': tx.customCategoryId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Save multiple transactions in a batch
  static Future<void> saveTransactions(List<Transaction> transactions,
      {String parsedBy = 'rule'}) async {
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
          'account_id': tx.accountId,
          'is_user_corrected': tx.isUserCorrected ? 1 : 0,
          'is_salary': tx.isSalary ? 1 : 0,
          'category': tx.category?.name,
          'note': tx.note,
          'tag': tx.tag,
          'is_ignored': tx.isIgnored ? 1 : 0,
          'custom_category_id': tx.customCategoryId,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Update a transaction (for user corrections)
  static Future<void> updateTransaction(Transaction tx) async {
    final db = await database;
    await db.update(
      'transactions',
      {
        'type': tx.type.name,
        'source': tx.source.name,
        'merchant': tx.merchant,
        'account_id': tx.accountId,
        'is_user_corrected': 1,
        'is_salary': tx.isSalary ? 1 : 0,
        'category': tx.category?.name,
        'note': tx.note,
        'tag': tx.tag,
        'is_ignored': tx.isIgnored ? 1 : 0,
        'custom_category_id': tx.customCategoryId,
      },
      where: 'id = ?',
      whereArgs: [tx.id],
    );
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
      accountId: row['account_id'] as String?,
      isUserCorrected: (row['is_user_corrected'] as int?) == 1,
      isSalary: (row['is_salary'] as int?) == 1,
      category: row['category'] != null
          ? TransactionCategory.values.firstWhere(
              (c) => c.name == row['category'],
              orElse: () => TransactionCategory.uncategorized,
            )
          : null,
      note: row['note'] as String?,
      tag: row['tag'] as String?,
      isIgnored: (row['is_ignored'] as int?) == 1,
      customCategoryId: row['custom_category_id'] as String?,
    );
  }

  // ==================== ACCOUNT OPERATIONS ====================

  /// Save an account
  static Future<void> saveAccount(Account account) async {
    final db = await database;
    await db.insert(
      'accounts',
      account.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all accounts
  static Future<List<Account>> getAllAccounts() async {
    final db = await database;
    final rows = await db.query('accounts', orderBy: 'created_at DESC');
    return rows.map((r) => Account.fromMap(r)).toList();
  }

  /// Delete an account
  static Future<void> deleteAccount(String accountId) async {
    final db = await database;
    await db.delete('accounts', where: 'id = ?', whereArgs: [accountId]);
    // Also unlink from transactions
    await db.update('transactions', {'account_id': null},
        where: 'account_id = ?', whereArgs: [accountId]);
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
    final existingLast4 = existingAccounts.map((a) => a.last4Digits).toSet();

    final newAccounts = <Account>[];
    for (final row in rows) {
      final last4 = row['account_last4'] as String?;
      if (last4 != null && !existingLast4.contains(last4)) {
        final sender = (row['sender'] as String?) ?? 'Unknown';
        final source = row['source'] as String?;

        final type =
            source == 'card' ? AccountType.creditCard : AccountType.bankAccount;
        final name = _extractBankName(sender);

        newAccounts.add(Account(
          id: 'auto_${last4}_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          type: type,
          last4Digits: last4,
          bankName: name,
          isManuallyAdded: false,
        ));
        existingLast4.add(last4);
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
  }

  /// Get transactions by account
  static Future<List<Transaction>> getTransactionsByAccount(
      String accountId) async {
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
        COALESCE(account_last4, sender) as account_key,
        type,
        SUM(amount) as total
      FROM transactions
      GROUP BY account_key, type
    ''');

    final result = <String, Map<String, double>>{};
    for (final row in rows) {
      final key = row['account_key'] as String;
      final type = row['type'] as String;
      final total = row['total'] as double;

      result.putIfAbsent(key, () => {'credit': 0.0, 'debit': 0.0});
      result[key]![type] = total;
    }

    return result;
  }

  // ==================== SALARY CYCLE OPERATIONS ====================

  /// Save a salary cycle
  static Future<void> saveSalaryCycle(SalaryCycle cycle) async {
    final db = await database;
    await db.insert(
      'salary_cycles',
      {
        ...cycle.toMap(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
      final transactions =
          await getTransactionsByDateRange(cycle.startDate, endDate);

      cycles.add(cycle.copyWith(transactions: transactions));
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
    List<String> employerKeywords = const ['HCA', 'SALARY', 'HCA GLOBAL'],
    double? minimumAmount,
  }) async {
    final db = await database;

    String whereClause = "type = 'credit'";
    final whereArgs = <dynamic>[];

    if (minimumAmount != null) {
      whereClause += ' AND amount >= ?';
      whereArgs.add(minimumAmount);
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
      where: 'is_salary = 1',
      orderBy: 'date ASC',
    );

    final salaryTransactions = rows.map(_rowToTransaction).toList();
    if (salaryTransactions.isEmpty) return [];

    final cycles = <SalaryCycle>[];

    for (int i = 0; i < salaryTransactions.length; i++) {
      final current = salaryTransactions[i];
      final next =
          i + 1 < salaryTransactions.length ? salaryTransactions[i + 1] : null;

      final cycle = SalaryCycle(
        id: 'cycle_${current.date.millisecondsSinceEpoch}',
        startDate: current.date,
        endDate: next?.date.subtract(const Duration(days: 1)),
        salaryAmount: current.amount,
        salaryTransactionId: current.id,
        employer: current.merchant,
      );

      cycles.add(cycle);
    }

    // Save cycles
    for (final cycle in cycles) {
      await saveSalaryCycle(cycle);
    }

    return await getAllSalaryCycles();
  }

  // ==================== USER SETTINGS ====================

  static Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'user_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  // ==================== PROCESSED SMS TRACKING ====================

  /// Mark an SMS as processed (whether it was a transaction or not)
  static Future<void> markSmsAsProcessed(String smsId,
      {bool isTransaction = false}) async {
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
        ) ??
        0;

    final processedCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM processed_sms'),
        ) ??
        0;

    final aiParsedCount = Sqflite.firstIntValue(
          await db.rawQuery(
              "SELECT COUNT(*) FROM transactions WHERE parsed_by = 'ai'"),
        ) ??
        0;

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
    final cutoff =
        DateTime.now().subtract(Duration(days: daysOld)).millisecondsSinceEpoch;

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

  // ==================== BUDGET OPERATIONS ====================

  /// Save a budget
  static Future<void> saveBudget(Budget budget) async {
    final db = await database;
    await db.insert(
      'budgets',
      budget.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
      batch.insert('alerts', alert.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
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

  /// Update transaction category
  static Future<void> updateTransactionCategory(
      String txId, TransactionCategory category) async {
    final db = await database;
    await db.update(
      'transactions',
      {'category': category.name},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Update transaction type (credit/debit)
  static Future<void> updateTransactionType(
      String txId, TransactionType type) async {
    final db = await database;
    await db.update(
      'transactions',
      {'type': type.name, 'is_user_corrected': 1},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Update transaction note
  static Future<void> updateTransactionNote(
      String txId, String? note) async {
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
      String txId, bool isIgnored) async {
    final db = await database;
    await db.update(
      'transactions',
      {'is_ignored': isIgnored ? 1 : 0},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Update transaction custom category (Feature 3)
  static Future<void> updateTransactionCustomCategory(
      String txId, String? customCategoryId) async {
    final db = await database;
    await db.update(
      'transactions',
      {'custom_category_id': customCategoryId},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  // ==================== CUSTOM CATEGORY OPERATIONS (Feature 3) ====================

  /// Get all user-created custom categories
  static Future<List<CustomCategory>> getAllCustomCategories() async {
    final db = await database;
    final rows =
        await db.query('custom_categories', orderBy: 'created_at ASC');
    return rows.map((r) => CustomCategory.fromMap(r)).toList();
  }

  /// Save (insert or replace) a custom category
  static Future<void> saveCustomCategory(CustomCategory cat) async {
    final db = await database;
    await db.insert(
      'custom_categories',
      cat.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete a custom category and unlink from transactions
  static Future<void> deleteCustomCategory(String catId) async {
    final db = await database;
    await db.delete('custom_categories', where: 'id = ?', whereArgs: [catId]);
    await db.update(
      'transactions',
      {'custom_category_id': null},
      where: 'custom_category_id = ?',
      whereArgs: [catId],
    );
  }

  // ==================== ONBOARDING HELPERS ====================

  /// Check if the user has completed the tracking onboarding
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
      await db.delete('user_settings',
          where: 'key = ?', whereArgs: ['has_completed_onboarding']);
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
      await db.delete('user_settings',
          where: 'key = ?', whereArgs: ['track_from_date']);
    } else {
      await setSetting(
          'track_from_date', date.millisecondsSinceEpoch.toString());
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
      await db.delete('user_settings',
          where: 'key = ?', whereArgs: ['track_from_transaction_id']);
    } else {
      await setSetting('track_from_transaction_id', txId);
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
  static Future<void> batchUpdateCategories(
      Map<String, TransactionCategory> updates) async {
    final db = await database;
    final batch = db.batch();
    for (final entry in updates.entries) {
      batch.update(
        'transactions',
        {'category': entry.value.name},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
    await batch.commit(noResult: true);
  }
}
