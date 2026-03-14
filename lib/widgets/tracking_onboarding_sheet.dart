// lib/widgets/tracking_onboarding_sheet.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/local_storage_service.dart';

/// Result returned by the onboarding sheet.
/// [trackFromDate] is null when the user chooses "Track everything".
class OnboardingResult {
  final DateTime? trackFromDate;
  const OnboardingResult({this.trackFromDate});
}

class TrackingOnboardingSheet extends StatefulWidget {
  const TrackingOnboardingSheet({super.key});

  /// Show the onboarding sheet and return the result.
  /// Returns `null` only if the user explicitly dismisses (back button),
  /// which we treat the same as "Track everything".
  static Future<OnboardingResult?> show(BuildContext context) {
    return showModalBottomSheet<OnboardingResult>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TrackingOnboardingSheet(),
    );
  }

  @override
  State<TrackingOnboardingSheet> createState() =>
      _TrackingOnboardingSheetState();
}

class _TrackingOnboardingSheetState extends State<TrackingOnboardingSheet> {
  DateTime? _selectedDate;
  int _selectedOption = -1; // -1 = none, 0 = date, 1 = all

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.history_toggle_off_rounded,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Where should we start?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose from when to track your transactions. '
                'We\'ll only consider messages after your selection.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Option 1: Pick a date
              _OptionCard(
                icon: Icons.calendar_today_rounded,
                title: 'Start from a date',
                subtitle: _selectedDate != null
                    ? 'From ${DateFormat('dd MMM yyyy').format(_selectedDate!)}'
                    : 'Only track transactions after a specific date',
                selected: _selectedOption == 0,
                color: theme.colorScheme.primary,
                onTap: () => _pickDate(context),
              ),
              const SizedBox(height: 12),

              // Option 2: Track everything
              _OptionCard(
                icon: Icons.all_inclusive_rounded,
                title: 'Track everything',
                subtitle: 'Consider all available transaction messages',
                selected: _selectedOption == 1,
                color: Colors.green,
                onTap: () {
                  setState(() {
                    _selectedOption = 1;
                    _selectedDate = null;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Quick presets row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'Quick:',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PresetChip(
                      label: 'This month',
                      onTap: () {
                        final now = DateTime.now();
                        setState(() {
                          _selectedDate = DateTime(now.year, now.month, 1);
                          _selectedOption = 0;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _PresetChip(
                      label: 'Last 30 days',
                      onTap: () {
                        setState(() {
                          _selectedDate = DateTime.now()
                              .subtract(const Duration(days: 30));
                          _selectedOption = 0;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _PresetChip(
                      label: 'Last 90 days',
                      onTap: () {
                        setState(() {
                          _selectedDate = DateTime.now()
                              .subtract(const Duration(days: 90));
                          _selectedOption = 0;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Continue button
              FilledButton(
                onPressed: _selectedOption == -1 ? null : _onContinue,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Continue',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDate: _selectedDate ?? now,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedOption = 0;
      });
    }
  }

  Future<void> _onContinue() async {
    // Persist the onboarding choice
    if (_selectedOption == 0 && _selectedDate != null) {
      await LocalStorageService.setTrackFromDate(_selectedDate);
    } else {
      // "Track everything" — clear any prior date restriction
      await LocalStorageService.setTrackFromDate(null);
    }
    // Also clear any prior transaction anchor
    await LocalStorageService.setTrackFromTransactionId(null);

    // Mark onboarding done
    await LocalStorageService.setOnboardingCompleted(true);

    if (mounted) {
      Navigator.pop(context, OnboardingResult(trackFromDate: _selectedDate));
    }
  }
}

// ─── Private widgets ──────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? color.withValues(alpha: 0.1)
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.5)
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.2)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected ? color : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: color, size: 24)
              else
                Icon(Icons.radio_button_unchecked,
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
