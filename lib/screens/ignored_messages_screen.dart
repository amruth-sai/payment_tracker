import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/sms_processing_record.dart';
import '../models/transaction_review.dart';
import '../services/local_storage_service.dart';
import '../services/sms_service.dart';

/// Shows user-dismissed review items separately from messages skipped by rules.
class IgnoredMessagesScreen extends StatefulWidget {
  const IgnoredMessagesScreen({super.key});

  @override
  State<IgnoredMessagesScreen> createState() => _IgnoredMessagesScreenState();
}

class _IgnoredMessagesScreenState extends State<IgnoredMessagesScreen> {
  late Future<(List<TransactionReview>, List<SmsProcessingRecord>, int)> _data;
  bool _rescanning = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _load();
  }

  Future<(List<TransactionReview>, List<SmsProcessingRecord>, int)> _load() async {
    final results = await Future.wait<Object>([
      LocalStorageService.getTransactionReviews(ignored: true),
      LocalStorageService.getSkippedPaymentMessages(),
      LocalStorageService.countSkippedMessages(),
    ]);
    return (
      results[0] as List<TransactionReview>,
      results[1] as List<SmsProcessingRecord>,
      results[2] as int,
    );
  }

  Future<void> _restore(TransactionReview review) async {
    await LocalStorageService.restoreTransactionReview(review.id);
    if (!mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message returned to the review inbox.')),
    );
  }

  Future<void> _recheckSkipped() async {
    setState(() => _rescanning = true);
    try {
      await context.read<SmsService>().recheckSkippedMessages();
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skipped messages checked again.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to recheck messages.')),
      );
    } finally {
      if (mounted) setState(() => _rescanning = false);
    }
  }

  Future<void> _sendToReview(SmsProcessingRecord record) async {
    final controller = TextEditingController();
    String? error;
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Review this payment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the amount. You can choose debit or credit in the review inbox.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value == null || value <= 0 || value >= 10000000) {
                  setDialogState(() => error = 'Enter a valid positive amount.');
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Send to review'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (amount == null) return;
    try {
      await LocalStorageService.sendSkippedMessageToReview(record, amount);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message added to the review inbox.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to add this message to review.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Message Decisions'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Ignored reviews'),
            Tab(text: 'Skipped by rules'),
          ]),
        ),
        body:
            FutureBuilder<(List<TransactionReview>, List<SmsProcessingRecord>, int)>(
          future: _data,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              if (snapshot.hasError) {
                return Center(
                    child: Text(
                        'Unable to load message decisions: ${snapshot.error}'));
              }
              return const Center(child: CircularProgressIndicator());
            }
            final (ignored, skipped, totalSkipped) = snapshot.data!;
            return TabBarView(children: [
              _list(
                ignored.isEmpty
                    ? const [
                        ListTile(title: Text('No ignored review messages'))
                      ]
                    : ignored
                        .map((review) => Card(
                              child: ListTile(
                                title: Text(
                                    '${review.sender} · ₹${review.amount.toStringAsFixed(2)}'),
                                subtitle: Text(
                                  '${DateFormat.yMMMd().add_jm().format(review.date)}\n${review.rawMessage}',
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                isThreeLine: true,
                                trailing: TextButton(
                                  onPressed: () => _restore(review),
                                  child: const Text('Restore'),
                                ),
                              ),
                            ))
                        .toList(),
              ),
              _list([
                ListTile(
                  title:
                      Text('${skipped.length} payment-like messages skipped'),
                  subtitle: Text(
                    '${totalSkipped - skipped.length} other skipped scans have no saved '
                    'message body, including older app data.',
                  ),
                  trailing: _rescanning
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator())
                      : IconButton(
                          tooltip: 'Recheck skipped messages',
                          onPressed: _recheckSkipped,
                          icon: const Icon(Icons.refresh),
                        ),
                ),
                if (skipped.isEmpty)
                  const ListTile(
                      title: Text('No skipped payment-like messages')),
                ...skipped.map((record) => Card(
                      child: ExpansionTile(
                        title: Text(record.sender.isEmpty
                            ? 'Unknown sender'
                            : record.sender),
                        subtitle: Text(
                          '${DateFormat.yMMMd().add_jm().format(record.date)} · '
                          '${record.folder} · ${_reason(record.reason)}',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(record.rawMessage ?? ''),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _rescanning ||
                                      context.watch<SmsService>().isLoading
                                  ? null
                                  : () => _sendToReview(record),
                              icon: const Icon(Icons.rate_review_outlined),
                              label: const Text('Send to review'),
                            ),
                          ),
                        ],
                      ),
                    )),
              ]),
            ]);
          },
        ),
      ),
    );
  }

  Widget _list(List<Widget> children) => RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _data;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: children,
        ),
      );

  String _reason(String reason) => switch (reason) {
        'sender_not_recognized' => 'Sender or message not recognized',
        'sent_unrecognized' => 'Sent message from an unknown payment sender',
        'no_amount_indicator' => 'No payment amount',
        'security_message' => 'Security code or login message',
        'amount_not_found' => 'Amount could not be read',
        'legacy_unclassified' => 'Processed before reasons were recorded',
        _ => 'No transaction detected',
      };
}
