// lib/services/local_storage_service.dart

import 'dart:convert';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../models/sender_mapping.dart';
import '../models/salary_cycle.dart';
import '../models/budget.dart';
import '../models/app_alert.dart';
import '../models/custom_category.dart';
import '../models/standard_category.dart';
import '../models/category_preferences.dart';
import '../constants/transfer_constants.dart';

/// Local SQLite database for caching parsed transactions
/// Avoids re-parsing already processed SMS messages
class LocalStorageService {
  static Database? _db;
  static const String _dbName = 'payment_tracker.db';
  static const int _dbVersion = 8; // v8: refreshed standard category catalog

  static String? _legacyCategoryNameForStandardCategoryId(
      String? standardCategoryId) {
    return TransactionCategory.fromStandardCategoryId(standardCategoryId)?.name;
  }

  static Map<String, String> get _legacyEnumToStandardCategoryId => {
        'foodDining': TransactionCategory.foodDining.standardCategoryId,
        'travelTransport':
            TransactionCategory.travelTransport.standardCategoryId,
        'shopping': TransactionCategory.shopping.standardCategoryId,
        'rentHousing': TransactionCategory.rentHousing.standardCategoryId,
        'emiLoans': TransactionCategory.emiLoans.standardCategoryId,
        'entertainment': TransactionCategory.entertainment.standardCategoryId,
        'billsUtilities': TransactionCategory.billsUtilities.standardCategoryId,
        'healthMedical': TransactionCategory.healthMedical.standardCategoryId,
        'education': TransactionCategory.education.standardCategoryId,
        'salaryIncome': TransactionCategory.salaryIncome.standardCategoryId,
        'transfer': TransactionCategory.transfer.standardCategoryId,
        'cashback': TransactionCategory.cashback.standardCategoryId,
        'investment': TransactionCategory.investment.standardCategoryId,
        'other': TransactionCategory.other.standardCategoryId,
        'uncategorized': TransactionCategory.uncategorized.standardCategoryId,
      };

