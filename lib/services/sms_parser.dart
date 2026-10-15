// lib/services/sms_parser.dart

import '../models/transaction.dart';
import '../models/transaction_review.dart';
import '../services/sender_discovery_service.dart';
import '../services/local_storage_service.dart';

class SmsParser {
  // Cache for sender mappings to avoid database lookups on every parse
  static Map<String, String>? _senderMappingCache;
  static DateTime? _cacheLastUpdated;
  static const Duration _cacheValidDuration = Duration(minutes: 10);

  // Recognized sender patterns used to identify financial messages.
  static const _knownSenders = [
    // Traditional Banks
    'HDFCBK', 'SBIINB', 'ICICIB', 'AXISBK', 'KOTAKB', 'PNBSMS',
    'BOIIND', 'CANBNK', 'UNIONB', 'INDUSB', 'YESBK', 'IDBIBK',
    'HSBC', 'SCBNK', 'CITIBK', 'RBLBNK', 'FEDRAL',
    'BOBSMS', 'BOBONE', 'BOBBNK', // Bank of Baroda / OneCard
    // Telecom & Digital Banks
    'AIRTEL', 'ARTLPY', 'ATBANK', 'AIRBNK', 'AIRBKS', // Airtel Payments Bank
    'JIOPAY', 'JIOMNY', 'JIOFIN', 'JIOBNK', 'JIOPBS',
    'JPBL', // Jio Payments Bank / Jio Finance
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

  // Recognized card issuers identify the payment channel, never the direction.
  static const _creditCardSenders = [
    'ONECARD', 'ONECRD', 'BOBONE', // OneCard (Bank of Baroda)
    'SLICE', 'CREDCLUB',
  ];

  static bool isBankSms(String sender) {
    final s = sender.toUpperCase();
    return _knownSenders.any((k) => s.contains(k)) ||
        RegExp(
          r'^[A-Z]{2}-[A-Z]{5,6}(?:-[A-Z])?$',
        ).hasMatch(sender); // AD-AIRBNK-S, DM-HDFCBK, JD-JIOPBS-S format
  }

  /// Payment alerts from unfamiliar senders can still enter review.
  static bool isLikelyPaymentMessage(String sender, String body) {
    if (isBankSms(sender)) return true;
    if (!hasAmountIndicator(body)) return false;
    return RegExp(
      r'\b(account|upi|imps|neft|rtgs|bank|card|wallet|transaction|txn)\b|a/c',
      caseSensitive: false,
    ).hasMatch(body);
  }

  static bool hasAmountIndicator(String body) =>
      _hasAmountIndicator(body.toLowerCase()) || body.contains('\u20b9');

  static bool isSecurityMessage(String body) {
    final lower = body.toLowerCase();
    final hasSecurityCode = RegExp(
      r'\b(otp|one.time.password|verification code|login code)\b',
    ).hasMatch(lower);
    final confirmsPayment = RegExp(
      r'\b(debited|credited|withdrawn|spent|paid to|received from)\b',
    ).hasMatch(lower);
    return hasSecurityCode && !confirmsPayment;
  }

  static String skipReason(String body, String sender) {
    if (isNonTransaction(body)) return 'not_completed';
    if (!isLikelyPaymentMessage(sender, body)) return 'sender_not_recognized';
    if (!hasAmountIndicator(body)) return 'no_amount_indicator';
    if (_extractAmount(body) == null) return 'amount_not_found';
    return 'not_a_payment';
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
      final accountsWithSenders =
          await SenderDiscoveryService.getAccountsWithSenders();
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
      // An unmapped sender keeps its original normalized name.
      return {};
    }
  }

  /// Clear the sender mapping cache (call when mappings change)
  static void clearSenderMappingCache() {
    _senderMappingCache = null;
    _cacheLastUpdated = null;
  }

  /// Use only accounts explicitly mapped by the user.
  static Future<String> getUnifiedSenderName(String rawSender) async {
    final sender = cleanSender(rawSender).toUpperCase();
    return (await _loadSenderMappings())[sender] ?? sender;
  }

  static String getUnifiedSenderNameSync(String rawSender) {
    final sender = cleanSender(rawSender).toUpperCase();
    return _senderMappingCache?[sender] ?? sender;
  }

