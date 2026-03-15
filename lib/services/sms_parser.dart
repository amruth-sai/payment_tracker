// lib/services/sms_parser.dart

import '../models/transaction.dart';
import '../services/sender_discovery_service.dart';
import '../services/local_storage_service.dart';

class SmsParser {
  // Cache for sender mappings to avoid database lookups on every parse
  static Map<String, String>? _senderMappingCache;
  static DateTime? _cacheLastUpdated;
  static const Duration _cacheValidDuration = Duration(minutes: 10);

  // User's specific bank and credit card sender mappings (kept for fallback)
  static const Map<String, List<String>> _userBankMapping = {
    'HDFC': [
      'HDFCBK', 'DM-HDFCBK', 'HDFC', 'HDFCBANK', 'HDFCLT',
      'HDFCCC', 'HDFCCR', 'HDFCDC', 'HDFCNET', 'HDFCALERT',
    ],
    'ICICI': [
      'ICICIB', 'DM-ICICIB', 'ICICI', 'ICICIBANK', 'ICICIBK',
      'ICICIMB', 'ICICINET', 'ICICIALERT',
    ],
    'AIRTEL': [
      'AIRTEL', 'ARTLPY', 'ATBANK', 'AIRBNK', 'AIRTELPAY',
      'AIRTELBANK', 'AIRTELBK', 'ARTLBK',
    ],
    'JIO PAY': [
      'JIOPAY', 'JIOMNY', 'JIOFIN', 'JIOBNK', 'JIOBANK',
      'JIOPAYMENTS', 'JIOFINANCE',
    ],
    'SBI': [
      'SBIINB', 'SBI', 'SBIBANK', 'SBIMB', 'SBINET', 'SBIALERT',
      'SBICRD', 'SBICC', 'SBIDC',
    ],
  };

  // User's specific credit card mappings (kept for fallback)
  static const Map<String, List<String>> _userCreditCardMapping = {
    'HDFC1': ['HDFCCC', 'HDFCCR1', 'HDFCCARD1'],
    'HDFC2': ['HDFCCR2', 'HDFCCARD2', 'HDFCDC2'],
    'ICICI Credit': ['ICICCC', 'ICICCARD', 'ICICIMB', 'ICICINET'],
    'OneCard': ['ONECARD', 'ONECRD', 'BOBONE', 'BOBSMS', 'BOBBNK'],
    'SBI Credit': ['SBICRD', 'SBICC', 'SBICARD'],
  };

  // Known bank/payment sender IDs (keeping for backward compatibility)
  static const _knownSenders = [
    // Traditional Banks
    'HDFCBK', 'SBIINB', 'ICICIB', 'AXISBK', 'KOTAKB', 'PNBSMS',
    'BOIIND', 'CANBNK', 'UNIONB', 'INDUSB', 'YESBK', 'IDBIBK',
    'HSBC', 'SCBNK', 'CITIBK', 'RBLBNK', 'FEDRAL',
    'BOBSMS', 'BOBONE', 'BOBBNK', // Bank of Baroda / OneCard

    // Telecom & Digital Banks
    'AIRTEL', 'ARTLPY', 'ATBANK', 'AIRBNK', // Airtel Payments Bank
    'JIOPAY', 'JIOMNY', 'JIOFIN', 'JIOBNK', // Jio Payments / Jio Finance

    // UPI & Wallets
    'PAYTM', 'GPAY', 'PHONEPE', 'AMAZONPAY', 'MOBIKWIK',
    'BHIMUPI', 'UPIPAY',

    // Fintech & Neo-banks
    'CREDCLUB', 'SLICE', 'JUPITER', 'FININ', 'FIAPP',
    'NIYOBNK', 'OPENBNK', 'RAZORPY',
    'ONECARD', 'ONECRD', // OneCard

    // Others
    'ATMMSG', 'TXNALRT', 'ALERTS',
  ];

  // Credit card issuers - transactions from these are typically debits (spending)
  static const _creditCardSenders = [
    'ONECARD', 'ONECRD', 'BOBONE', // OneCard (Bank of Baroda)
    'SLICE', 'CREDCLUB',
  ];

