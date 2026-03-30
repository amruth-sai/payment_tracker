// lib/widgets/merged_transfer_card.dart

import 'package:flutter/material.dart';
import '../models/merged_transfer.dart';
import '../utils/format_utils.dart';
import '../constants/transfer_constants.dart';

class MergedTransferCard extends StatelessWidget {
  final MergedTransfer mergedTransfer;
  final VoidCallback? onTap;
  final Function(MergedTransfer)? onSwipeUnmerge;
  final Function(MergedTransfer)? onSwipeIgnore;

  const MergedTransferCard({
    super.key,
    required this.mergedTransfer,
    this.onTap,
    this.onSwipeUnmerge,
    this.onSwipeIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const transferColor = Color(0xFF1976D2); // Blue for transfers
    final bgColor = transferColor.withValues(alpha: 0.08);

    final cardContent = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap != null
            ? () {
                debugPrint('🔄 MergedTransferCard tapped for group: ${mergedTransfer.transferGroupId}');
                onTap!();
              }
            : null,
        splashColor: transferColor.withValues(alpha: 0.1),
        highlightColor: transferColor.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Transfer icon with special design
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  color: transferColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Transfer details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Transfer title
                    Text(
                      TransferConstants.transferCategory,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: transferColor,
                      ),
                    ),
                    const SizedBox(height: 3),

                    // Transfer path: From → To
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            mergedTransfer.sourceAccountName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            mergedTransfer.destinationAccountName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Chips and metadata
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Chip(
                          label: mergedTransfer.paymentSource.name.toUpperCase(),
                          color: theme.colorScheme.primary,
                        ),
                        const _Chip(
                          label: TransferConstants.transferLabel,
                          color: transferColor,
                        ),
                        if (mergedTransfer.combinedTags.isNotEmpty)
                          ...mergedTransfer.combinedTags.map((tag) => _Chip(
                            label: tag,
                            color: theme.colorScheme.tertiary,
                          )),
                      ],
                    ),
                    const SizedBox(height: 3),

                    // Date and time
                    Text(
                      FormatUtils.formatDateShort(mergedTransfer.date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Amount (neutral since it's a transfer)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    FormatUtils.formatCurrency(mergedTransfer.amount),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: transferColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: transferColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      TransferConstants.transferCategory,
                      style: TextStyle(
                        color: transferColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // If no swipe callbacks provided, return plain card
    if (onSwipeUnmerge == null && onSwipeIgnore == null) {
      return cardContent;
    }

    // Wrap with Dismissible for swipe actions
    return Dismissible(
      key: ValueKey('merged_${mergedTransfer.transferGroupId}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd && onSwipeIgnore != null) {
          // Swipe right → Ignore both transactions
          onSwipeIgnore!(mergedTransfer);
          return false;
        } else if (direction == DismissDirection.endToStart && onSwipeUnmerge != null) {
          // Swipe left → Unmerge transfer
          onSwipeUnmerge!(mergedTransfer);
          return false;
        }
        return false;
      },
      background: // Swipe right background (Ignore)
          Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Ignore',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: // Swipe left background (Unmerge)
          Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Unmerge',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            SizedBox(width: 8),
            Icon(
              Icons.call_split_rounded,
              color: Colors.white,
              size: 22,
            ),
          ],
        ),
      ),
      child: cardContent,
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Widget for displaying potential transfer pairs that can be merged
class TransferPairSuggestionCard extends StatelessWidget {
  final dynamic transferPair; // TransferPair from transfer_service.dart
  final VoidCallback? onMerge;
  final VoidCallback? onDismiss;

  const TransferPairSuggestionCard({
    super.key,
    required this.transferPair,
    this.onMerge,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.merge_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Merge as Transfer?',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  transferPair.confidencePercentage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Transfer details
            Text(
              transferPair.description,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),

            // Reasons
            if (transferPair.reasons.isNotEmpty) ...[
              Text(
                'Detected: ${transferPair.reasons.join(", ")}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('Not a Transfer'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onMerge,
                  icon: const Icon(Icons.merge_rounded, size: 18),
                  label: const Text('Merge'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}