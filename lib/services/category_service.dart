// lib/services/category_service.dart

import '../models/transaction.dart';

/// Auto-categorizes transactions based on merchant names and message content.
class CategoryService {
  static const String dailyTransactionsCategoryId = 'daily_transactions';
  static const _airtelBankKeywords = [
    'airtel payments bank',
    'airtel bank',
    'airtel',
    'atbank',
    'airbnk',
    'airbks',
    'artlpy',
  ];

  static const _merchantKeywords = <TransactionCategory, List<String>>{
    TransactionCategory.foodDining: [
      'swiggy',
      'zomato',
      'uber eats',
      'dominos',
      'pizza hut',
      'mcdonald',
      'kfc',
      'starbucks',
      'cafe coffee',
      'restaurant',
      'biryani',
      'burger',
      'subway',
      'dunkin',
      'baskin',
      'haldiram',
      'barbeque nation',
      'chai',
      'tea post',
      'coffee',
      'bakery',
      'sweet',
      'juice',
      'dairy',
      'food',
      'dine',
      'eat',
      'meal',
      'kitchen',
      'dhaba',
      'hotel',
      'canteen',
      'mess',
      'tiffin',
      'thali',
      'pav bhaji',
      'dosa',
      'idli',
      'paneer',
      'chicken',
      'fish',
      'mutton',
      'ice cream',
      'gelato',
      'brownie',
      'cake',
      'biscuit',
      'snack',
      'maggi',
      'noodle',
      'chowmein',
      'blinkit',
      'zepto',
      'instamart',
      'bigbasket',
      'grofers',
      'dmart',
      'more supermarket',
      'reliance fresh',
    ],
    TransactionCategory.travelTransport: [
      'uber',
      'ola',
      'rapido',
      'irctc',
      'makemytrip',
      'goibibo',
      'yatra',
      'cleartrip',
      'ixigo',
      'flight',
      'airline',
      'indigo',
      'spicejet',
      'air india',
      'vistara',
      'bus',
      'metro',
      'taxi',
      'cab',
      'auto',
      'petrol',
      'diesel',
      'fuel',
      'hp pump',
      'indian oil',
      'bharat petro',
      'parking',
      'toll',
      'fastag',
      'railway',
      'train',
      'booking.com',
      'oyo',
      'airbnb',
      'hostel',
      'treebo',
      'fabhotel',
    ],
    TransactionCategory.shopping: [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'meesho',
      'nykaa',
      'tata cliq',
      'snapdeal',
      'shoppers stop',
      'lifestyle',
      'westside',
      'zara',
      'h&m',
      'uniqlo',
      'decathlon',
      'croma',
      'reliance digital',
      'vijay sales',
      'mall',
      'store',
      'market',
      'bazaar',
      'shop',
      'mart',
      'retail',
      'electronics',
      'mobile',
      'phone',
      'laptop',
      'cloth',
      'fashion',
      'shoe',
      'watch',
      'jewel',
      'gold',
      'silver',
      'diamond',
    ],
    TransactionCategory.rentHousing: [
      'rent',
      'housing',
      'landlord',
      'pg ',
      'paying guest',
      'flat',
      'apartment',
      'society',
      'maintenance',
      'property',
      'broker',
      'nobroker',
      'magicbricks',
      '99acres',
    ],
    TransactionCategory.emiLoans: [
      'emi',
      'loan',
      'lending',
      'bajaj finserv',
      'bajaj finance',
      'hdfc ltd',
      'capital first',
      'home credit',
      'zestmoney',
      'simpl',
      'lazypay',
      'postpe',
      'pay later',
      'installment',
      'flexi pay',
      'credit card payment',
      'card bill',
      'min due',
      'minimum due',
    ],
    TransactionCategory.entertainment: [
      'netflix',
      'hotstar',
      'prime video',
      'disney',
      'spotify',
      'gaana',
      'youtube premium',
      'apple music',
      'bookmyshow',
      'pvr',
      'inox',
      'cinepolis',
      'game',
      'gaming',
      'playstation',
      'xbox',
      'steam',
      'dream11',
      'mpl',
      'winzo',
      'jio cinema',
      'zee5',
      'sonyliv',
      'voot',
      'aha',
      'altbalaji',
      'mx player',
    ],
    TransactionCategory.billsUtilities: [
      'electricity',
      'bescom',
      'tata power',
      'adani electricity',
      'water bill',
      'gas bill',
      'dth',
      'tata sky',
      'dish tv',
      'broadband',
      'wifi',
      'internet',
      'recharge',
      'jio',
      'airtel',
      'vi ',
      'vodafone',
      'idea ',
      'bsnl',
      'postpaid',
      'prepaid',
      'bill payment',
      'utility',
      'municipal',
      'insurance premium',
      'lic',
      'health insurance',
      'car insurance',
    ],
    TransactionCategory.healthMedical: [
      'pharma',
      'pharmacy',
      'medical',
      'hospital',
      'clinic',
      '1mg',
      'netmeds',
      'pharmeasy',
      'practo',
      'doctor',
      'dental',
      'eye',
      'lab',
      'diagnostic',
      'pathology',
      'ayurveda',
      'homeopathy',
      'apollo',
      'fortis',
      'max hospital',
      'manipal',
      'medplus',
      'wellness',
      'gym',
      'fitness',
      'cult.fit',
      'healthify',
    ],
    TransactionCategory.education: [
      'coursera',
      'udemy',
      'unacademy',
      'byjus',
      'school',
      'college',
      'university',
      'tuition',
      'coaching',
      'upgrad',
      'simplilearn',
      'edureka',
      'pluralsight',
      'linkedin learning',
      'skillshare',
      'exam',
      'test',
      'certification',
      'book',
      'stationery',
    ],
    TransactionCategory.investment: [
      'zerodha',
      'groww',
      'kite',
      'upstox',
      'angel one',
      'mutual fund',
      'sip ',
      'nps ',
      'ppf',
      'fixed deposit',
      'fd ',
      'rd ',
      'stock',
      'share',
      'demat',
      'trading',
      'smallcase',
      'coin',
      'etmoney',
      'paytm money',
      'kuvera',
      'vested',
    ],
    TransactionCategory.transfer: [
      'neft',
      'imps',
      'rtgs',
      'transfer',
      'fund transfer',
      'self transfer',
      'own account',
      'a/c to a/c',
    ],
    TransactionCategory.cashback: [
      'cashback',
      'reward',
      'refund',
      'reversal',
      'reversed',
    ],
  };