  static bool isBankSms(String sender) {
    final s = sender.toUpperCase();
    return _knownSenders.any((k) => s.contains(k)) ||
        RegExp(r'^[A-Z]{2}-[A-Z]{6}$').hasMatch(sender); // DM-HDFCBK format
  }

  /// Load sender mappings from database with caching
  static Future<Map<String, String>> _loadSenderMappings() async {
    final now = DateTime.now();

    // Return cached mappings if still valid
    if (_senderMappingCache != null &&
        _cacheLastUpdated != null &&
        now.difference(_cacheLastUpdated!) < _cacheValidDuration) {
      return _senderMappingCache!;
    }

    // Load fresh mappings from database
    try {
      final accountsWithSenders = await SenderDiscoveryService.getAccountsWithSenders();
      final mappings = <String, String>{};

      for (final accountWithSenders in accountsWithSenders) {
        final accountName = accountWithSenders.account.name;
        for (final senderMapping in accountWithSenders.senderMappings) {
          mappings[senderMapping.senderId] = accountName;
        }
      }

      _senderMappingCache = mappings;
      _cacheLastUpdated = now;
      return mappings;
    } catch (e) {
      // If database access fails, return empty map (will fall back to hardcoded mappings)
      return {};
    }
  }

  /// Clear the sender mapping cache (call when mappings change)
  static void clearSenderMappingCache() {
    _senderMappingCache = null;
    _cacheLastUpdated = null;
  }

  /// Groups sender by mapping to user's specific bank/credit card names
  /// Now uses dynamic database mappings with hardcoded fallback
  static Future<String> getUnifiedSenderName(String rawSender) async {
    final cleanedSender = _cleanSender(rawSender).toUpperCase();

    // Try dynamic mappings first
    final dynamicMappings = await _loadSenderMappings();
    if (dynamicMappings.containsKey(cleanedSender)) {
      return dynamicMappings[cleanedSender]!;
    }

    // Fallback to hardcoded mappings for backward compatibility
    // Check user's bank mappings first
    for (final entry in _userBankMapping.entries) {
      final bankName = entry.key;
      final senderIds = entry.value;

      if (senderIds.any((id) => cleanedSender.contains(id.toUpperCase()))) {
        return bankName;
      }
    }

    // Check user's credit card mappings
    for (final entry in _userCreditCardMapping.entries) {
      final cardName = entry.key;
      final senderIds = entry.value;

      if (senderIds.any((id) => cleanedSender.contains(id.toUpperCase()))) {
        return cardName;
      }
    }

    // Return cleaned sender if no mapping found
    return cleanedSender;
  }

  /// Sync version of getUnifiedSenderName for compatibility
  /// Uses cached mappings, falls back to hardcoded if cache is empty
  static String getUnifiedSenderNameSync(String rawSender) {
    final cleanedSender = _cleanSender(rawSender).toUpperCase();

    // Try cached mappings first
    if (_senderMappingCache != null && _senderMappingCache!.containsKey(cleanedSender)) {
      return _senderMappingCache![cleanedSender]!;
    }

    // Fallback to hardcoded mappings
    // Check user's bank mappings first
    for (final entry in _userBankMapping.entries) {
      final bankName = entry.key;
      final senderIds = entry.value;

      if (senderIds.any((id) => cleanedSender.contains(id.toUpperCase()))) {
        return bankName;
      }
    }

    // Check user's credit card mappings
    for (final entry in _userCreditCardMapping.entries) {
      final cardName = entry.key;
      final senderIds = entry.value;

      if (senderIds.any((id) => cleanedSender.contains(id.toUpperCase()))) {
        return cardName;
      }
    }

    // Return cleaned sender if no mapping found
    return cleanedSender;
  }

