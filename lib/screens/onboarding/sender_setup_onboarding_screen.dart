// lib/screens/onboarding/sender_setup_onboarding_screen.dart
// First-time onboarding screen for AI-powered sender discovery and setup

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:another_telephony/telephony.dart';
import '../../services/onboarding_service.dart';
import '../../services/ai_account_discovery_service.dart';
import '../home_screen.dart';
import 'ai_account_review_screen.dart';

class SenderSetupOnboardingScreen extends StatefulWidget {
  const SenderSetupOnboardingScreen({super.key});

  @override
  State<SenderSetupOnboardingScreen> createState() => _SenderSetupOnboardingScreenState();
}

class _SenderSetupOnboardingScreenState extends State<SenderSetupOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  DateTimeRange? _selectedDateRange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            LinearProgressIndicator(
              value: (_currentPage + 1) / 3,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),

            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _WelcomePage(
                    onContinue: () => _nextPage(),
                  ),
                  _DateRangePage(
                    selectedRange: _selectedDateRange,
                    onRangeSelected: (range) => setState(() => _selectedDateRange = range),
                    onContinue: () => _nextPage(),
                    onBack: () => _previousPage(),
                  ),
                  _SetupProgressPage(
                    dateRange: _selectedDateRange!,
                    onComplete: () => _completeOnboarding(),
                    onBack: () => _previousPage(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      await OnboardingService.setSenderOnboardingCompleted(true);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const HomeScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing setup: $e')),
        );
      }
    }
  }
}

class _WelcomePage extends StatelessWidget {
  final VoidCallback onContinue;

  const _WelcomePage({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),

          // Hero icon
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              size: 64,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),

          const SizedBox(height: 32),

          // Title
          Text(
            'Welcome to Smart Banking',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Description
          Text(
            'Let\'s set up your payment tracker by organizing your bank messages. This one-time setup will help us understand your accounts and provide better insights.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Features list
          _FeatureItem(
            icon: Icons.group_work_outlined,
            title: 'Smart Organization',
            description: 'Group SMS senders under your actual bank accounts',
          ),
          const SizedBox(height: 16),
          _FeatureItem(
            icon: Icons.auto_fix_high,
            title: 'AI-Powered Detection',
            description: 'Automatic suggestions based on your message history',
          ),
          const SizedBox(height: 16),
          _FeatureItem(
            icon: Icons.tune,
            title: 'Full Control',
            description: 'Manually adjust and customize sender assignments',
          ),

          const Spacer(),

          // Continue button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: const Text('Get Started'),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'This setup will take about 2-3 minutes',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateRangePage extends StatelessWidget {
  final DateTimeRange? selectedRange;
  final Function(DateTimeRange) onRangeSelected;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  const _DateRangePage({
    required this.selectedRange,
    required this.onRangeSelected,
    required this.onContinue,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),

          const SizedBox(height: 16),

          // Title
          Text(
            'Choose Time Period',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Select how far back you want to analyze your SMS messages. We\'ll find all bank-related messages in this period.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 32),

          // Quick options
          Text(
            'Quick Options',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 16),

          ...[
            ('Last Week', 'last_week', 'Most recent transactions'),
            ('Last Month', 'last_month', 'Good balance of data and speed'),
            ('Last 3 Months', 'last_3_months', 'More comprehensive analysis'),
            ('Last 6 Months', 'last_6_months', 'Full transaction history'),
          ].map((option) => _DateRangeOption(
            title: option.$1,
            description: option.$3,
            isSelected: selectedRange != null &&
                _isSameRange(selectedRange!, OnboardingService.getRecommendedDateRange(option.$2)),
            onTap: () => onRangeSelected(OnboardingService.getRecommendedDateRange(option.$2)),
          )),

          const SizedBox(height: 24),

          // Custom range option
          OutlinedButton.icon(
            onPressed: () => _showCustomRangePicker(context),
            icon: const Icon(Icons.date_range),
            label: const Text('Choose Custom Range'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),

          // Selected range display
          if (selectedRange != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Selected: ${DateFormat('dd MMM yyyy').format(selectedRange!.start)} - ${DateFormat('dd MMM yyyy').format(selectedRange!.end)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Continue button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: selectedRange != null ? onContinue : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameRange(DateTimeRange a, DateTimeRange b) {
    return a.start.day == b.start.day &&
           a.start.month == b.start.month &&
           a.start.year == b.start.year &&
           a.end.day == b.end.day &&
           a.end.month == b.end.month &&
           a.end.year == b.end.year;
  }

  Future<void> _showCustomRangePicker(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: selectedRange,
    );

    if (range != null) {
      onRangeSelected(range);
    }
  }
}

class _DateRangeOption extends StatelessWidget {
  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _DateRangeOption({
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerLowest,
        leading: Radio<bool>(
          value: true,
          groupValue: isSelected,
          onChanged: (_) => onTap(),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? theme.colorScheme.primary : null,
          ),
        ),
        subtitle: Text(description),
      ),
    );
  }
}

class _SetupProgressPage extends StatefulWidget {
  final DateTimeRange dateRange;
  final VoidCallback onComplete;
  final VoidCallback onBack;

  const _SetupProgressPage({
    required this.dateRange,
    required this.onComplete,
    required this.onBack,
  });

  @override
  State<_SetupProgressPage> createState() => _SetupProgressPageState();
}

class _SetupProgressPageState extends State<_SetupProgressPage> {
  bool _isAnalyzing = true;
  String _currentStep = 'Initializing...';
  double _progress = 0.0;
  String? _error;
  AccountDiscoveryResult? _discoveryResult;

  @override
  void initState() {
    super.initState();
    _startAiAnalysis();
  }

  Future<void> _startAiAnalysis() async {
    try {
      // Step 1: Save date range
      setState(() {
        _currentStep = 'Saving preferences...';
        _progress = 0.1;
      });
      await OnboardingService.setOnboardingDateRange(widget.dateRange);

      // Step 2: Request SMS permission
      setState(() {
        _currentStep = 'Requesting SMS permission...';
        _progress = 0.2;
      });

      final smsPermission = await Permission.sms.request();
      if (!smsPermission.isGranted) {
        setState(() {
          _error = 'SMS permission denied. Cannot analyze messages.';
          _isAnalyzing = false;
        });
        return;
      }

      // Step 3: Fetch SMS messages
      setState(() {
        _currentStep = 'Fetching SMS messages...';
        _progress = 0.3;
      });

      final telephony = Telephony.instance;
      final inboxMessages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ID],
        filter: SmsFilter.where(SmsColumn.DATE)
            .greaterThanOrEqualTo(widget.dateRange.start.millisecondsSinceEpoch.toString()),
      );

      final sentMessages = await telephony.getSentSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ID],
        filter: SmsFilter.where(SmsColumn.DATE)
            .greaterThanOrEqualTo(widget.dateRange.start.millisecondsSinceEpoch.toString()),
      );

      // Convert to map format for AI service
      final allMessages = <Map<String, dynamic>>[];
      for (final msg in [...inboxMessages, ...sentMessages]) {
        if (msg.address == null || msg.body == null) continue;
        allMessages.add({
          'id': 'sms_${msg.id ?? DateTime.now().millisecondsSinceEpoch}',
          'sender': msg.address!,
          'body': msg.body!,
          'date': DateTime.fromMillisecondsSinceEpoch(msg.date ?? 0),
        });
      }

      setState(() {
        _currentStep = 'Found ${allMessages.length} messages...';
        _progress = 0.4;
      });

      if (allMessages.isEmpty) {
        setState(() {
          _error = 'No SMS messages found in the selected period.';
          _isAnalyzing = false;
        });
        return;
      }

      // Step 4: Initialize AI
      setState(() {
        _currentStep = 'Initializing AI...';
        _progress = 0.5;
      });

      final hasApiKey = await AiAccountDiscoveryService.loadSavedApiKey();
      if (!hasApiKey) {
        setState(() {
          _error = 'Gemini API key not configured. Please set up your API key in Settings.';
          _isAnalyzing = false;
        });
        return;
      }

      // Step 5: AI discovers accounts
      setState(() {
        _currentStep = 'AI is analyzing your accounts...';
        _progress = 0.6;
      });

      _discoveryResult = await AiAccountDiscoveryService.discoverAccounts(
        smsMessages: allMessages,
        fromDate: widget.dateRange.start,
      );

      if (_discoveryResult!.hasError) {
        setState(() {
          _error = _discoveryResult!.error;
          _isAnalyzing = false;
        });
        return;
      }

      setState(() {
        _currentStep = 'Found ${_discoveryResult!.totalAccounts} accounts!';
        _progress = 1.0;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Analysis failed: $e';
        _isAnalyzing = false;
      });
    }
  }

