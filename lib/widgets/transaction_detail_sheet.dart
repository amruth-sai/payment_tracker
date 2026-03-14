// lib/widgets/transaction_detail_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../models/custom_category.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';

class TransactionDetailSheet extends StatefulWidget {
  final Transaction tx;
  final Function(Transaction)? onTransactionUpdated;

  const TransactionDetailSheet({
    super.key,
    required this.tx,
    this.onTransactionUpdated,
  });

  static void show(BuildContext context, Transaction tx,
      {Function(Transaction)? onUpdated}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransactionDetailSheet(
        tx: tx,
        onTransactionUpdated: onUpdated,
      ),
    );
  }

  @override
  State<TransactionDetailSheet> createState() => _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<TransactionDetailSheet> {
  late Transaction _tx;
  List<CustomCategory> _customCategories = [];
  CustomCategory? _selectedCustomCategory;

  @override
  void initState() {
    super.initState();
    _tx = widget.tx;
    _loadCustomCategories();
  }

  Future<void> _loadCustomCategories() async {
    final cats = await LocalStorageService.getAllCustomCategories();
    CustomCategory? current;
    if (_tx.customCategoryId != null) {
      try {
        current = cats.firstWhere((c) => c.id == _tx.customCategoryId);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _customCategories = cats;
        _selectedCustomCategory = current;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit = _tx.isCredit;
    final color = isCredit ? const Color(0xFF1DB954) : const Color(0xFFE53935);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Amount hero
          Icon(
            isCredit
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            color: color,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            '${isCredit ? '+' : '-'}₹${NumberFormat('#,##,###.##').format(_tx.amount)}',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _tx.typeLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_tx.isUserCorrected) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CORRECTED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Correction button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: _showCorrectionDialog,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Correct Transaction Type'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Ignore toggle (Feature 2)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Material(
              color: _tx.isIgnored
                  ? Colors.orange.withValues(alpha: 0.08)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _toggleIgnore,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        _tx.isIgnored
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                        color: _tx.isIgnored ? Colors.orange : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _tx.isIgnored
                                  ? 'Ignored'
                                  : 'Track this transaction',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _tx.isIgnored
                                    ? Colors.orange
                                    : null,
                              ),
                            ),
                            Text(
                              _tx.isIgnored
                                  ? 'Not included in any summaries'
                                  : 'Tap to exclude from summaries',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: !_tx.isIgnored,
                        onChanged: (_) => _toggleIgnore(),
                        activeThumbColor: Colors.green,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Category badge - clickable to change (Feature 3)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Built-in or custom category
                if (_selectedCustomCategory != null)
                  _CategoryBadge(
                    emoji: _selectedCustomCategory!.emoji,
                    label: _selectedCustomCategory!.name,
                    color: _selectedCustomCategory!.color,
                    onTap: _showCategoryPicker,
                  )
                else if (_tx.category != null)
                  _CategoryBadge(
                    emoji: _tx.category!.emoji,
                    label: _tx.category!.displayName,
                    color: Theme.of(context).colorScheme.primary,
                    onTap: _showCategoryPicker,
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _showCategoryPicker,
                    icon: const Icon(Icons.label_outline, size: 16),
                    label: const Text('Assign Category'),
                    style: OutlinedButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tag row (Feature 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              onTap: _showTagEditor,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _tx.tag != null && _tx.tag!.isNotEmpty
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      size: 18,
                      color: _tx.tag != null && _tx.tag!.isNotEmpty
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _tx.tag != null && _tx.tag!.isNotEmpty
                            ? _tx.tag!
                            : 'Add a tag (e.g. reimbursable, split...)',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle:
                              _tx.tag == null || _tx.tag!.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                          color:
                              _tx.tag != null && _tx.tag!.isNotEmpty
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(Icons.edit, size: 14, color: Colors.grey[400]),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Personal Note
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              onTap: _showNoteEditor,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _tx.note != null && _tx.note!.isNotEmpty
                          ? Icons.sticky_note_2
                          : Icons.note_add_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _tx.note != null && _tx.note!.isNotEmpty
                            ? _tx.note!
                            : 'Add a personal note...',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle:
                              _tx.note == null || _tx.note!.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                          color: _tx.note != null && _tx.note!.isNotEmpty
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(Icons.edit, size: 14, color: Colors.grey[400]),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _DetailRow('Date & Time',
                    DateFormat('dd MMM yyyy, hh:mm a').format(_tx.date), theme),
                _DetailRow('Via', _tx.sourceLabel, theme),
                if (_tx.merchant != null)
                  _DetailRow('Merchant', _tx.merchant!, theme),
                if (_tx.accountLast4 != null)
                  _DetailRow('Account', '••••${_tx.accountLast4}', theme),
                if (_tx.balance != null)
                  _DetailRow(
                      'Balance After',
                      '₹${NumberFormat('#,##,###.##').format(_tx.balance!)}',
                      theme),
                if (_tx.referenceId != null)
                  _DetailRow('Reference ID', _tx.referenceId!, theme,
                      copyable: true),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Raw SMS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ExpansionTile(
              title: Text('Raw SMS', style: theme.textTheme.bodySmall),
              tilePadding: EdgeInsets.zero,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _tx.rawMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showCorrectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct Transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This transaction was detected as:'),
            const SizedBox(height: 8),
            Chip(
              label: Text(
                  _tx.isCredit ? 'Money In (Credit)' : 'Money Out (Debit)'),
              backgroundColor: _tx.isCredit
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.red.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            const Text('Change it to:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (_tx.isCredit)
            FilledButton.icon(
              onPressed: () => _correctType(TransactionType.debit),
              icon: const Icon(Icons.arrow_upward),
              label: const Text('Money Out'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
            )
          else
            FilledButton.icon(
              onPressed: () => _correctType(TransactionType.credit),
              icon: const Icon(Icons.arrow_downward),
              label: const Text('Money In'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
        ],
      ),
    );
  }

  Future<void> _correctType(TransactionType newType) async {
    Navigator.pop(context); // Close dialog

    final correctedTx = _tx.copyWith(
      type: newType,
      isUserCorrected: true,
    );

    await LocalStorageService.updateTransaction(correctedTx);

    setState(() {
      _tx = correctedTx;
    });

    widget.onTransactionUpdated?.call(correctedTx);

    // Refresh in-memory list so all screens reflect the change instantly
    if (mounted) {
      context.read<SmsService>().reloadFromCache();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction corrected'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showNoteEditor() {
    final controller = TextEditingController(text: _tx.note ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Personal Note'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Birthday dinner, Office supplies...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final note = controller.text.trim();
              await LocalStorageService.updateTransactionNote(
                  _tx.id, note.isEmpty ? null : note);
              final updated = _tx.copyWith(note: note.isEmpty ? null : note);
              setState(() => _tx = updated);
              widget.onTransactionUpdated?.call(updated);
              // Refresh in-memory list so all screens reflect the change instantly
              if (mounted) {
                context.read<SmsService>().reloadFromCache();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Feature 1: Tag editor
  void _showTagEditor() {
    final controller = TextEditingController(text: _tx.tag ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            hintText: 'e.g. reimbursable, split, work...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (_tx.tag != null && _tx.tag!.isNotEmpty)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await LocalStorageService.updateTransactionTag(_tx.id, null);
                final updated = _tx.copyWith(clearTag: true);
                setState(() => _tx = updated);
                widget.onTransactionUpdated?.call(updated);
                // Refresh in-memory list so all screens reflect the change instantly
                if (mounted) {
                  context.read<SmsService>().reloadFromCache();
                }
              },
              child: const Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final tag = controller.text.trim();
              await LocalStorageService.updateTransactionTag(
                  _tx.id, tag.isEmpty ? null : tag);
              final updated = tag.isEmpty
                  ? _tx.copyWith(clearTag: true)
                  : _tx.copyWith(tag: tag);
              setState(() => _tx = updated);
              widget.onTransactionUpdated?.call(updated);
              // Refresh in-memory list so all screens reflect the change instantly
              if (mounted) {
                context.read<SmsService>().reloadFromCache();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Feature 2: Toggle ignore
  Future<void> _toggleIgnore() async {
    final newIgnored = !_tx.isIgnored;
    await LocalStorageService.updateTransactionIgnored(_tx.id, newIgnored);
    final updated = _tx.copyWith(isIgnored: newIgnored);
    setState(() => _tx = updated);
    widget.onTransactionUpdated?.call(updated);
    // Refresh in-memory list so home screen summary updates
    if (mounted) {
      context.read<SmsService>().reloadFromCache();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newIgnored
            ? 'Transaction ignored — excluded from summaries'
            : 'Transaction restored — included in summaries'),
        backgroundColor: newIgnored ? Colors.orange : Colors.green,
      ));
    }
  }

  // Feature 3: Category picker (built-in + custom)
  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CategoryPickerSheet(
        currentBuiltIn: _tx.category,
        currentCustomId: _tx.customCategoryId,
        customCategories: _customCategories,
        onBuiltInSelected: (cat) async {
          await LocalStorageService.updateTransactionCategory(_tx.id, cat);
          await LocalStorageService.updateTransactionCustomCategory(
              _tx.id, null);
          final updated =
              _tx.copyWith(category: cat, clearCustomCategory: true);
          setState(() {
            _tx = updated;
            _selectedCustomCategory = null;
          });
          widget.onTransactionUpdated?.call(updated);
          // Refresh in-memory list so all screens reflect the change instantly
          if (mounted) {
            context.read<SmsService>().reloadFromCache();
          }
        },
        onCustomSelected: (custom) async {
          await LocalStorageService.updateTransactionCustomCategory(
              _tx.id, custom.id);
          final updated = _tx.copyWith(customCategoryId: custom.id);
          setState(() {
            _tx = updated;
            _selectedCustomCategory = custom;
          });
          widget.onTransactionUpdated?.call(updated);
          // Refresh in-memory list so all screens reflect the change instantly
          if (mounted) {
            context.read<SmsService>().reloadFromCache();
          }
        },
        onClearCategory: () async {
          await LocalStorageService.updateTransactionCustomCategory(
              _tx.id, null);
          final updated = _tx.copyWith(clearCustomCategory: true);
          setState(() {
            _tx = updated;
            _selectedCustomCategory = null;
          });
          widget.onTransactionUpdated?.call(updated);
          // Refresh in-memory list so all screens reflect the change instantly
          if (mounted) {
            context.read<SmsService>().reloadFromCache();
          }
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  final bool copyable;

  const _DetailRow(this.label, this.value, this.theme, {this.copyable = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            children: [
              Text(
                value,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (copyable) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Copied!'),
                          duration: Duration(seconds: 1)),
                    );
                  },
                  child: Icon(Icons.copy_rounded,
                      size: 14, color: theme.colorScheme.primary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// Feature 3: Tappable category badge
class _CategoryBadge extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CategoryBadge({
    required this.emoji,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}

// Feature 3: Sheet showing built-in + custom categories to pick from
class _CategoryPickerSheet extends StatelessWidget {
  final TransactionCategory? currentBuiltIn;
  final String? currentCustomId;
  final List<CustomCategory> customCategories;
  final void Function(TransactionCategory) onBuiltInSelected;
  final void Function(CustomCategory) onCustomSelected;
  final VoidCallback onClearCategory;

  const _CategoryPickerSheet({
    required this.currentBuiltIn,
    required this.currentCustomId,
    required this.customCategories,
    required this.onBuiltInSelected,
    required this.onCustomSelected,
    required this.onClearCategory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, sc) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Choose Category',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (currentBuiltIn != null || currentCustomId != null)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          onClearCategory();
                        },
                        child: const Text('Clear',
                            style: TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: sc,
              padding: const EdgeInsets.all(12),
              children: [
                // Custom categories section
                if (customCategories.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Text('My Categories',
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: customCategories.map((cat) {
                      final isSelected = cat.id == currentCustomId;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          onCustomSelected(cat);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? cat.color.withValues(alpha: 0.25)
                                : cat.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: cat.color
                                  .withValues(alpha: isSelected ? 0.8 : 0.3),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(cat.emoji,
                                  style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 6),
                              Text(cat.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: cat.color,
                                  )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                ],

                // Built-in categories
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text('Standard Categories',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: TransactionCategory.values.map((cat) {
                    final isSelected =
                        currentCustomId == null && cat == currentBuiltIn;
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        onBuiltInSelected(cat);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline
                                    .withValues(alpha: 0.3),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cat.emoji,
                                style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(cat.displayName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimaryContainer
                                      : null,
                                )),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
