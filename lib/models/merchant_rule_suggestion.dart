import 'transaction_review.dart';

/// Optional merchant rules suggested from the transaction export.
/// They are stored as disabled rules so the user can review each one.
class MerchantRuleSuggestion {
  const MerchantRuleSuggestion({
    required this.id,
    required this.matchText,
    required this.merchant,
    required this.standardCategoryId,
    required this.reason,
  });

  final String id;
  final String matchText;
  final String merchant;
  final String standardCategoryId;
  final String reason;

  MerchantRule toRule(DateTime createdAt) => MerchantRule(
        id: id,
        matchText: matchText,
        merchant: merchant,
        standardCategoryId: standardCategoryId,
        createdAt: createdAt,
        isEnabled: false,
      );
}

class MerchantRuleSuggestions {
  static const all = <MerchantRuleSuggestion>[
    MerchantRuleSuggestion(
      id: 'suggested_bigtree',
      matchText: 'BIGTREEENTERTAINMENTPRI',
      merchant: 'BigTree Entertainment',
      standardCategoryId: 'fun_activities',
      reason:
          'Four matching exports were categorized as investments. Check the SMS before enabling.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_youtube',
      matchText: 'Youtube',
      merchant: 'YouTube',
      standardCategoryId: 'subscriptions',
      reason:
          'Use for recurring YouTube payments after checking the matching SMS.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_spotify',
      matchText: 'Spotify',
      merchant: 'Spotify',
      standardCategoryId: 'subscriptions',
      reason: 'The export has Spotify payments in more than one category.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_cred_club',
      matchText: 'CRED Club',
      merchant: 'CRED Club',
      standardCategoryId: 'credit_card_bills',
      reason: 'Enable only if matching messages are credit card bill payments.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_policy_bazaar',
      matchText: 'Policy Bazaar',
      merchant: 'Policy Bazaar',
      standardCategoryId: 'insurance',
      reason: 'Enable only if matching messages are insurance premiums.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_groww',
      matchText: 'GROWW INVEST TECH',
      merchant: 'Groww',
      standardCategoryId: 'long_term_investments',
      reason:
          'Eight exported payments used this investment merchant. Check credits separately.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_decathlon',
      matchText: 'DECATHLON',
      merchant: 'Decathlon',
      standardCategoryId: 'shopping',
      reason: 'Eight exported payments were already categorized as shopping.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_swiggy',
      matchText: 'Swiggy',
      merchant: 'Swiggy',
      standardCategoryId: 'food_dining',
      reason: 'Twenty-five exported merchant names contained Swiggy.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_compass_food',
      matchText: 'COMPASS INDIA FOOD SERVIC',
      merchant: 'Compass India Food Service',
      standardCategoryId: 'food_dining',
      reason: 'Six exported payments were categorized as food and dining.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_bookmyshow',
      matchText: 'BOOKMYSHOW',
      merchant: 'BookMyShow',
      standardCategoryId: 'fun_activities',
      reason:
          'Two exported payments used this merchant. Review the matching SMS.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_dineout',
      matchText: 'DINEOUT',
      merchant: 'Dineout',
      standardCategoryId: 'dining',
      reason: 'Two exported payments used this dining merchant.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_myntra',
      matchText: 'Myntra',
      merchant: 'Myntra',
      standardCategoryId: 'shopping',
      reason: 'Two exported payments were categorized as shopping.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_flipkart',
      matchText: 'Flipkart',
      merchant: 'Flipkart',
      standardCategoryId: 'shopping',
      reason: 'Two exported payments were categorized as shopping.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_blinkit',
      matchText: 'Blinkit',
      merchant: 'Blinkit',
      standardCategoryId: 'food_dining',
      reason: 'Two exported payments were categorized as food and dining.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_care_health_ins',
      matchText: 'CARE HEALTH INS',
      merchant: 'Care Health Insurance',
      standardCategoryId: 'insurance',
      reason:
          'Two exported payments were under loans. Confirm they are insurance premiums.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_indian_oil',
      matchText: 'Indian Oil Petrol Pump',
      merchant: 'Indian Oil Petrol Pump',
      standardCategoryId: 'fuel',
      reason: 'Review this fuel merchant before enabling.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_bp_petrol',
      matchText: 'BP Petrol Pump',
      merchant: 'BP Petrol Pump',
      standardCategoryId: 'fuel',
      reason: 'Review this fuel merchant before enabling.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_laxmi_filling',
      matchText: 'LAXMIKOUSALYAFILLING',
      merchant: 'Laxmi Kousalya Filling',
      standardCategoryId: 'fuel',
      reason:
          'Two exported payments were categorized as investments. Confirm fuel purchase.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_airbnb',
      matchText: 'Airbnb Payments India',
      merchant: 'Airbnb',
      standardCategoryId: 'travel_fuel',
      reason:
          'A travel payment appeared in the export. Check the matching SMS.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_medplus',
      matchText: 'medplus',
      merchant: 'MedPlus',
      standardCategoryId: 'health',
      reason:
          'A pharmacy payment appeared in the export. Check the matching SMS.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_apollo_pharmacy',
      matchText: 'apollopharmacy',
      merchant: 'Apollo Pharmacy',
      standardCategoryId: 'health',
      reason:
          'A pharmacy payment appeared in the export. Check the matching SMS.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_primark',
      matchText: 'PRIMARK',
      merchant: 'Primark',
      standardCategoryId: 'shopping',
      reason:
          'Two exported trip-period payments had no standard category. Verify these purchases.',
    ),
    MerchantRuleSuggestion(
      id: 'suggested_avolta',
      matchText: 'Avolta LHR',
      merchant: 'Avolta LHR',
      standardCategoryId: 'shopping',
      reason:
          'Two exported trip-period payments had no standard category. Verify these purchases.',
    ),
  ];

  static MerchantRuleSuggestion? byId(String id) {
    for (final suggestion in all) {
      if (suggestion.id == id) return suggestion;
    }
    return null;
  }
}