  /// Gets all transactions grouped by unified sender names
  static Map<String, List<Transaction>> groupTransactionsBySender(
      List<Transaction> transactions) {
    final Map<String, List<Transaction>> grouped = {};

    for (final transaction in transactions) {
      final unifiedSender = getUnifiedSenderNameSync(transaction.sender);

      if (!grouped.containsKey(unifiedSender)) {
        grouped[unifiedSender] = [];
      }

      grouped[unifiedSender]!.add(transaction);
    }

    // Sort by date for each sender group
    for (final list in grouped.values) {
      list.sort((a, b) => b.date.compareTo(a.date));
    }

    return grouped;
  }

  /// Checks if a sender is one of user's specific banks/cards
  /// Now uses dynamic mappings with hardcoded fallback
  static Future<bool> isUserBank(String sender) async {
    final unifiedName = await getUnifiedSenderName(sender);

    // Check if this sender is assigned to any account in the database
    final accountId = await SenderDiscoveryService.getAccountForSender(cleanSender(sender));
    if (accountId != null) {
      return true; // Any assigned sender is considered a "user bank"
    }

    // Fallback to hardcoded mappings
    return _userBankMapping.containsKey(unifiedName) ||
           _userCreditCardMapping.containsKey(unifiedName);
  }

  /// Sync version for performance
  static bool isUserBankSync(String sender) {
    final unifiedName = getUnifiedSenderNameSync(sender);
    return _userBankMapping.containsKey(unifiedName) ||
           _userCreditCardMapping.containsKey(unifiedName);
  }

  /// Gets the account type (bank or credit card) for a sender
  /// Now uses dynamic database mapping with hardcoded fallback
  static Future<String> getAccountType(String sender) async {
    // Try to get account type from database
    try {
      final accountId = await SenderDiscoveryService.getAccountForSender(cleanSender(sender));
      if (accountId != null) {
        final accounts = await LocalStorageService.getAllAccounts();
        final account = accounts.where((a) => a.id == accountId).isNotEmpty
            ? accounts.where((a) => a.id == accountId).first
            : null;
        if (account != null) {
          return account.typeLabel;
        }
      }
    } catch (e) {
      // Fall back to hardcoded logic if database fails
    }

    // Fallback to hardcoded mappings
    final unifiedName = getUnifiedSenderNameSync(sender);

    if (_userBankMapping.containsKey(unifiedName)) {
      return 'Bank Account';
    } else if (_userCreditCardMapping.containsKey(unifiedName)) {
      return 'Credit Card';
    }

    return 'Payment Service';
  }

  /// Sync version for performance
  static String getAccountTypeSync(String sender) {
    final unifiedName = getUnifiedSenderNameSync(sender);

    if (_userBankMapping.containsKey(unifiedName)) {
      return 'Bank Account';
    } else if (_userCreditCardMapping.containsKey(unifiedName)) {
      return 'Credit Card';
    }

    return 'Payment Service';
  }

  static Future<Transaction?> parse(
      String body, String sender, DateTime date, String id) async {
    final lower = body.toLowerCase();

    // Must contain amount indicators
    if (!lower.contains('rs') &&
        !lower.contains('inr') &&
        !lower.contains('₹') &&
        !lower.contains('amount')) {
      return null;
    }

    final amount = _extractAmount(body);
    if (amount == null || amount <= 0) return null;

    final type = _detectType(body, sender);
    if (type == TransactionType.unknown) return null;

    // Use unified sender name for grouping
    final unifiedSender = await getUnifiedSenderName(sender);

    // Try to get account ID from sender mapping
    String? accountId;
    try {
      accountId = await SenderDiscoveryService.getAccountForSender(cleanSender(sender));
    } catch (e) {
      // If database access fails, accountId remains null
    }

    return Transaction(
      id: id,
      amount: amount,
      type: type,
      source: _detectSource(body, sender),
      sender: unifiedSender, // Use unified name instead of raw sender
      merchant: _extractMerchant(body, type),
      accountLast4: _extractAccountLast4(body),
      date: date,
      rawMessage: body,
      referenceId: _extractRefId(body),
      balance: _extractBalance(body),
      accountId: accountId, // Assign to account if mapping exists
    );
  }