  static Future<void> _seedDefaultStandardCategories(Database db) async {
    for (final category in StandardCategory.defaultCategories) {
      await db.insert(
        'standard_categories',
        category.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  static Future<void> _migrateLegacyStandardCategoryIds(Database db) async {
    for (final entry in StandardCategory.legacyIdRemap.entries) {
      await db.update(
        'transactions',
        {'standard_category_id': entry.value},
        where: 'standard_category_id = ?',
        whereArgs: [entry.key],
      );
    }

    final desiredIds =
        StandardCategory.defaultCategories.map((c) => c.id).toSet().toList();
    final obsoleteDefaultIds = StandardCategory.legacyIdRemap.keys.toList();

    for (final obsoleteId in obsoleteDefaultIds) {
      await db.delete(
        'standard_categories',
        where: 'id = ? AND is_default = 1',
        whereArgs: [obsoleteId],
      );
    }

    await db.delete(
      'standard_categories',
      where:
          'is_default = 1 AND id NOT IN (${List.filled(desiredIds.length, '?').join(', ')})',
      whereArgs: desiredIds,
    );
  }

  static Future<void> _migrateCategoryPreferences(Database db) async {
    final rows = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['category_preferences'],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final rawValue = rows.first['value'] as String?;
    if (rawValue == null || rawValue.isEmpty) return;

    try {
      final map = json.decode(rawValue) as Map<String, dynamic>;
      final savedIds =
          (map['enabled_category_ids'] as List<dynamic>? ?? []).cast<String>();
      final normalizedIds = savedIds
          .map((id) => StandardCategory.legacyIdRemap[id] ?? id)
          .toSet();
      normalizedIds.addAll(StandardCategory.newlyAddedDefaultIds);

      await db.update(
        'user_settings',
        {
          'value': json.encode({
            'enabled_category_ids': normalizedIds.toList(),
          }),
        },
        where: 'key = ?',
        whereArgs: ['category_preferences'],
      );
    } catch (_) {
      // Ignore malformed legacy settings and fall back to runtime defaults.
    }
  }

  static Future<void> _syncAirtelBankTransactions(Database db) async {
    const standardCategoryId = 'daily_transactions';
    const whereClause = '''
      LOWER(COALESCE(sender, '')) LIKE ? OR
      LOWER(COALESCE(merchant, '')) LIKE ? OR
      LOWER(COALESCE(raw_message, '')) LIKE ? OR
      LOWER(COALESCE(sender, '')) LIKE ? OR
      LOWER(COALESCE(raw_message, '')) LIKE ? OR
      LOWER(COALESCE(sender, '')) LIKE ? OR
      LOWER(COALESCE(raw_message, '')) LIKE ? OR
      LOWER(COALESCE(sender, '')) LIKE ? OR
      LOWER(COALESCE(raw_message, '')) LIKE ?
    ''';

    const whereArgs = [
      '%airtel payments bank%',
      '%airtel payments bank%',
      '%airtel payments bank%',
      '%atbank%',
      '%atbank%',
      '%airbnk%',
      '%airbnk%',
      '%airbks%',
      '%airbks%',
    ];

    await db.update(
      'transactions',
      {
        'standard_category_id': standardCategoryId,
        'category': null,
      },
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  static Future<void> _syncStandardCategoryCatalog(Database db) async {
    await _migrateLegacyStandardCategoryIds(db);
    await _seedDefaultStandardCategories(db);
    await _migrateCategoryPreferences(db);
    await _syncAirtelBankTransactions(db);
  }

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
      onOpen: (db) async {
        await _syncStandardCategoryCatalog(db);
      },
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
        standard_category_id TEXT,
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

    // Table for standard categories (dynamic standard categories)
    await db.execute('''
      CREATE TABLE standard_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        emoji TEXT NOT NULL DEFAULT '🏷️',
        color_value INTEGER NOT NULL,
        is_default INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // Populate default standard categories
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultCategories = [
      [
        'food_dining',
        'foodDining',
        'Food & Dining',
        '🍕',
        4294924800,
        0
      ], // Colors.orange.value
      [
        'travel_transport',
        'travelTransport',
        'Travel & Transport',
        '🚗',
        4278190335,
        1
      ], // Colors.blue.value
      [
        'shopping',
        'shopping',
        'Shopping',
        '🛍️',
        4287245282,
        2
      ], // Colors.purple.value
      [
        'rent_housing',
        'rentHousing',
        'Rent & Housing',
        '🏠',
        4280391411,
        3
      ], // Colors.brown.value
      [
        'emi_loans',
        'emiLoans',
        'EMI & Loans',
        '💳',
        4294198070,
        4
      ], // Colors.red.value
      [
        'entertainment',
        'entertainment',
        'Entertainment',
        '🎬',
        4291467747,
        5
      ], // Colors.pink.value
      [
        'bills_utilities',
        'billsUtilities',
        'Bills & Utilities',
        '💡',
        4294961664,
        6
      ], // Colors.yellow.value
      [
        'health_medical',
        'healthMedical',
        'Health & Medical',
        '🏥',
        4283215696,
        7
      ], // Colors.green.value
      [
        'education',
        'education',
        'Education',
        '📚',
        4281367748,
        8
      ], // Colors.indigo.value
      [
        'salary_income',
        'salaryIncome',
        'Salary & Income',
        '💰',
        4283002648,
        9
      ], // Colors.green.shade700.value
      [
        'transfer',
        'transfer',
        'Transfer',
        '🔄',
        4286611584,
        10
      ], // Colors.grey.value
      [
        'cashback',
        'cashback',
        'Cashback',
        '🎁',
        4278238420,
        11
      ], // Colors.teal.value
      [
        'investment',
        'investment',
        'Investment',
        '📈',
        4284513675,
        12
      ], // Colors.deepPurple.value
      [
        'other',
        'other',
        'Other',
        '📌',
        4285755919,
        13
      ], // Colors.blueGrey.value
      [
        'uncategorized',
        'uncategorized',
        'Uncategorized',
        '❓',
        4286611584,
        14
      ], // Colors.grey.shade500.value
    ];

    for (final category in defaultCategories) {
      await db.insert('standard_categories', {
        'id': category[0],
        'name': category[1],
        'display_name': category[2],
        'emoji': category[3],
        'color_value': category[4],
        'is_default': 1,
        'is_active': 1,
        'sort_order': category[5],
        'created_at': now,
      });
    }

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
        'CREATE INDEX idx_transactions_standard_category ON transactions(standard_category_id)');
    await db.execute(
        'CREATE INDEX idx_standard_categories_active ON standard_categories(is_active)');
    await db.execute('CREATE INDEX idx_alerts_read ON alerts(is_read)');
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
      await db.execute('ALTER TABLE transactions ADD COLUMN category TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN note TEXT');

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
    if (oldVersion < 6) {
      // Create standard_categories table for dynamic standard categories
      await db.execute('''
        CREATE TABLE IF NOT EXISTS standard_categories (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          display_name TEXT NOT NULL,
          emoji TEXT NOT NULL DEFAULT '🏷️',
          color_value INTEGER NOT NULL,
          is_default INTEGER DEFAULT 0,
          is_active INTEGER DEFAULT 1,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');

      // Add standard_category_id column to transactions table
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN standard_category_id TEXT');

      // Populate with default standard categories
      final now = DateTime.now().millisecondsSinceEpoch;
      final defaultCategories = [
        [
          'food_dining',
          'foodDining',
          'Food & Dining',
          '🍕',
          4294924800,
          0
        ], // Colors.orange.value
        [
          'travel_transport',
          'travelTransport',
          'Travel & Transport',
          '🚗',
          4278190335,
          1
        ], // Colors.blue.value
        [
          'shopping',
          'shopping',
          'Shopping',
          '🛍️',
          4287245282,
          2
        ], // Colors.purple.value
        [
          'rent_housing',
          'rentHousing',
          'Rent & Housing',
          '🏠',
          4280391411,
          3
        ], // Colors.brown.value
        [
          'emi_loans',
          'emiLoans',
          'EMI & Loans',
          '💳',
          4294198070,
          4
        ], // Colors.red.value
        [
          'entertainment',
          'entertainment',
          'Entertainment',
          '🎬',
          4291467747,
          5
        ], // Colors.pink.value
        [
          'bills_utilities',
          'billsUtilities',
          'Bills & Utilities',
          '💡',
          4294961664,
          6
        ], // Colors.yellow.value
        [
          'health_medical',
          'healthMedical',
          'Health & Medical',
          '🏥',
          4283215696,
          7
        ], // Colors.green.value
        [
          'education',
          'education',
          'Education',
          '📚',
          4281367748,
          8
        ], // Colors.indigo.value
        [
          'salary_income',
          'salaryIncome',
          'Salary & Income',
          '💰',
          4283002648,
          9
        ], // Colors.green.shade700.value
        [
          'transfer',
          'transfer',
          'Transfer',
          '🔄',
          4286611584,
          10
        ], // Colors.grey.value
        [
          'cashback',
          'cashback',
          'Cashback',
          '🎁',
          4278238420,
          11
        ], // Colors.teal.value
        [
          'investment',
          'investment',
          'Investment',
          '📈',
          4284513675,
          12
        ], // Colors.deepPurple.value
        [
          'other',
          'other',
          'Other',
          '📌',
          4285755919,
          13
        ], // Colors.blueGrey.value
        [
          'uncategorized',
          'uncategorized',
          'Uncategorized',
          '❓',
          4286611584,
          14
        ], // Colors.grey.shade500.value
      ];

      for (final category in defaultCategories) {
        await db.insert('standard_categories', {
          'id': category[0],
          'name': category[1],
          'display_name': category[2],
          'emoji': category[3],
          'color_value': category[4],
          'is_default': 1,
          'is_active': 1,
          'sort_order': category[5],
          'created_at': now,
        });
      }

      // Migrate existing category enum values to standard_category_id references
      for (final entry in _legacyEnumToStandardCategoryId.entries) {
        await db.update(
          'transactions',
          {'standard_category_id': entry.value},
          where: 'category = ?',
          whereArgs: [entry.key],
        );
      }

      // Index on standard_category_id for fast filtering
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_standard_category ON transactions(standard_category_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_standard_categories_active ON standard_categories(is_active)');
    }

    if (oldVersion < 7) {
      // Add transfer linking columns to transactions table
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN transfer_group_id TEXT');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN transfer_partner_id TEXT');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN is_transfer_source INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN is_transfer_destination INTEGER DEFAULT 0');

      // Add indexes for transfer queries
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_transfer_group ON transactions(transfer_group_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_transfer_partner ON transactions(transfer_partner_id)');
    }

    if (oldVersion < 8) {
      await _syncStandardCategoryCatalog(db);
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
        'category': tx.effectiveLegacyCategory?.name,
        'standard_category_id': tx.effectiveStandardCategoryId,
        'note': tx.note,
        'tag': tx.tag,
        'is_ignored': tx.isIgnored ? 1 : 0,
        'custom_category_id': tx.customCategoryId,
        TransferConstants.transferGroupIdField: tx.transferGroupId,
        TransferConstants.transferPartnerIdField: tx.transferPartnerId,
        TransferConstants.isTransferSourceField: tx.isTransferSource ? 1 : 0,
        TransferConstants.isTransferDestinationField:
            tx.isTransferDestination ? 1 : 0,
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
          'category': tx.effectiveLegacyCategory?.name,
          'standard_category_id': tx.effectiveStandardCategoryId,
          'note': tx.note,
          'tag': tx.tag,
          'is_ignored': tx.isIgnored ? 1 : 0,
          'custom_category_id': tx.customCategoryId,
          'transfer_group_id': tx.transferGroupId,
          'transfer_partner_id': tx.transferPartnerId,
          'is_transfer_source': tx.isTransferSource ? 1 : 0,
          'is_transfer_destination': tx.isTransferDestination ? 1 : 0,
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
        'category': tx.effectiveLegacyCategory?.name,
        'standard_category_id': tx.effectiveStandardCategoryId,
        'note': tx.note,
        'tag': tx.tag,
        'is_ignored': tx.isIgnored ? 1 : 0,
        'custom_category_id': tx.customCategoryId,
        TransferConstants.transferGroupIdField: tx.transferGroupId,
        TransferConstants.transferPartnerIdField: tx.transferPartnerId,
        TransferConstants.isTransferSourceField: tx.isTransferSource ? 1 : 0,
        TransferConstants.isTransferDestinationField:
            tx.isTransferDestination ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [tx.id],
    );
  }

  /// Update multiple transactions atomically (for transfer operations)
  static Future<void> updateTransactionsAtomic(
      List<Transaction> transactions) async {
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
            'category': tx.effectiveLegacyCategory?.name,
            'standard_category_id': tx.effectiveStandardCategoryId,
            'note': tx.note,
            'tag': tx.tag,
            'is_ignored': tx.isIgnored ? 1 : 0,
            'custom_category_id': tx.customCategoryId,
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
          : TransactionCategory.fromStandardCategoryId(
              row['standard_category_id'] as String?,
            ),
      standardCategoryId: row['standard_category_id'] as String?,
      note: row['note'] as String?,
      tag: row['tag'] as String?,
      isIgnored: (row['is_ignored'] as int?) == 1,
      customCategoryId: row['custom_category_id'] as String?,
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
      {
        'category': category.name,
        'standard_category_id': category.standardCategoryId,
      },
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

  /// Update transaction payment source
  static Future<void> updateTransactionSource(
      String txId, PaymentSource source) async {
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
      String txId, String? accountId) async {
    final db = await database;
    await db.update(
      'transactions',
      {'account_id': accountId},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  // ==================== CUSTOM CATEGORY OPERATIONS (Feature 3) ====================

  /// Get all user-created custom categories
  static Future<List<CustomCategory>> getAllCustomCategories() async {
    final db = await database;
    final rows = await db.query('custom_categories', orderBy: 'created_at ASC');
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

  // ==================== STANDARD CATEGORY OPERATIONS ====================

  /// Get all standard categories (both default and user-created)
  static Future<List<StandardCategory>> getAllStandardCategories({
    bool? activeOnly,
  }) async {
    final db = await database;
    final where = activeOnly == true ? 'is_active = ?' : null;
    final whereArgs = activeOnly == true ? [1] : null;

    final rows = await db.query(
      'standard_categories',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'sort_order ASC, display_name ASC',
    );
    return rows.map((r) => StandardCategory.fromMap(r)).toList();
  }

  /// Get a standard category by ID
  static Future<StandardCategory?> getStandardCategoryById(String id) async {
    final db = await database;
    final rows = await db.query(
      'standard_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isNotEmpty ? StandardCategory.fromMap(rows.first) : null;
  }

  /// Save (insert or replace) a standard category
  static Future<void> saveStandardCategory(StandardCategory category) async {
    final db = await database;
    await db.insert(
      'standard_categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update standard category active status
  static Future<void> updateStandardCategoryStatus(
      String categoryId, bool isActive) async {
    final db = await database;
    await db.update(
      'standard_categories',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [categoryId],
    );
  }

  /// Delete a user-created standard category (cannot delete default categories)
  static Future<void> deleteStandardCategory(String categoryId) async {
    final db = await database;

    // First check if it's a default category
    final category = await getStandardCategoryById(categoryId);
    if (category?.isDefault == true) {
      throw Exception(
          'Cannot delete default categories. Use updateStandardCategoryStatus to disable instead.');
    }

    // Delete the category
    await db.delete('standard_categories',
        where: 'id = ?', whereArgs: [categoryId]);

    // Unlink from transactions (set to uncategorized)
    await db.update(
      'transactions',
      {'standard_category_id': 'uncategorized'},
      where: 'standard_category_id = ?',
      whereArgs: [categoryId],
    );
  }

  /// Update transaction standard category
  static Future<void> updateTransactionStandardCategory(
      String txId, String? standardCategoryId) async {
    final db = await database;
    await db.update(
      'transactions',
      {
        'standard_category_id': standardCategoryId,
        'category':
            _legacyCategoryNameForStandardCategoryId(standardCategoryId),
      },
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Get category usage statistics
  static Future<Map<String, int>> getStandardCategoryUsageStats() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT standard_category_id, COUNT(*) as usage_count
      FROM transactions
      WHERE standard_category_id IS NOT NULL
      GROUP BY standard_category_id
    ''');

    return Map.fromEntries(
      rows.map((r) => MapEntry(
            r['standard_category_id'] as String,
            r['usage_count'] as int,
          )),
    );
  }

  // ==================== CATEGORY PREFERENCES ====================

  /// Get category preferences (which standard categories are enabled)
  static Future<CategoryPreferences> getCategoryPreferences() async {
    final val = await getSetting('category_preferences');
    if (val == null) return CategoryPreferences.defaultPreferences();
    try {
      final map = json.decode(val) as Map<String, dynamic>;
      final prefs = CategoryPreferences.fromMap(map);
      final normalizedIds = prefs.enabledCategoryIds
          .map((id) => StandardCategory.legacyIdRemap[id] ?? id)
          .toSet()
        ..addAll(StandardCategory.newlyAddedDefaultIds);
      return prefs.copyWith(enabledCategoryIds: normalizedIds);
    } catch (_) {
      return CategoryPreferences.defaultPreferences();
    }
  }

  /// Save category preferences
  static Future<void> saveCategoryPreferences(CategoryPreferences prefs) async {
    final jsonStr = json.encode(prefs.toMap());
    await setSetting('category_preferences', jsonStr);
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
      await db.delete('user_settings',
          where: 'key = ?', whereArgs: ['salary_cycle_day']);
    } else {
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
  static Future<void> batchUpdateCategories(
      Map<String, TransactionCategory> updates) async {
    final db = await database;
    final batch = db.batch();
    for (final entry in updates.entries) {
      batch.update(
        'transactions',
        {
          'category': entry.value.name,
          'standard_category_id': entry.value.standardCategoryId,
        },
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
    await batch.commit(noResult: true);
  }
}
