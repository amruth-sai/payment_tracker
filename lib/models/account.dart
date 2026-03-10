// lib/models/account.dart

enum AccountType { bankAccount, creditCard, wallet, upi }

class Account {
  final String id;
  final String name;
  final AccountType type;
  final String? last4Digits;
  final String? bankName;
  final String? cardNetwork; // Visa, Mastercard, Rupay, etc.
  final bool isManuallyAdded;
  final DateTime createdAt;

  Account({
    required this.id,
    required this.name,
    required this.type,
    this.last4Digits,
    this.bankName,
    this.cardNetwork,
    this.isManuallyAdded = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get displayName {
    if (last4Digits != null) {
      return '$name (••••$last4Digits)';
    }
    return name;
  }

  String get typeLabel {
    switch (type) {
      case AccountType.bankAccount:
        return 'Bank Account';
      case AccountType.creditCard:
        return 'Credit Card';
      case AccountType.wallet:
        return 'Wallet';
      case AccountType.upi:
        return 'UPI';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'last4_digits': last4Digits,
      'bank_name': bankName,
      'card_network': cardNetwork,
      'is_manually_added': isManuallyAdded ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as String,
      name: map['name'] as String,
      type: AccountType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => AccountType.bankAccount,
      ),
      last4Digits: map['last4_digits'] as String?,
      bankName: map['bank_name'] as String?,
      cardNetwork: map['card_network'] as String?,
      isManuallyAdded: (map['is_manually_added'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Account copyWith({
    String? id,
    String? name,
    AccountType? type,
    String? last4Digits,
    String? bankName,
    String? cardNetwork,
    bool? isManuallyAdded,
    DateTime? createdAt,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      last4Digits: last4Digits ?? this.last4Digits,
      bankName: bankName ?? this.bankName,
      cardNetwork: cardNetwork ?? this.cardNetwork,
      isManuallyAdded: isManuallyAdded ?? this.isManuallyAdded,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
