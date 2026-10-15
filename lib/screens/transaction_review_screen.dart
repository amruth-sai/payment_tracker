import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/app_category.dart';
import '../models/transaction.dart';
import '../models/transaction_review.dart';
import '../services/local_storage_service.dart';
import '../services/sms_parser.dart';
import '../services/sms_service.dart';
import '../utils/format_utils.dart';
import 'categories_screen.dart';

class TransactionReviewScreen extends StatefulWidget {
  const TransactionReviewScreen({super.key});

  @override
  State<TransactionReviewScreen> createState() =>
      _TransactionReviewScreenState();
}

class _TransactionReviewScreenState extends State<TransactionReviewScreen> {
  static const _uuid = Uuid();

  List<TransactionReview> _reviews = const [];
  List<AppCategory> _categories = const [];
  final Set<String> _savingReviewIds = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        LocalStorageService.getTransactionReviews(),
        LocalStorageService.getAllCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews = results[0] as List<TransactionReview>;
        _categories = results[1] as List<AppCategory>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load transactions that need review.';
        _isLoading = false;
      });
    }
  }

  Future<void> _resolve(TransactionReview review, TransactionType type) async {
    _setSaving(review.id, true);
    try {
      final transaction = await SmsParser.transactionFromReview(review, type);
      await LocalStorageService.resolveTransactionReview(
        review.id,
        transaction,
      );
      if (!mounted) return;
      setState(
        () =>
            _reviews = _reviews.where((item) => item.id != review.id).toList(),
      );
      await context.read<SmsService>().reloadFromCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${type == TransactionType.debit ? 'Debit' : 'Credit'} saved.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save this transaction.')),
      );
    } finally {
      _setSaving(review.id, false);
    }
  }

  Future<void> _ignore(TransactionReview review) async {
    _setSaving(review.id, true);
    try {
      await LocalStorageService.ignoreTransactionReview(review.id);
      if (!mounted) return;
      setState(
        () =>
            _reviews = _reviews.where((item) => item.id != review.id).toList(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message ignored. It will not affect summaries.'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to ignore this message.')),
        );
      }
    } finally {
      _setSaving(review.id, false);
    }
  }

  Future<void> _chooseCategory(TransactionReview review) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => ListView(
        children: [
          const ListTile(title: Text('Choose Category')),
          ListTile(
            title: const Text('Uncategorized'),
            onTap: () => Navigator.pop(sheetContext, ''),
          ),
          ..._categories.map(
            (category) => ListTile(
              leading: Text(category.emoji),
              title: Text(category.name),
              onTap: () => Navigator.pop(sheetContext, category.id),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Manage categories'),
            onTap: () => Navigator.pop(sheetContext, '__manage'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == '__manage') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CategoriesScreen()),
      );
      if (mounted) await _load();
      return;
    }
    _setSaving(review.id, true);
    try {
      await LocalStorageService.updateTransactionReviewCategory(
        review.id,
        selected.isEmpty ? null : selected,
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update category.')),
        );
      }
    } finally {
      _setSaving(review.id, false);
    }
  }

  Future<void> _saveMerchantRule(TransactionReview review) async {
    final draft = await _showMerchantRuleDialog(review);
    if (draft == null) return;

    _setSaving(review.id, true);
    try {
      await LocalStorageService.saveMerchantRule(
        MerchantRule(
          id: _uuid.v4(),
          matchText: draft.matchText,
          merchant: draft.merchant,
          categoryId: review.categoryId,
          tag: draft.tag,
          createdAt: DateTime.now(),
        ),
      );
      await LocalStorageService.updateTransactionReviewMerchant(
        review.id,
        draft.merchant,
        draft.tag,
      );
      if (!mounted) return;
      setState(() {
        _reviews = _reviews
            .map(
              (item) => item.id == review.id
                  ? item.copyWith(
                      merchant: draft.merchant,
                      tag: draft.tag,
                      clearTag: draft.tag == null,
                    )
                  : item,
            )
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merchant rule saved for future messages.'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save the merchant rule.')),
        );
      }
    } finally {
      _setSaving(review.id, false);
    }
  }

  Future<_MerchantRuleDraft?> _showMerchantRuleDialog(
    TransactionReview review,
  ) async {
    final matchController = TextEditingController(text: review.merchant ?? '');
    final merchantController = TextEditingController(
      text: review.merchant ?? '',
    );
    final tagController = TextEditingController(text: review.tag ?? '');
    String? error;

    final result = await showDialog<_MerchantRuleDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Save Merchant Rule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: matchController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'When SMS contains',
                  hintText: 'A unique word or merchant text',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: merchantController,
                decoration: const InputDecoration(labelText: 'Merchant name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagController,
                decoration: const InputDecoration(
                  labelText: 'Tag (optional)',
                  hintText: 'For example: Dining',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final matchText = matchController.text.trim();
                final merchant = merchantController.text.trim();
                final tag = tagController.text.trim();
                if (matchText.isEmpty || merchant.isEmpty) {
                  setDialogState(
                    () => error = 'Enter both a match and merchant name.',
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  _MerchantRuleDraft(
                    matchText: matchText,
                    merchant: merchant,
                    tag: tag.isEmpty ? null : tag,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    matchController.dispose();
    merchantController.dispose();
    tagController.dispose();
    return result;
  }

  void _setSaving(String reviewId, bool saving) {
    if (!mounted) return;
    setState(() {
      if (saving) {
        _savingReviewIds.add(reviewId);
      } else {
        _savingReviewIds.remove(reviewId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Inbox'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _reviews.isEmpty
          ? const _EmptyReviewInbox()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                itemCount: _reviews.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final review = _reviews[index];
                  return _ReviewCard(
                    review: review,
                    category: _categories
                        .where((c) => c.id == review.categoryId)
                        .firstOrNull,
                    isSaving: _savingReviewIds.contains(review.id),
                    onIgnore: () => _ignore(review),
                    onDebit: () => _resolve(review, TransactionType.debit),
                    onCredit: () => _resolve(review, TransactionType.credit),
                    onCategory: () => _chooseCategory(review),
                    onSaveMerchantRule: () => _saveMerchantRule(review),
                  );
                },
              ),
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    this.category,
    required this.isSaving,
    required this.onIgnore,
    required this.onDebit,
    required this.onCredit,
    required this.onCategory,
    required this.onSaveMerchantRule,
  });

  final TransactionReview review;
  final AppCategory? category;
  final bool isSaving;
  final VoidCallback onIgnore;
  final VoidCallback onDebit;
  final VoidCallback onCredit;
  final VoidCallback onCategory;
  final VoidCallback onSaveMerchantRule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sender = SmsParser.getUnifiedSenderNameSync(review.sender);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    review.merchant ?? sender,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  FormatUtils.formatCurrency(review.amount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$sender - ${FormatUtils.formatDateShort(review.date)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text(
              'The parser could not tell whether this was money in or out.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              review.rawMessage,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: isSaving ? null : onIgnore,
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: const Text('Ignore'),
                ),
                FilledButton.icon(
                  onPressed: isSaving ? null : onDebit,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  label: const Text('Debit'),
                ),
                FilledButton.tonalIcon(
                  onPressed: isSaving ? null : onCredit,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  label: const Text('Credit'),
                ),
                OutlinedButton.icon(
                  onPressed: isSaving ? null : onCategory,
                  icon: const Icon(Icons.category_outlined, size: 18),
                  label: Text(category?.name ?? 'Uncategorized'),
                ),
                TextButton.icon(
                  onPressed: isSaving ? null : onSaveMerchantRule,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Save merchant rule'),
                ),
                if (isSaving)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReviewInbox extends StatelessWidget {
  const _EmptyReviewInbox();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing needs review',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Payment messages with an unclear debit or credit direction will appear here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantRuleDraft {
  const _MerchantRuleDraft({
    required this.matchText,
    required this.merchant,
    this.tag,
  });

  final String matchText;
  final String merchant;
  final String? tag;
}
