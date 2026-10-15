enum BackupRestoreMode { merge, replace }

/// Versioned, plaintext database snapshot used only between encryption and
/// decryption. The persisted backup file is always encrypted by Android.
class LocalBackup {
  const LocalBackup({
    required this.createdAt,
    required this.databaseVersion,
    required this.tables,
  });

  static const format = 'payment_tracker_release_backup';
  static const formatVersion = 1;

  final DateTime createdAt;
  final int databaseVersion;
  final Map<String, List<Map<String, dynamic>>> tables;

  int get transactionCount => tables['transactions']?.length ?? 0;

  int get recordCount =>
      tables.values.fold(0, (count, rows) => count + rows.length);

  Map<String, dynamic> toJson() {
    return {
      'format': format,
      'format_version': formatVersion,
      'created_at': createdAt.toIso8601String(),
      'database_version': databaseVersion,
      'tables': tables,
    };
  }

  factory LocalBackup.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format || json['format_version'] != formatVersion) {
      throw const FormatException(
        'This is not a supported Payment Tracker backup.',
      );
    }

    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    final databaseVersion = json['database_version'];
    final rawTables = json['tables'];
    if (createdAt == null || databaseVersion is! int || rawTables is! Map) {
      throw const FormatException('The backup file is incomplete.');
    }

    final tables = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawTables.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('The backup contains invalid table data.');
      }
      tables[entry.key as String] = (entry.value as List).map((row) {
        if (row is! Map) {
          throw const FormatException('The backup contains an invalid record.');
        }
        return Map<String, dynamic>.from(row);
      }).toList();
    }

    return LocalBackup(
      createdAt: createdAt,
      databaseVersion: databaseVersion,
      tables: tables,
    );
  }
}
