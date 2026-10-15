import '../models/transaction.dart';
import '../models/transaction_review.dart';

class CategoryAssignment {
  const CategoryAssignment(this.categoryId, this.source);
  final String? categoryId;
  final String? source;
}

class RuleCategoryChange {
  const RuleCategoryChange({
    required this.transactionId,
    required this.merchant,
    required this.oldCategoryId,
    required this.assignment,
  });
  final String transactionId;
  final String merchant;
  final String? oldCategoryId;
  final CategoryAssignment assignment;
}

/// Only rules explicitly created by the user may assign categories.
class CategoryService {
  static MerchantRule? matchingMerchantRule(
    Iterable<MerchantRule> rules,
    String rawMessage,
  ) {
    final message = rawMessage.toLowerCase();
    MerchantRule? best;
    for (final rule in rules) {
      if (!rule.isEnabled ||
          rule.matchText.trim().isEmpty ||
          !message.contains(rule.matchText.toLowerCase())) {
        continue;
      }
      if (best == null ||
          rule.matchText.length > best.matchText.length ||
          (rule.matchText.length == best.matchText.length &&
              rule.createdAt.isAfter(best.createdAt))) {
        best = rule;
      }
    }
    return best;
  }

  static CategoryAssignment assign(
    Transaction transaction, {
    MerchantRule? merchantRule,
  }) {
    if (merchantRule?.categoryId != null) {
      return CategoryAssignment(merchantRule!.categoryId, 'merchant_rule');
    }
    return const CategoryAssignment(null, null);
  }
}
