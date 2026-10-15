import 'package:sqflite/sqflite.dart';

/// The first release schema. Earlier development databases are not supported.
class DatabaseSchema {
  static const version = 1;
  static const fileName = 'payment_tracker_release.db';
  static const tables = [
    'categories',
    'accounts',
    'user_settings',
    'transactions',
    'processed_sms',
    'sms_processing',
    'transaction_reviews',
    'merchant_rules',
    'sender_mappings',
    'salary_cycles',
    'budgets',
    'alerts',
    'emis',
  ];

  static Future<void> create(Database db, int version) async {
    for (final statement in statements) {
      await db.execute(statement);
    }
  }

  static const statements = <String>[
    '''CREATE TABLE categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name)) > 0),
      emoji TEXT NOT NULL,
      color_value INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    )''',
    '''CREATE TABLE accounts (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL CHECK(type IN ('bankAccount','creditCard','wallet','upi')),
      last4_digits TEXT, bank_name TEXT, card_network TEXT,
      is_manually_added INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL
    )''',
    '''CREATE TABLE user_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
    '''CREATE TABLE transactions (
      id TEXT PRIMARY KEY, sms_id TEXT UNIQUE,
      amount INTEGER NOT NULL CHECK(typeof(amount) = 'integer' AND amount > 0),
      type TEXT NOT NULL CHECK(type IN ('debit','credit')),
      source TEXT NOT NULL CHECK(source IN ('upi','bank','card','wallet','unknown')), sender TEXT NOT NULL, merchant TEXT,
      account_last4 TEXT, date INTEGER NOT NULL, raw_message TEXT NOT NULL,
      reference_id TEXT, balance INTEGER CHECK(balance IS NULL OR typeof(balance) = 'integer'),
      account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
      is_user_corrected INTEGER NOT NULL DEFAULT 0,
      is_salary INTEGER NOT NULL DEFAULT 0,
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      category_source TEXT CHECK(category_source IN ('user','merchant_rule')),
      note TEXT, tag TEXT, is_ignored INTEGER NOT NULL DEFAULT 0,
      transfer_group_id TEXT, transfer_partner_id TEXT,
      is_transfer_source INTEGER NOT NULL DEFAULT 0,
      is_transfer_destination INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''',
    '''CREATE TABLE processed_sms (
      sms_id TEXT PRIMARY KEY, processed_at INTEGER NOT NULL,
      is_transaction INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE sms_processing (
      sms_id TEXT PRIMARY KEY, sender TEXT NOT NULL, date INTEGER NOT NULL,
      outcome TEXT NOT NULL CHECK(outcome IN ('transaction','needsReview','skipped')), reason TEXT NOT NULL, folder TEXT NOT NULL,
      raw_message TEXT, parser_version INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )''',
    '''CREATE TABLE transaction_reviews (
      id TEXT PRIMARY KEY, amount INTEGER NOT NULL CHECK(typeof(amount) = 'integer' AND amount > 0),
      source TEXT NOT NULL CHECK(source IN ('upi','bank','card','wallet','unknown')), sender TEXT NOT NULL, merchant TEXT,
      account_last4 TEXT, date INTEGER NOT NULL, raw_message TEXT NOT NULL,
      reference_id TEXT, balance INTEGER CHECK(balance IS NULL OR typeof(balance) = 'integer'),
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      category_source TEXT CHECK(category_source IN ('user','merchant_rule')),
      tag TEXT, is_ignored INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL
    )''',
    '''CREATE TABLE merchant_rules (
      id TEXT PRIMARY KEY, match_text TEXT NOT NULL CHECK(length(trim(match_text)) > 0),
      merchant TEXT NOT NULL,
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      tag TEXT, created_at INTEGER NOT NULL, is_enabled INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE sender_mappings (
      id TEXT PRIMARY KEY, sender_id TEXT NOT NULL UNIQUE,
      account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL, is_user_assigned INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE salary_cycles (
      id TEXT PRIMARY KEY, start_date INTEGER NOT NULL, end_date INTEGER,
      salary_amount INTEGER NOT NULL CHECK(typeof(salary_amount) = 'integer' AND salary_amount > 0),
      salary_transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      employer TEXT, created_at INTEGER NOT NULL
    )''',
    '''CREATE TABLE budgets (
      id TEXT PRIMARY KEY,
      category_id TEXT NOT NULL UNIQUE REFERENCES categories(id) ON DELETE CASCADE,
      monthly_limit INTEGER NOT NULL CHECK(typeof(monthly_limit) = 'integer' AND monthly_limit > 0),
      is_suggested INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL
    )''',
    '''CREATE TABLE alerts (
      id TEXT PRIMARY KEY, type TEXT NOT NULL CHECK(type IN ('anomaly','duplicate','budgetWarning','dailyDigest','emiDetected')), title TEXT NOT NULL,
      message TEXT NOT NULL, severity TEXT NOT NULL CHECK(severity IN ('info','warning','critical')), transaction_id TEXT,
      is_read INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL
    )''',
    '''CREATE TABLE emis (
      id TEXT PRIMARY KEY, merchant TEXT NOT NULL, amount INTEGER NOT NULL CHECK(typeof(amount) = 'integer' AND amount > 0),
      day_of_month INTEGER NOT NULL, occurrences TEXT NOT NULL,
      total_detected INTEGER NOT NULL, estimated_total INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1
    )''',
    'CREATE INDEX idx_transactions_date ON transactions(date DESC, id DESC)',
    'CREATE INDEX idx_transactions_account ON transactions(account_id)',
    'CREATE INDEX idx_transactions_category ON transactions(category_id)',
    'CREATE INDEX idx_transactions_transfer ON transactions(transfer_group_id)',
    'CREATE INDEX idx_reviews_date ON transaction_reviews(date DESC)',
    'CREATE INDEX idx_processing_outcome ON sms_processing(outcome, date DESC)',
  ];
}
