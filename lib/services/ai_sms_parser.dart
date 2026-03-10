// lib/services/ai_sms_parser.dart

import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction.dart';
import 'sms_parser.dart';

/// AI-powered SMS parser using Google Gemini
/// Falls back to rule-based parsing when AI is unavailable
class AiSmsParser {
  static GenerativeModel? _model;
  static bool _isInitialized = false;
  
  /// Initialize with your Gemini API key
  /// Get your key at: https://aistudio.google.com/app/apikey
  static Future<void> initialize(String apiKey) async {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash', // Fast and cost-effective
      apiKey: apiKey,
    );
    _isInitialized = true;
    
    // Save API key for future use
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
  
  /// Parse SMS using AI with fallback to rule-based parsing
  static Future<Transaction?> parse(
    String body,
    String sender,
    DateTime date,
    String id,
  ) async {
    // Try AI parsing first if available
    if (_isInitialized && _model != null) {
      try {
        final aiResult = await _parseWithAI(body, sender, date, id);
        if (aiResult != null) return aiResult;
      } catch (e) {
        // AI failed, fall back to rule-based
        print('AI parsing failed: $e');
      }
    }
    
    // Fallback to rule-based parsing
    return SmsParser.parse(body, sender, date, id);
  }
  
  /// Parse SMS using Gemini AI
  static Future<Transaction?> _parseWithAI(
    String body,
    String sender,
    DateTime date,
    String id,
  ) async {
    final prompt = '''
Analyze this SMS and extract transaction details. Return ONLY valid JSON (no markdown, no explanation).

SMS from "$sender":
"$body"

If this is a financial transaction (bank alert, UPI, wallet, payment), extract:
{
  "is_transaction": true,
  "type": "credit" or "debit",
  "amount": <number>,
  "source": "upi" or "card" or "bank" or "wallet",
  "merchant": "<merchant/sender name or null>",
  "account_last4": "<last 4 digits of account/card or null>",
  "reference_id": "<transaction reference or null>",
  "balance": <available balance after transaction or null>
}

If NOT a financial transaction:
{"is_transaction": false}

Rules:
- Amount must be a number (no currency symbols)
- type is "credit" for money received, "debit" for money spent/sent
- Include merchant name for debit, sender name for credit
- Extract reference/UTR/transaction ID if present''';

    final response = await _model!.generateContent([Content.text(prompt)]);
    final text = response.text;
    
    if (text == null || text.isEmpty) return null;
    
    // Clean up response (remove markdown code blocks if present)
    String jsonStr = text.trim();
    if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr.replaceAll(RegExp(r'^```\w*\n?'), '');
      jsonStr = jsonStr.replaceAll(RegExp(r'\n?```$'), '');
    }
    
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      if (data['is_transaction'] != true) return null;
      
      final typeStr = data['type'] as String?;
      final amount = (data['amount'] as num?)?.toDouble();
      
      if (typeStr == null || amount == null || amount <= 0) return null;
      
      final type = typeStr == 'credit' 
          ? TransactionType.credit 
          : TransactionType.debit;
      
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
      
      return Transaction(
        id: id,
        amount: amount,
        type: type,
        source: source,
        sender: _cleanSender(sender),
        merchant: data['merchant'] as String?,
        accountLast4: data['account_last4'] as String?,
        date: date,
        rawMessage: body,
        referenceId: data['reference_id'] as String?,
        balance: (data['balance'] as num?)?.toDouble(),
      );
    } catch (e) {
      print('Failed to parse AI response: $e');
      return null;
    }
  }
  
  static String _cleanSender(String sender) {
    return sender.replaceAll(RegExp(r'^[A-Z]{2}-'), '');
  }
  
  /// Check if SMS might be a transaction (quick pre-filter)
  static bool mightBeTransaction(String body) {
    final lower = body.toLowerCase();
    return lower.contains('rs') ||
        lower.contains('inr') ||
        lower.contains('₹') ||
        lower.contains('credited') ||
        lower.contains('debited') ||
        lower.contains('payment') ||
        lower.contains('upi') ||
        lower.contains('transferred') ||
        lower.contains('received') ||
        lower.contains('balance');
  }
  
  /// Batch parse multiple SMS messages efficiently
  static Future<List<Transaction>> parseBatch(
    List<Map<String, dynamic>> messages,
  ) async {
    final transactions = <Transaction>[];
    
    for (final msg in messages) {
      final body = msg['body'] as String;
      final sender = msg['sender'] as String;
      final date = msg['date'] as DateTime;
      final id = msg['id'] as String;
      
      // Quick filter before expensive AI call
      if (!mightBeTransaction(body)) continue;
      
      final tx = await parse(body, sender, date, id);
      if (tx != null) transactions.add(tx);
    }
    
    return transactions;
  }
}
