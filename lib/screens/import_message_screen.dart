import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../services/local_storage_service.dart';
import '../services/message_import_service.dart';
import '../services/sms_service.dart';
import '../utils/format_utils.dart';

class ImportMessageScreen extends StatefulWidget {
  const ImportMessageScreen({super.key});
  @override
  State<ImportMessageScreen> createState() => _ImportMessageScreenState();
}

class _ImportMessageScreenState extends State<ImportMessageScreen> {
  final _sender = TextEditingController();
  final _body = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _dateChosen = false;
  bool _busy = false;
  bool _saved = false;
  Transaction? _preview;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _sender.addListener(_changed);
    _body.addListener(_changed);
  }

  void _changed() {
    setState(() {
      _preview = null;
      _error = null;
      _status = null;
      if (!_dateChosen) _date = MessageImportService.dateInMessage(_body.text);
    });
  }

  @override
  void dispose() {
    _sender.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      if (data?.text?.trim().isNotEmpty != true) {
        setState(() => _error = 'Copy a payment message first.');
        return;
      }
      _body.text = data!.text!;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not paste. You can enter the text below.',
        );
      }
    }
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _date != null && !_date!.isAfter(now) ? _date : now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _date = selected;
      _dateChosen = true;
      _preview = null;
      _error = null;
    });
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 12, minute: 0),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _time = selected;
      _preview = null;
      _error = null;
    });
  }

  Future<void> _parse() async {
    FocusScope.of(context).unfocus();
    if (_date == null || _time == null) {
      setState(() => _error = 'Choose the original message date and time.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await MessageImportService.preview(
        body: _body.text,
        sender: _sender.text,
        date: DateTime(
          _date!.year,
          _date!.month,
          _date!.day,
          _time!.hour,
          _time!.minute,
        ),
      );
      if (mounted) setState(() => _preview = result);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read this message. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _saved || _preview == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var inserted = false;
    try {
      inserted = await LocalStorageService.importMessageTransaction(_preview!);
      if (!mounted) return;
      setState(() {
        _saved = true;
        _status = inserted
            ? 'Transaction saved. It appears in your totals when it matches your tracking and list filters.'
            : 'This message already exists. No duplicate was added and previous edits were preserved.';
      });
      await context.read<SmsService>().reloadFromCache();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = _saved
            ? 'The transaction is stored. Reopen the transaction list to refresh it.'
            : 'Could not save this message. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _another() {
    _body.clear();
    setState(() {
      _date = null;
      _time = null;
      _dateChosen = false;
      _preview = null;
      _error = null;
      _status = null;
      _saved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tx = _preview;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Paste payment message')),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            children: [
              const Text(
                'RCS chats are separate from the SMS inbox. Long-press a payment alert in Messages, copy its text, then paste it here. Import one message at a time.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _sender,
                enabled: !_saved,
                key: const ValueKey('message-sender'),
                decoration: const InputDecoration(
                  labelText: 'Sender or bank name',
                  hintText: 'For example: SBI CARDS AND PAYMENT SERVICES',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                enabled: !_saved,
                key: const ValueKey('message-body'),
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Payment message',
                  border: OutlineInputBorder(),
                ),
              ),
              if (!_saved)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste copied text'),
                  ),
                ),
              ListTile(
                key: const ValueKey('message-date'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Original message date'),
                subtitle: Text(
                  _date == null
                      ? 'Choose date'
                      : DateFormat('dd MMM yyyy').format(_date!),
                ),
                onTap: _saved ? null : _chooseDate,
              ),
              ListTile(
                key: const ValueKey('message-time'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Original message time'),
                subtitle: Text(
                  _time == null
                      ? 'Choose time shown in Messages'
                      : _time!.format(context),
                ),
                onTap: _saved ? null : _chooseTime,
              ),
              const Text(
                'Dates found in the alert use day/month/year. Check the date and original time before saving; the time also helps detect an existing SMS copy.',
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_busy) const Center(child: CircularProgressIndicator()),
              if (!_saved)
                OutlinedButton.icon(
                  onPressed: _parse,
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Preview transaction'),
                ),
              if (tx != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${tx.typeLabel} ${FormatUtils.formatCurrency(tx.amount)}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(tx.displayName),
                        Text(tx.sender),
                        Text(
                          '${tx.sourceLabel}${tx.accountLast4 == null ? '' : ' ending ${tx.accountLast4}'}',
                        ),
                        Text(DateFormat('dd MMM yyyy, HH:mm').format(tx.date)),
                        if (tx.categoryId != null)
                          Text(
                            context
                                    .watch<SmsService>()
                                    .categoriesById[tx.categoryId]
                                    ?.name ??
                                'Uncategorized',
                          ),
                      ],
                    ),
                  ),
                ),
                if (!_saved)
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Save transaction'),
                  ),
              ],
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_status!),
                ),
              if (_saved)
                FilledButton(
                  onPressed: _another,
                  child: const Text('Import another message'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