  void _navigateToReview() {
    if (_discoveryResult != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AiAccountReviewScreen(
            discoveryResult: _discoveryResult!,
            dateRange: widget.dateRange,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Back button
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _isAnalyzing ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          ),

          const Spacer(),

          // Setup icon
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _error != null
                  ? Icons.error_outline
                  : (_progress >= 1.0 ? Icons.auto_awesome : Icons.psychology),
              size: 48,
              color: _error != null
                  ? theme.colorScheme.error
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),

          const SizedBox(height: 32),

          // Title
          Text(
            _error != null
                ? 'Analysis Failed'
                : (_progress >= 1.0 ? 'Accounts Discovered!' : 'AI Analyzing Messages'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Date range display
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.date_range,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '${DateFormat('dd MMM yyyy').format(widget.dateRange.start)} - ${DateFormat('dd MMM yyyy').format(widget.dateRange.end)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Progress indicator or error
          if (_error == null) ...[
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              _currentStep,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Success message
          if (!_isAnalyzing && _progress >= 1.0 && _discoveryResult != null) ...[
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'AI Analysis Complete',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatChip(
                        icon: Icons.account_balance,
                        label: '${_discoveryResult!.bankAccounts}',
                        subtitle: 'Banks',
                      ),
                      _StatChip(
                        icon: Icons.credit_card,
                        label: '${_discoveryResult!.creditCards}',
                        subtitle: 'Cards',
                      ),
                      _StatChip(
                        icon: Icons.receipt_long,
                        label: '${_discoveryResult!.parsedTransactions.length}',
                        subtitle: 'Transactions',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Continue button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isAnalyzing
                  ? null
                  : (_error != null ? _startAiAnalysis : _navigateToReview),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: Text(
                _isAnalyzing
                    ? 'Analyzing...'
                    : (_error != null ? 'Retry' : 'Review Accounts'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.green.shade700),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.green.shade700,
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.green.shade600,
          ),
        ),
      ],
    );
  }
}