// lib/services/ai_account_discovery_service.dart

import 'dart:convert';
import 'dart:math';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../models/sender_mapping.dart';
import 'ai_sms_parser.dart';
import 'local_storage_service.dart';

/// Result of AI-powered account discovery
class AccountDiscoveryResult {
  final List<DiscoveredAccount> discoveredAccounts;
  final List<ParsedTransaction> parsedTransactions;
  final String? error;

  AccountDiscoveryResult({
    required this.discoveredAccounts,
    required this.parsedTransactions,
    this.error,
  });

  int get totalAccounts => discoveredAccounts.length;
  int get bankAccounts =>
      discoveredAccounts.where((a) => a.type == AccountType.bankAccount).length;
  int get creditCards =>
      discoveredAccounts.where((a) => a.type == AccountType.creditCard).length;
  int get wallets =>
      discoveredAccounts.where((a) => a.type == AccountType.wallet).length;

  bool get hasAccounts => discoveredAccounts.isNotEmpty;
  bool get hasError => error != null;
}

/// Account discovered by AI analysis
class DiscoveredAccount {
  final String id;
  String name;
  AccountType type;
  String? bankName;
  String? last4Digits;
  String? cardNetwork;
  final List<String> senderIds;
  final int messageCount;
  bool isSelected; // For user confirmation UI

  DiscoveredAccount({
    required this.id,
    required this.name,
    required this.type,
    this.bankName,
    this.last4Digits,
    this.cardNetwork,
    required this.senderIds,
    required this.messageCount,
    this.isSelected = true,
  });

  Account toAccount() {
    return Account(
      id: id,
      name: name,
      type: type,
      bankName: bankName,
      last4Digits: last4Digits,
      cardNetwork: cardNetwork,
      isManuallyAdded: false,
    );
  }

  List<SenderMapping> toSenderMappings() {
    return senderIds.map((senderId) {
      return SenderMapping(
        id: 'mapping_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}',
        senderId: senderId,
        accountId: id,
        createdAt: DateTime.now(),
        isUserAssigned: false,
      );
    }).toList();
  }
}

/// Transaction parsed by AI with account context
class ParsedTransaction {
  final String smsId;
  final String senderId;
  final String rawMessage;
  final DateTime date;
  final double amount;
  final TransactionType type;
  final PaymentSource source;
  final String? merchant;
  final String? accountLast4;
  final String? referenceId;
  final double? balance;
  final String? accountId;
  final TransactionCategory? category;

  ParsedTransaction({
    required this.smsId,
    required this.senderId,
    required this.rawMessage,
    required this.date,
    required this.amount,
    required this.type,
    required this.source,
    this.merchant,
    this.accountLast4,
    this.referenceId,
    this.balance,
    this.accountId,
    this.category,
  });

  Transaction toTransaction(String accountName) {
    return Transaction(
      id: smsId,
      amount: amount,
      type: type,
      source: source,
      sender: accountName,
      merchant: merchant,
      accountLast4: accountLast4,
      date: date,
      rawMessage: rawMessage,
      referenceId: referenceId,
      balance: balance,
      accountId: accountId,
      category: category,
    );
  }
}

/// AI-powered account discovery service using Google Gemini
class AiAccountDiscoveryService {
  static GenerativeModel? _model;
  static bool _isInitialized = false;

  /// Batch size for API calls (balance between context and token limits)
  static const int _batchSize = 30;

  /// Maximum sample messages per sender for discovery
  static const int _maxSamplesPerSender = 5;

