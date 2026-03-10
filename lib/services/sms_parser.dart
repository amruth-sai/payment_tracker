// lib/services/sms_parser.dart

import '../models/transaction.dart';

class SmsParser {
  // Known bank/payment sender IDs
  static const _knownSenders = [
    // Traditional Banks
    'HDFCBK', 'SBIINB', 'ICICIB', 'AXISBK', 'KOTAKB', 'PNBSMS',
    'BOIIND', 'CANBNK', 'UNIONB', 'INDUSB', 'YESBK', 'IDBIBK',
    'HSBC', 'SCBNK', 'CITIBK', 'RBLBNK', 'FEDRAL',
    
    // Telecom & Digital Banks
    'AIRTEL', 'ARTLPY', 'ATBANK', 'AIRBNK',  // Airtel Payments Bank
    'JIOPAY', 'JIOMNY', 'JIOFIN', 'JIOBNK',  // Jio Payments / Jio Finance
    
    // UPI & Wallets  
    'PAYTM', 'GPAY', 'PHONEPE', 'AMAZONPAY', 'MOBIKWIK',
    'BHIMUPI', 'UPIPAY',
    
    // Fintech & Neo-banks
    'CREDCLUB', 'SLICE', 'JUPITER', 'FININ', 'FIAPP',
    'NIYOBNK', 'OPENBNK', 'RAZORPY',
    
    // Others
    'ATMMSG', 'TXNALRT', 'ALERTS',
  ];

  static bool isBankSms(String sender) {
    final s = sender.toUpperCase();
    return _knownSenders.any((k) => s.contains(k)) ||
        RegExp(r'^[A-Z]{2}-[A-Z]{6}$').hasMatch(sender); // DM-HDFCBK format
  }

  static Transaction? parse(String body, String sender, DateTime date, String id) {
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

    final type = _detectType(body);
    if (type == TransactionType.unknown) return null;

    return Transaction(
      id: id,
      amount: amount,
      type: type,
      source: _detectSource(body, sender),
      sender: _cleanSender(sender),
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
      RegExp(r'(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      RegExp(r'(?:amount|amt)[:\s]+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      RegExp(r'([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:rs|inr|₹)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final str = match.group(1)!.replaceAll(',', '');
        final val = double.tryParse(str);
        if (val != null && val > 0 && val < 10000000) return val; // sanity: < 1 crore
      }
    }
    return null;
  }

  static TransactionType _detectType(String body) {
    final lower = body.toLowerCase();

    final creditWords = [
      'credited', 'received', 'credit', 'deposited',
      'added', 'received from', 'money added', 'cashback',
      'refund', 'reversed', 'reversal',
    ];
    final debitWords = [
      'debited', 'spent', 'debit', 'payment', 'paid',
      'withdrawn', 'transferred to', 'purchase', 'charged',
      'used at', 'sent to', 'transaction at',
    ];

    bool hasCredit = creditWords.any((w) => lower.contains(w));
    bool hasDebit = debitWords.any((w) => lower.contains(w));

    if (hasCredit && !hasDebit) return TransactionType.credit;
    if (hasDebit && !hasCredit) return TransactionType.debit;
    // Both or neither – try positional heuristic
    if (hasCredit) return TransactionType.credit;
    if (hasDebit) return TransactionType.debit;
    return TransactionType.unknown;
  }

  static PaymentSource _detectSource(String body, String sender) {
    final lower = body.toLowerCase();
    final s = sender.toUpperCase();

    if (lower.contains('upi') || s.contains('PAYTM') || s.contains('GPAY') || s.contains('PHONEPE')) {
      return PaymentSource.upi;
    }
    if (lower.contains('credit card') || lower.contains('debit card') || lower.contains('card no')) {
      return PaymentSource.card;
    }
    if (lower.contains('wallet') || s.contains('MOBIKWIK') || s.contains('AMAZONPAY')) {
      return PaymentSource.wallet;
    }
    return PaymentSource.bank;
  }

  static String? _extractMerchant(String body, TransactionType type) {
    if (type == TransactionType.debit) {
      // "at MERCHANT NAME" or "to VPA@bank"
      final atMatch = RegExp(r"(?:at|to)\s+([A-Z][A-Za-z0-9 &\-']+?)(?:\s+on|\s+via|\s+for|\s+ref|\.|,|$)", caseSensitive: false)
          .firstMatch(body);
      if (atMatch != null) {
        final name = atMatch.group(1)!.trim();
        if (name.length > 2 && name.length < 40) return name;
      }
    }
    if (type == TransactionType.credit) {
      final fromMatch = RegExp(r"(?:from|by)\s+([A-Z][A-Za-z0-9 &\-']+?)(?:\s+on|\s+via|\s+ref|\.|,|$)", caseSensitive: false)
          .firstMatch(body);
      if (fromMatch != null) {
        final name = fromMatch.group(1)!.trim();
        if (name.length > 2 && name.length < 40) return name;
      }
    }
    return null;
  }

  static String? _extractAccountLast4(String body) {
    final match = RegExp(r'(?:a/c|account|ac|card)\s*(?:no\.?|num\.?)?\s*[xX*]+(\d{4})', caseSensitive: false)
        .firstMatch(body);
    return match?.group(1);
  }

  static String? _extractRefId(String body) {
    final match = RegExp(r'(?:ref\.?|txn\.?|utr|rrn)[:\s#]+([A-Z0-9]{8,22})', caseSensitive: false)
        .firstMatch(body);
    return match?.group(1);
  }

  static double? _extractBalance(String body) {
    final match = RegExp(r'(?:bal(?:ance)?|avl\.?)[:\s]+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false)
        .firstMatch(body);
    if (match != null) {
      final str = match.group(1)!.replaceAll(',', '');
      return double.tryParse(str);
    }
    return null;
  }

  static String _cleanSender(String sender) {
    // "DM-HDFCBK" → "HDFCBK"
    return sender.replaceAll(RegExp(r'^[A-Z]{2}-'), '');
  }
}