  /// Gets all transactions grouped by unified sender names
  static Map<String, List<Transaction>> groupTransactionsBySender(
    List<Transaction> transactions,
  ) {
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

  static Future<bool> isUserBank(String sender) async =>
      await SenderDiscoveryService.getAccountForSender(cleanSender(sender)) !=
      null;

  static bool isUserBankSync(String sender) =>
      _senderMappingCache?.containsKey(cleanSender(sender).toUpperCase()) ??
      false;

  static Future<String> getAccountType(String sender) async {
    final id = await SenderDiscoveryService.getAccountForSender(
      cleanSender(sender),
    );
    for (final account in await LocalStorageService.getAllAccounts()) {
      if (account.id == id) return account.typeLabel;
    }
    return 'Payment Service';
  }

  static String getAccountTypeSync(String sender) => 'Payment Service';

  static Future<Transaction?> parse(
    String body,
    String sender,
    DateTime date,
    String id,
  ) async {
    if (isNonTransaction(body) || !hasAmountIndicator(body)) return null;

    final amount = _extractAmount(body);
    if (amount == null || amount <= 0) return null;

    final type = _detectType(body, sender);
    if (type == TransactionType.unknown) return null;

    // Use unified sender name for grouping
    final unifiedSender = await getUnifiedSenderName(sender);

    // Try to get account ID from sender mapping
    String? accountId;
    try {
      accountId = await SenderDiscoveryService.getAccountForSender(
        cleanSender(sender),
      );
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

  /// Sync version of parse for callers that do not need account assignment
  static Transaction? parseSync(
    String body,
    String sender,
    DateTime date,
    String id,
  ) {
    if (isNonTransaction(body) || !hasAmountIndicator(body)) return null;

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

  /// Returns payment-like messages that have an amount but no reliable
  /// debit/credit direction. These are shown in the local review inbox.
  static TransactionReview? buildReviewCandidate(
    String body,
    String sender,
    DateTime date,
    String id,
  ) {
    if (isNonTransaction(body) || !hasAmountIndicator(body)) return null;

    final amount = _extractAmount(body);
    if (amount == null || amount <= 0) return null;

    if (_detectType(body, sender) != TransactionType.unknown) return null;

    return TransactionReview(
      id: id,
      amount: amount,
      source: _detectSource(body, sender),
      sender: sender,
      merchant:
          _extractMerchant(body, TransactionType.debit) ??
          _extractMerchant(body, TransactionType.credit),
      accountLast4: _extractAccountLast4(body),
      date: date,
      rawMessage: body,
      referenceId: _extractRefId(body),
      balance: _extractBalance(body),
      createdAt: DateTime.now(),
    );
  }

  /// Creates a confirmed transaction from a review item after a user picks
  /// its direction. The item is then saved atomically by LocalStorageService.
  static Future<Transaction> transactionFromReview(
    TransactionReview review,
    TransactionType type,
  ) async {
    if (type == TransactionType.unknown) {
      throw ArgumentError.value(type, 'type', 'Must be debit or credit.');
    }

    String? accountId;
    try {
      accountId = await SenderDiscoveryService.getAccountForSender(
        cleanSender(review.sender),
      );
    } catch (_) {
      // The corrected transaction remains usable without an account mapping.
    }

    final transaction = Transaction(
      id: review.id,
      amount: review.amount,
      type: type,
      source: review.source,
      sender: await getUnifiedSenderName(review.sender),
      merchant: review.merchant ?? _extractMerchant(review.rawMessage, type),
      accountLast4: review.accountLast4,
      date: review.date,
      rawMessage: review.rawMessage,
      referenceId: review.referenceId,
      balance: review.balance,
      accountId: accountId,
      isUserCorrected: true,
      categoryId: review.categoryId,
      categorySource: review.categoryId == null
          ? null
          : (review.categorySource ?? 'user'),
      tag: review.tag,
    );
    return transaction;
  }

  static bool _hasAmountIndicator(String lower) {
    return lower.contains('\u20b9') ||
        RegExp(r'\b(?:rs\.?|inr)\s*\d|\b(?:amount|amt)\b').hasMatch(lower);
  }

  /// Failed, pending and requested payments are not completed movements.
  static bool isNonTransaction(String body) => RegExp(
    r'\b(failed|declined|unsuccessful|pending|scheduled|due|requested|request to pay|will be|not debited|not credited)\b',
    caseSensitive: false,
  ).hasMatch(body);

  static double? _extractAmount(String body) {
    final pattern = RegExp(
      r'(?:rs\.?|inr|\u20b9|amount[:\s]+|amt[:\s]+)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    final candidates = <double>{};
    for (final match in pattern.allMatches(body)) {
      final prefix = body.substring(0, match.start).toLowerCase();
      // Balance and available-limit values never represent this payment.
      if (RegExp(
        r'(?:bal(?:ance)?|available limit|credit limit|outstanding)\s*[:.\-]?\s*(?:is\s*)?$',
      ).hasMatch(prefix)) {
        continue;
      }
      final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (value != null && value > 0 && value.isFinite) candidates.add(value);
    }
    // Preserve ambiguous multi-amount messages for manual review of skipped SMS.
    return candidates.length == 1 ? candidates.single : null;
  }

  static TransactionType _detectType(String body, String sender) {
    if (isNonTransaction(body)) return TransactionType.unknown;
    final lower = body.toLowerCase().replaceAll(
      RegExp(r'\b(?:credit|debit)\s+card\b'),
      'card',
    );
    // An explicit completed refund takes priority over purchase context.
    if (RegExp(
      r'\b(refunded|reversed|cashback credited|refund credited|refund of)\b',
    ).hasMatch(lower)) {
      return TransactionType.credit;
    }
    final credit = RegExp(
      r'\b(credited|received|deposited|added|cashback|refund|reversal)\b',
    ).hasMatch(lower);
    final debit = RegExp(
      r'\b(debited|spent|paid|withdrawn|transferred to|purchase|charged|used|sent|payment to|payment of|txn of|transaction of|transaction at)\b',
    ).hasMatch(lower);
    if (credit == debit) return TransactionType.unknown;
    return credit ? TransactionType.credit : TransactionType.debit;
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
    if (_creditCardSenders.any(s.contains) ||
        lower.contains('credit card') ||
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
      // Pattern 1: "Info: UPI/DR/REF/MERCHANT" (Jio format)
      final infoMatch = RegExp(
        r'Info:\s*UPI/(?:DR|CR)/\d+/([A-Za-z0-9 ]+)',
        caseSensitive: false,
      ).firstMatch(body);
      if (infoMatch != null) {
        final name = infoMatch.group(1)!.trim();
        if (name.length > 2 && name.length < 40) return name;
      }

      // Pattern 2: "At VPA@bank" (HDFC Card UPI format)
      final atVpaMatch = RegExp(
        r'(?:at)\s+([A-Za-z0-9.\-]+@[A-Za-z0-9]+)',
        caseSensitive: false,
      ).firstMatch(body);
      if (atVpaMatch != null) {
        return atVpaMatch.group(1)!.trim();
      }

      // Pattern 3: "To MERCHANT NAME" at start of line (HDFC UPI multi-line format)
      final toLineMatch = RegExp(
        r'(?:^|\n)To\s+([A-Z][A-Za-z0-9 ]+?)(?:\s*\n|\s+On\s|\s*$)',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(body);
      if (toLineMatch != null) {
        final name = toLineMatch.group(1)!.trim();
        if (name.length > 2 && name.length < 40) return name;
      }

      // Pattern 4: "at MERCHANT NAME" or "to VPA@bank" (original patterns)
      final atMatch = RegExp(
        r"(?:at|to)\s+([A-Z][A-Za-z0-9 &\-']+?)(?:\s+on|\s+via|\s+for|\s+ref|\.|,|$)",
        caseSensitive: false,
      ).firstMatch(body);
      if (atMatch != null) {
        final name = atMatch.group(1)!.trim();
        if (name.length > 2 && name.length < 40) return name;
      }
    }
    if (type == TransactionType.credit) {
      // Try VPA pattern first: "from VPA xxx@yyy"
      final vpaMatch = RegExp(
        r'(?:from)\s+(?:VPA\s+)?([A-Za-z0-9.\-]+@[A-Za-z0-9]+)',
        caseSensitive: false,
      ).firstMatch(body);
      if (vpaMatch != null) {
        return vpaMatch.group(1)!.trim();
      }
      // Standard "from MERCHANT" pattern
      final fromMatch = RegExp(
        r"(?:from|by)\s+([A-Z][A-Za-z0-9 &\-']+?)(?:\s+on|\s+via|\s+ref|\.|,|$)",
        caseSensitive: false,
      ).firstMatch(body);
      if (fromMatch != null) {
        final name = fromMatch.group(1)!.trim();
        if (name.length > 2 && name.length < 40) return name;
      }
    }
    return null;
  }

  static String? _extractAccountLast4(String body) {
    final patterns = [
      // Pattern 1: "a/c XX1234" or "A/C *1651" (standard bank format)
      RegExp(
        r'(?:a/c|account|ac)\s*(?:no\.?|num\.?)?\s*[xX*]+(\d{4})',
        caseSensitive: false,
      ),
      // Pattern 2: "Card 9162" (HDFC Card format - just 4 digits after Card)
      RegExp(r'(?:card)\s*(?:no\.?|num\.?)?\s*(\d{4})\b', caseSensitive: false),
      // Pattern 3: "from x9295" or "x9295" (Jio format - x followed by 4 digits)
      RegExp(r'(?:from\s+)?[xX](\d{4})\b', caseSensitive: false),
      // Pattern 4: "*1651" standalone (masked account)
      RegExp(r'\*(\d{4})\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static String? _extractRefId(String body) {
    final patterns = [
      // Pattern 1: "Txn ID: 322438863654" (Airtel format)
      RegExp(r'(?:txn\s*id)[:\s]+(\d{10,15})', caseSensitive: false),
      // Pattern 2: "ref.:", "txn.:", "utr", "rrn" followed by alphanumeric
      RegExp(
        r'(?:ref\.?|txn\.?|utr|rrn)[:\s#]+([A-Z0-9]{8,22})',
        caseSensitive: false,
      ),
      // Pattern 3: "by UPI 119184082771" (HDFC Card format)
      RegExp(r'by\s+UPI\s+(\d{9,15})', caseSensitive: false),
      // Pattern 4: "Ref 179775436288" (HDFC UPI format - no colon)
      RegExp(r'(?:^|\s)Ref\s+(\d{9,15})', caseSensitive: false),
      // Pattern 5: "Info: UPI/DR/299922204562/..." (Jio format)
      RegExp(r'Info:\s*UPI/(?:DR|CR)/(\d{9,15})/', caseSensitive: false),
      // Pattern 6: Standard UPI reference
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
      caseSensitive: false,
    ).firstMatch(body);
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
}