  /// Initialize with Gemini API key
  static Future<void> initialize(String apiKey) async {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );
    _isInitialized = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', apiKey);
  }

  /// Load saved API key
  static Future<bool> loadSavedApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('gemini_api_key');
    if (savedKey != null && savedKey.isNotEmpty) {
      await initialize(savedKey);
      return true;
    }
    return false;
  }

  static bool get isInitialized => _isInitialized;

  /// Discover accounts from SMS messages using AI
  static Future<AccountDiscoveryResult> discoverAccounts({
    required List<Map<String, dynamic>> smsMessages,
    required DateTime fromDate,
  }) async {
    // Ensure AI is initialized
    if (!_isInitialized || _model == null) {
      final loaded = await loadSavedApiKey();
      if (!loaded) {
        return AccountDiscoveryResult(
          discoveredAccounts: [],
          parsedTransactions: [],
          error: 'Gemini API key not configured. Please set up your API key.',
        );
      }
    }

    try {
      // Step 1: Filter and group messages by sender
      final groupedMessages = _groupMessagesBySender(smsMessages);

      if (groupedMessages.isEmpty) {
        return AccountDiscoveryResult(
          discoveredAccounts: [],
          parsedTransactions: [],
          error: 'No financial messages found in the selected period.',
        );
      }

      // Step 2: Discover accounts using AI
      final discoveryPrompt = _buildDiscoveryPrompt(groupedMessages);
      final discoveryResponse =
          await _model!.generateContent([Content.text(discoveryPrompt)]);
      final discoveryText = discoveryResponse.text;

      if (discoveryText == null || discoveryText.isEmpty) {
        return AccountDiscoveryResult(
          discoveredAccounts: [],
          parsedTransactions: [],
          error: 'AI did not return a valid response for account discovery.',
        );
      }

      // Step 3: Parse discovered accounts
      final accounts = _parseDiscoveryResponse(discoveryText, groupedMessages);

      // Step 4: Parse transactions with account context
      final transactions = await _parseTransactionsWithContext(
        smsMessages: smsMessages,
        discoveredAccounts: accounts,
      );

      return AccountDiscoveryResult(
        discoveredAccounts: accounts,
        parsedTransactions: transactions,
      );
    } catch (e) {
      return AccountDiscoveryResult(
        discoveredAccounts: [],
        parsedTransactions: [],
        error: 'AI analysis failed: ${e.toString()}',
      );
    }
  }

  /// Group messages by sender ID, filtering for financial SMS
  static Map<String, List<Map<String, dynamic>>> _groupMessagesBySender(
      List<Map<String, dynamic>> messages) {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final msg in messages) {
      final body = msg['body'] as String? ?? '';
      final sender = msg['sender'] as String? ?? '';

      // Quick filter for financial messages
      if (!AiSmsParser.mightBeTransaction(body)) continue;

      // Clean sender ID (remove prefixes like "DM-", "AD-")
      final cleanSender = _cleanSender(sender);
      if (cleanSender.isEmpty) continue;

      if (!grouped.containsKey(cleanSender)) {
        grouped[cleanSender] = [];
      }
      grouped[cleanSender]!.add(msg);
    }

    return grouped;
  }

  /// Clean sender ID by removing common prefixes
  static String _cleanSender(String sender) {
    return sender.replaceAll(RegExp(r'^[A-Z]{2}-'), '').toUpperCase();
  }

  /// Build the AI prompt for account discovery
  static String _buildDiscoveryPrompt(
      Map<String, List<Map<String, dynamic>>> groupedMessages) {
    final buffer = StringBuffer();

    buffer.writeln('''
Analyze these SMS messages from my phone to identify all my financial accounts (bank accounts, credit cards, wallets).

For each unique account you find, extract:
- Account name (e.g., "HDFC Savings Account", "ICICI Credit Card")
- Account type: "bank_account", "credit_card", or "wallet"
- Bank name (e.g., "HDFC Bank", "ICICI Bank")
- Last 4 digits of account/card number if mentioned
- Card network (Visa/Mastercard/Rupay) for credit cards if mentioned
- All SMS sender IDs that belong to this account

IMPORTANT:
- Multiple sender IDs can belong to the same account (e.g., HDFCBK, HDFCBANK, HDFCALERT all = HDFC Bank)
- Same bank can have multiple accounts (e.g., HDFC Savings and HDFC Credit Card are separate)
- Identify accounts by the last 4 digits mentioned in messages
- If a sender sends both credit and debit messages, determine the account type from context

MESSAGES BY SENDER:
''');

    // Add sample messages grouped by sender
    for (final entry in groupedMessages.entries) {
      final senderId = entry.key;
      final messages = entry.value;

      buffer.writeln('\n[SENDER: $senderId] (${messages.length} messages)');

      // Take sample messages
      final samples = messages.take(_maxSamplesPerSender);
      for (final msg in samples) {
        final body = (msg['body'] as String? ?? '').replaceAll('\n', ' ');
        // Truncate long messages
        final truncated = body.length > 200 ? '${body.substring(0, 200)}...' : body;
        buffer.writeln('- "$truncated"');
      }
    }

    buffer.writeln('''

---
Return ONLY valid JSON (no markdown, no explanation):
{
  "accounts": [
    {
      "name": "Account Name",
      "type": "bank_account" | "credit_card" | "wallet",
      "bank_name": "Bank Name",
      "last4_digits": "1234" or null,
      "card_network": "Visa" | "Mastercard" | "Rupay" or null,
      "sender_ids": ["SENDER1", "SENDER2"]
    }
  ]
}
''');

    return buffer.toString();
  }

  /// Parse the AI response into DiscoveredAccount objects
  static List<DiscoveredAccount> _parseDiscoveryResponse(
      String responseText, Map<String, List<Map<String, dynamic>>> groupedMessages) {
    // Clean up response (remove markdown code blocks if present)
    String jsonStr = responseText.trim();
    if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr.replaceAll(RegExp(r'^```\w*\n?'), '');
      jsonStr = jsonStr.replaceAll(RegExp(r'\n?```$'), '');
    }

    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final accountsData = data['accounts'] as List<dynamic>? ?? [];
      final accounts = <DiscoveredAccount>[];

      for (int i = 0; i < accountsData.length; i++) {
        final acc = accountsData[i] as Map<String, dynamic>;
        final senderIds =
            (acc['sender_ids'] as List<dynamic>?)?.cast<String>() ?? [];

        // Count messages for this account
        int messageCount = 0;
        for (final senderId in senderIds) {
          messageCount += groupedMessages[senderId]?.length ?? 0;
        }

        // Skip accounts with no messages
        if (messageCount == 0) continue;

        // Parse account type
        final typeStr = acc['type'] as String? ?? 'bank_account';
        AccountType type;
        switch (typeStr.toLowerCase()) {
          case 'credit_card':
            type = AccountType.creditCard;
            break;
          case 'wallet':
            type = AccountType.wallet;
            break;
          default:
            type = AccountType.bankAccount;
        }

        accounts.add(DiscoveredAccount(
          id: 'account_ai_${DateTime.now().millisecondsSinceEpoch}_$i',
          name: acc['name'] as String? ?? 'Unknown Account',
          type: type,
          bankName: acc['bank_name'] as String?,
          last4Digits: acc['last4_digits'] as String?,
          cardNetwork: acc['card_network'] as String?,
          senderIds: senderIds,
          messageCount: messageCount,
        ));
      }

      return accounts;
    } catch (e) {
      // If parsing fails, return empty list
      return [];
    }
  }

  /// Parse all transactions with account context
  static Future<List<ParsedTransaction>> _parseTransactionsWithContext({
    required List<Map<String, dynamic>> smsMessages,
    required List<DiscoveredAccount> discoveredAccounts,
  }) async {
    final transactions = <ParsedTransaction>[];

    // Create sender to account mapping
    final senderToAccount = <String, DiscoveredAccount>{};
    for (final account in discoveredAccounts) {
      for (final senderId in account.senderIds) {
        senderToAccount[senderId] = account;
      }
    }

    // Filter financial messages
    final financialMessages = smsMessages
        .where((msg) => AiSmsParser.mightBeTransaction(msg['body'] as String? ?? ''))
        .toList();

    // Process in batches
    for (int i = 0; i < financialMessages.length; i += _batchSize) {
      final batch = financialMessages.skip(i).take(_batchSize).toList();
      final batchTransactions = await _parseTransactionBatch(
        batch,
        senderToAccount,
        discoveredAccounts,
      );
      transactions.addAll(batchTransactions);
    }

    return transactions;
  }

  /// Parse a batch of transactions using AI
  static Future<List<ParsedTransaction>> _parseTransactionBatch(
    List<Map<String, dynamic>> messages,
    Map<String, DiscoveredAccount> senderToAccount,
    List<DiscoveredAccount> allAccounts,
  ) async {
    final transactions = <ParsedTransaction>[];

    // Build account context for the prompt
    final accountContext = allAccounts
        .map((a) => '${a.name} (${a.type.name}, senders: ${a.senderIds.join(", ")})')
        .join('\n');

    final prompt = '''
Parse these SMS messages into transactions. I have the following accounts:
$accountContext

For each SMS, extract:
- type: "credit" (money received) or "debit" (money spent/sent)
- amount: numeric value
- source: "upi", "card", "bank", or "wallet"
- merchant: merchant/payee name for debits, sender name for credits (or null)
- account_last4: last 4 digits of account/card mentioned
- reference_id: transaction reference/UTR/RRN if present
- balance: available balance after transaction if mentioned
- category: one of [food_dining, travel_transport, shopping, rent_housing, emi_loans, entertainment, bills_utilities, health_medical, education, salary_income, transfer, cashback, investment, other]

MESSAGES:
${messages.map((m) => '{"id": "${m['id']}", "sender": "${_cleanSender(m['sender'] as String? ?? '')}", "body": "${(m['body'] as String? ?? '').replaceAll('"', '\\"').replaceAll('\n', ' ')}"}'
).join('\n')}

---
Return ONLY valid JSON array:
[
  {
    "id": "sms_id",
    "is_transaction": true/false,
    "type": "credit" | "debit",
    "amount": 1234.56,
    "source": "upi" | "card" | "bank" | "wallet",
    "merchant": "Name" or null,
    "account_last4": "1234" or null,
    "reference_id": "REF123" or null,
    "balance": 5678.90 or null,
    "category": "category_name" or null
  }
]
''';

    try {
      final response = await _model!.generateContent([Content.text(prompt)]);
      final text = response.text;

      if (text == null || text.isEmpty) return transactions;

      // Clean up response
      String jsonStr = text.trim();
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceAll(RegExp(r'^```\w*\n?'), '');
        jsonStr = jsonStr.replaceAll(RegExp(r'\n?```$'), '');
      }

      final parsedList = jsonDecode(jsonStr) as List<dynamic>;

      for (int i = 0; i < parsedList.length; i++) {
        final data = parsedList[i] as Map<String, dynamic>;
        if (data['is_transaction'] != true) continue;

        final msgId = data['id'] as String?;
        if (msgId == null) continue;

        // Find original message
        final originalMsg = messages.firstWhere(
          (m) => m['id'] == msgId,
          orElse: () => <String, dynamic>{},
        );
        if (originalMsg.isEmpty) continue;

        final sender = _cleanSender(originalMsg['sender'] as String? ?? '');
        final account = senderToAccount[sender];

        // Parse type
        final typeStr = data['type'] as String?;
        TransactionType type;
        if (typeStr == 'credit') {
          type = TransactionType.credit;
        } else if (typeStr == 'debit') {
          type = TransactionType.debit;
        } else {
          continue; // Skip unknown types
        }

        // Parse source
        final sourceStr = data['source'] as String? ?? 'bank';
        PaymentSource source;
        switch (sourceStr.toLowerCase()) {
          case 'upi':
            source = PaymentSource.upi;
            break;
          case 'card':
            source = PaymentSource.card;
            break;
          case 'wallet':
            source = PaymentSource.wallet;
            break;
          default:
            source = PaymentSource.bank;
        }

        // Parse category
        TransactionCategory? category;
        final categoryStr = data['category'] as String?;
        if (categoryStr != null) {
          category = _parseCategory(categoryStr);
        }

        final amount = (data['amount'] as num?)?.toDouble();
        if (amount == null || amount <= 0) continue;

        transactions.add(ParsedTransaction(
          smsId: msgId,
          senderId: sender,
          rawMessage: originalMsg['body'] as String? ?? '',
          date: originalMsg['date'] as DateTime? ?? DateTime.now(),
          amount: amount,
          type: type,
          source: source,
          merchant: data['merchant'] as String?,
          accountLast4: data['account_last4'] as String?,
          referenceId: data['reference_id'] as String?,
          balance: (data['balance'] as num?)?.toDouble(),
          accountId: account?.id,
          category: category,
        ));
      }
    } catch (e) {
      // On error, return what we have so far
    }

    return transactions;
  }

  /// Parse category string to enum
  static TransactionCategory? _parseCategory(String categoryStr) {
    final normalized = categoryStr.toLowerCase().replaceAll('_', '');
    switch (normalized) {
      case 'fooddining':
      case 'food':
        return TransactionCategory.foodDining;
      case 'traveltransport':
      case 'travel':
        return TransactionCategory.travelTransport;
      case 'shopping':
        return TransactionCategory.shopping;
      case 'renthousing':
      case 'rent':
        return TransactionCategory.rentHousing;
      case 'emiloans':
      case 'emi':
        return TransactionCategory.emiLoans;
      case 'entertainment':
        return TransactionCategory.entertainment;
      case 'billsutilities':
      case 'bills':
        return TransactionCategory.billsUtilities;
      case 'healthmedical':
      case 'health':
        return TransactionCategory.healthMedical;
      case 'education':
        return TransactionCategory.education;
      case 'salaryincome':
      case 'salary':
        return TransactionCategory.salaryIncome;
      case 'transfer':
        return TransactionCategory.transfer;
      case 'cashback':
        return TransactionCategory.cashback;
      case 'investment':
        return TransactionCategory.investment;
      default:
        return TransactionCategory.other;
    }
  }

  /// Save confirmed accounts and their mappings to database
  static Future<void> saveConfirmedAccounts(
      List<DiscoveredAccount> confirmedAccounts) async {
    for (final discovered in confirmedAccounts) {
      if (!discovered.isSelected) continue;

      // Save account
      final account = discovered.toAccount();
      await LocalStorageService.saveAccount(account);

      // Save sender mappings
      final mappings = discovered.toSenderMappings();
      for (final mapping in mappings) {
        await LocalStorageService.saveSenderMapping(mapping);
      }
    }
  }

  /// Save parsed transactions to database
  static Future<void> saveTransactions(
    List<ParsedTransaction> transactions,
    Map<String, String> senderToAccountName,
  ) async {
    for (final parsed in transactions) {
      final accountName = senderToAccountName[parsed.senderId] ?? parsed.senderId;
      final transaction = parsed.toTransaction(accountName);
      await LocalStorageService.saveTransaction(transaction);
    }
  }
}