  /// Sync version of parse for compatibility (when account assignment isn't needed)
  static Transaction? parseSync(
      String body, String sender, DateTime date, String id) {
    final lower = body.toLowerCase();

    // Must contain amount indicators
    if (!lower.contains('rs') &&
        !lower.contains('inr') &&
        !lower.contains('₹') &&
        !lower.contains('amount')) {
      return null;
    }

    final amount = _extractAmount(body);
    if (amount == null || amount <= 0) return null;

    final type = _detectType(body, sender);
    if (type == TransactionType.unknown) return null;

    // Use sync unified sender name for grouping
    final unifiedSender = getUnifiedSenderNameSync(sender);

    return Transaction(
      id: id,
      amount: amount,
      type: type,
      source: _detectSource(body, sender),
      sender: unifiedSender, // Use unified name instead of raw sender
      merchant: _extractMerchant(body, type),
      accountLast4: _extractAccountLast4(body),
      date: date,
      rawMessage: body,
      referenceId: _extractRefId(body),
      balance: _extractBalance(body),
    );
  }

  static double? _extractAmount(String body) {
    // Patterns: Rs.1,234.56 | INR 1234 | ₹1,234.56 | Rs 1234.00
    final patterns = [
      RegExp(r'(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
          caseSensitive: false),
      RegExp(
          r'(?:amount|amt)[:\s]+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
          caseSensitive: false),
      RegExp(r'([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:rs|inr|₹)',
          caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final str = match.group(1)!.replaceAll(',', '');
        final val = double.tryParse(str);
        if (val != null && val > 0 && val < 10000000) {
          return val; // sanity: < 1 crore
        }
      }
    }
    return null;
  }

  static TransactionType _detectType(String body, String sender) {
    final lower = body.toLowerCase();
    final senderUpper = sender.toUpperCase();

    // Check if this is from a credit card issuer (typically these are spending alerts)
    final isFromCreditCard =
        _creditCardSenders.any((s) => senderUpper.contains(s));

    // Credit card specific patterns - these are almost always debits (spending)
    final creditCardSpendPatterns = [
      'spent',
      'transaction of',
      'txn of',
      'purchase',
      'used at',
      'transaction at',
      'payment of',
      'charged',
      'bill payment',
    ];

    // If from credit card sender and matches spend pattern, it's a debit
    if (isFromCreditCard &&
        creditCardSpendPatterns.any((p) => lower.contains(p))) {
      return TransactionType.debit;
    }

    final creditWords = [
      'credited',
      'received',
      'credit',
      'deposited',
      'added',
      'received from',
      'money added',
      'cashback',
      'refund',
      'reversed',
      'reversal',
    ];
    final debitWords = [
      'debited',
      'spent',
      'debit',
      'payment',
      'paid',
      'withdrawn',
      'transferred to',
      'purchase',
      'charged',
      'used at',
      'sent to',
      'transaction at',
      'txn of',
      'transaction of',
      'bill payment',
    ];

    // Context-aware detection: "credited to merchant" means debit for you
    // "your account credited" or "credited to [Bank] A/c" means credit for you
    if (lower.contains('credited to') &&
        !lower.contains('your') &&
        !lower.contains('a/c credited') &&
        !RegExp(r'credited to\s+[\w\s]*(?:a/c|account|ac\b)',
                caseSensitive: false)
            .hasMatch(body)) {
      return TransactionType.debit;
    }

    // "Amount debited from" is a clear debit
    if (lower.contains('debited from') || lower.contains('debit from')) {
      return TransactionType.debit;
    }

    // "Amount credited to your" is a clear credit
    if (lower.contains('credited to your') ||
        lower.contains('credit to your')) {
      return TransactionType.credit;
    }

    bool hasCredit = creditWords.any((w) => lower.contains(w));
    bool hasDebit = debitWords.any((w) => lower.contains(w));

    // If from credit card and both signals present, prefer debit (spending)
    if (isFromCreditCard && hasCredit && hasDebit) {
      return TransactionType.debit;
    }

    if (hasCredit && !hasDebit) return TransactionType.credit;
    if (hasDebit && !hasCredit) return TransactionType.debit;

    // Both or neither – use positional heuristic
    // Check what comes first in the message
    if (hasCredit && hasDebit) {
      int creditPos = creditWords
          .map((w) => lower.indexOf(w))
          .where((i) => i >= 0)
          .reduce((a, b) => a < b ? a : b);
      int debitPos = debitWords
          .map((w) => lower.indexOf(w))
          .where((i) => i >= 0)
          .reduce((a, b) => a < b ? a : b);
      return creditPos < debitPos
          ? TransactionType.credit
          : TransactionType.debit;
    }

    // If from credit card and no clear signal, assume debit
    if (isFromCreditCard) return TransactionType.debit;

    return TransactionType.unknown;
  }

