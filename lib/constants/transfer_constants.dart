// lib/constants/transfer_constants.dart

/// Constants for transfer-related operations
class TransferConstants {
  TransferConstants._(); // Private constructor to prevent instantiation

  // Database field names for transfer operations
  static const String transferGroupIdField = 'transfer_group_id';
  static const String transferPartnerIdField = 'transfer_partner_id';
  static const String isTransferSourceField = 'is_transfer_source';
  static const String isTransferDestinationField = 'is_transfer_destination';

  // Transfer detection keywords
  static const List<String> transferKeywords = [
    'transfer',
    'neft',
    'imps',
    'rtgs',
    'fund transfer'
  ];

  // UI text constants
  static const String transferLabel = '🔄 Transfer';
  static const String accountTransferLabel = 'Account Transfer';

  // Transfer categories
  static const String transferCategory = 'Transfer';
}