  /// Categorize a transaction based on merchant name and SMS content.
  static TransactionCategory categorize(Transaction tx) {
    // Already manually categorized
    if (tx.category != null &&
        tx.category != TransactionCategory.uncategorized) {
      return tx.category!;
    }

    // Salary
    if (tx.isSalary || tx.type == TransactionType.credit) {
      if (tx.isSalary) return TransactionCategory.salaryIncome;
    }

    final name = (tx.merchant ?? tx.sender).toLowerCase();
    final raw = tx.rawMessage.toLowerCase();
    final searchText = '$name $raw';

    for (final entry in _merchantKeywords.entries) {
      for (final keyword in entry.value) {
        if (searchText.contains(keyword)) {
          return entry.key;
        }
      }
    }

    // Credits default to 'other', debits to 'uncategorized'
    return tx.isCredit
        ? TransactionCategory.other
        : TransactionCategory.uncategorized;
  }

  /// Returns the standard category ID to store for a transaction.
  static String categorizeStandardCategoryId(Transaction tx) {
    if (_isAirtelBankTransaction(tx)) {
      return dailyTransactionsCategoryId;
    }

    return categorize(tx).standardCategoryId;
  }

  static bool _isAirtelBankTransaction(Transaction tx) {
    final merchant = tx.merchant?.toLowerCase() ?? '';
    final sender = tx.sender.toLowerCase();
    final raw = tx.rawMessage.toLowerCase();
    final searchText = '$merchant $sender $raw';

    return _airtelBankKeywords.any(searchText.contains);
  }

  /// Categorize a list of transactions in place.
  static List<Transaction> categorizeAll(List<Transaction> transactions) {
    return transactions.map((tx) {
      final cat = categorize(tx);
      return tx.copyWith(category: cat);
    }).toList();
  }
}