  static PaymentSource _detectSource(String body, String sender) {
    final lower = body.toLowerCase();
    final s = sender.toUpperCase();

    if (lower.contains('upi') ||
        s.contains('PAYTM') ||
        s.contains('GPAY') ||
        s.contains('PHONEPE')) {
      return PaymentSource.upi;
    }
    if (lower.contains('credit card') ||
        lower.contains('debit card') ||
        lower.contains('card no')) {
      return PaymentSource.card;
    }
    if (lower.contains('wallet') ||
        s.contains('MOBIKWIK') ||
        s.contains('AMAZONPAY')) {
      return PaymentSource.wallet;
    }
    return PaymentSource.bank;
  }

  static String? _extractMerchant(String body, TransactionType type) {
    if (type == TransactionType.debit) {
      // "at MERCHANT NAME" or "to VPA@bank"
      final atMatch = RegExp(
              r"(?:at|to)\s+([A-Z][A-Za-z0-9 &\-']+?)(?:\s+on|\s+via|\s+for|\s+ref|\.|,|$)",
              caseSensitive: false)
          .firstMatch(body);
      if (atMatch != null) {
        final name = atMatch.group(1)!.trim();
        if (name.length > 2 && name.length < 40) return name;
      }
    }
    if (type == TransactionType.credit) {
      // Try VPA pattern first: "from VPA xxx@yyy"
      final vpaMatch = RegExp(
              r'(?:from)\s+(?:VPA\s+)?([A-Za-z0-9.\-]+@[A-Za-z0-9]+)',
              caseSensitive: false)
          .firstMatch(body);
      if (vpaMatch != null) {
        return vpaMatch.group(1)!.trim();
      }
      // Standard "from MERCHANT" pattern
      final fromMatch = RegExp(
              r"(?:from|by)\s+([A-Z][A-Za-z0-9 &\-']+?)(?:\s+on|\s+via|\s+ref|\.|,|$)",
              caseSensitive: false)
          .firstMatch(body);
      if (fromMatch != null) {
        final name = fromMatch.group(1)!.trim();
        if (name.length > 2 && name.length < 40) return name;
      }
    }
    return null;
  }

  static String? _extractAccountLast4(String body) {
    final match = RegExp(
            r'(?:a/c|account|ac|card)\s*(?:no\.?|num\.?)?\s*[xX*]+(\d{4})',
            caseSensitive: false)
        .firstMatch(body);
    return match?.group(1);
  }

  static String? _extractRefId(String body) {
    final patterns = [
      RegExp(r'(?:ref\.?|txn\.?|utr|rrn)[:\s#]+([A-Z0-9]{8,22})',
          caseSensitive: false),
      RegExp(r'(?:UPI)\s+(\d{9,15})', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static double? _extractBalance(String body) {
    final match = RegExp(
            r'(?:bal(?:ance)?|avl\.?)[:\s]+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
            caseSensitive: false)
        .firstMatch(body);
    if (match != null) {
      final str = match.group(1)!.replaceAll(',', '');
      return double.tryParse(str);
    }
    return null;
  }

  static String cleanSender(String sender) {
    // "DM-HDFCBK" → "HDFCBK"
    return sender.replaceAll(RegExp(r'^[A-Z]{2}-'), '');
  }

  static String _cleanSender(String sender) {
    return cleanSender(sender); // Delegate to public method
  }
}
