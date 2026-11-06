import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/screens/import_message_screen.dart';
import 'package:payment_tracker/services/database_schema.dart';
import 'package:payment_tracker/services/local_storage_service.dart';
import 'package:payment_tracker/services/message_import_service.dart';
import 'package:payment_tracker/services/sms_fingerprint.dart';
import 'package:payment_tracker/services/sms_parser.dart';
import 'package:payment_tracker/services/sms_processing_service.dart';
import 'package:payment_tracker/services/sms_service.dart';

const sender = 'SBI CARDS AND PAYMENT SERVICES';
const alerts = [
  'Rs.55,838.00 spent on your SBI Credit Card ending 0042 at ASSPL on 08/10/26. Trxn. not done by you? Report at https://sbicard.com/Dispute',
  'Rs.5,635.30 spent on your SBI Credit Card ending 0042 at ASSPL on 12/10/26. Trxn. not done by you? Report at https://sbicard.com/Dispute',
  'Rs.100,000.00 spent on your SBI Credit Card ending 0042 at EICHERS on 04/11/26. Trxn. not done by you? Report at https://sbicard.com/Dispute',
];

void main() {
  late Database db;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.create,
      ),
    );
    LocalStorageService.useDatabaseForTesting(db);
    SmsParser.clearSenderMappingCache();
  });
  tearDown(LocalStorageService.close);

  test(
    'all three screenshot alerts parse with exact paise, merchants and card digits',
    () async {
      for (var i = 0; i < alerts.length; i++) {
        final date = MessageImportService.dateInMessage(alerts[i])!;
        final body = alerts[i].replaceAll('Credit Card', 'Credit\nCard');
        final result = await SmsProcessingService().process(
          id: 'sms-$i',
          sender: sender,
          body: body,
          date: date,
        );
        final tx = result.transaction!;
        expect(tx.amount, [55838.0, 5635.3, 100000.0][i]);
        expect(tx.type, TransactionType.debit);
        expect(tx.source, PaymentSource.card);
        expect(tx.accountLast4, '0042');
        expect(tx.merchant, ['ASSPL', 'ASSPL', 'EICHERS'][i]);
        expect(
          date,
          [
            DateTime(2026, 10, 8),
            DateTime(2026, 10, 12),
            DateTime(2026, 11, 4),
          ][i],
        );
        expect(
          SmsParser.parseSync(body, 'AD-SBICARD', date, 'sync')!.accountLast4,
          '0042',
        );
      }
    },
  );

  test(
    'message dates are validated and failed/security/ambiguous messages are not imported',
    () async {
      expect(MessageImportService.dateInMessage('on 31/02/26'), isNull);
      expect(
        MessageImportService.dateInMessage('on 04/11/2026.'),
        DateTime(2026, 11, 4),
      );
      for (final body in [
        'Rs.500 payment failed, account not debited.',
        'OTP 123456 for your SBI card payment of Rs.500.',
        'Rs.500 payment pending.',
        'Rs.500 and Rs.600 spent on your SBI card.',
      ]) {
        await expectLater(
          MessageImportService.preview(
            body: body,
            sender: sender,
            date: DateTime(2026, 10, 8),
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        MessageImportService.preview(
          body: alerts.first,
          sender: '',
          date: DateTime(2026, 10, 8),
        ),
        throwsFormatException,
      );
      await expectLater(
        MessageImportService.preview(
          body: alerts.first,
          sender: sender,
          date: DateTime.now().add(const Duration(days: 1)),
        ),
        throwsFormatException,
      );
      expect(await LocalStorageService.getAllTransactions(), isEmpty);
    },
  );

  test(
    'repeated imports preserve user edits and separate times remain separate payments',
    () async {
      final date = DateTime(2026, 10, 8, 21, 23);
      final tx = await MessageImportService.preview(
        body: alerts.first,
        sender: sender,
        date: date,
      );
      expect(await LocalStorageService.importMessageTransaction(tx), isTrue);
      await LocalStorageService.saveTransaction(
        tx.copyWith(note: 'keep this', tag: 'bike', isIgnored: true),
      );
      final repeated = await MessageImportService.preview(
        body: alerts.first.replaceAll(' ', '  '),
        sender: 'AD-SBICARD',
        date: date.add(const Duration(seconds: 40)),
      );
      expect(
        await LocalStorageService.importMessageTransaction(repeated),
        isFalse,
      );
      final saved = (await LocalStorageService.getAllTransactions()).single;
      expect(saved.note, 'keep this');
      expect(saved.tag, 'bike');
      expect(saved.isIgnored, isTrue);
      final other = await MessageImportService.preview(
        body: alerts.first,
        sender: sender,
        date: date.add(const Duration(hours: 1)),
      );
      expect(await LocalStorageService.importMessageTransaction(other), isTrue);
      expect(await LocalStorageService.getAllTransactions(), hasLength(2));
    },
  );

  test(
    'SMS before import is not duplicated, including sender aliases and SMS seconds',
    () async {
      final date = DateTime(2026, 10, 8, 21, 23);
      final native = SmsParser.parseSync(
        alerts.first,
        'AD-SBICARD',
        date.add(const Duration(seconds: 42)),
        'sms-native',
      )!;
      await LocalStorageService.saveTransaction(
        native.copyWith(note: 'original'),
      );
      final imported = await MessageImportService.preview(
        body: alerts.first,
        sender: sender,
        date: date,
      );
      expect(
        await LocalStorageService.importMessageTransaction(imported),
        isFalse,
      );
      expect(
        (await LocalStorageService.getAllTransactions()).single.note,
        'original',
      );
    },
  );

  test(
    'SMS arriving after import is processed once and preserves the imported row',
    () async {
      final date = DateTime(2026, 10, 8, 21, 23);
      final tx = await MessageImportService.preview(
        body: alerts.first,
        sender: sender,
        date: date,
      );
      final results = await Future.wait([
        LocalStorageService.importMessageTransaction(tx),
        LocalStorageService.importMessageTransaction(tx),
      ]);
      expect(results.where((result) => result), hasLength(1));
      await LocalStorageService.saveTransaction(
        tx.copyWith(note: 'preserve', isIgnored: true),
      );
      final before = await db.query('transactions');
      final smsDate = date.add(const Duration(seconds: 42));
      final id = SmsFingerprint.of(
        sender: 'AD-SBICARD',
        body: alerts.first,
        date: smsDate,
        isSent: false,
      );
      final scan = await SmsProcessingService().process(
        id: id,
        sender: 'AD-SBICARD',
        body: alerts.first,
        date: smsDate,
      );
      final storedIds = await LocalStorageService.saveScanResults(
        transactions: [scan.transaction!],
        reviews: [],
        records: [scan.record],
      );
      expect(storedIds, isEmpty);
      expect(await db.query('transactions'), before);
      expect(await LocalStorageService.getProcessedSmsIds(), contains(id));
      expect(await db.query('sms_processing'), hasLength(1));
    },
  );

  testWidgets(
    'paste, preview, save and reset work on a phone without SMS permission',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') return {'text': alerts.last};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final sms = SmsService();
      addTearDown(sms.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: sms,
          child: const MaterialApp(home: ImportMessageScreen()),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('message-sender')),
        sender,
      );
      await tester.tap(find.text('Paste copied text'));
      await tester.pumpAndSettle();
      expect(find.text('04 Nov 2026'), findsOneWidget);
      final preview = find.text('Preview transaction');
      await tester.scrollUntilVisible(
        preview,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(
        find.text('Choose the original message date and time.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('message-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.scrollUntilVisible(
          preview,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(preview);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Credit Card ending 0042'), findsNothing);
      expect(find.text('Card ending 0042'), findsOneWidget);
      expect(find.text('EICHERS'), findsOneWidget);
      final save = find.text('Save transaction');
      await tester.scrollUntilVisible(
        save,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(save);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(sms.transactions, hasLength(1));
      expect(sms.transactions.single.amount, 100000);
      expect(sms.transactions.single.date, DateTime(2026, 11, 4, 12));
      final another = find.text('Import another message');
      await tester.scrollUntilVisible(
        another,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(another);
      await tester.pumpAndSettle();
      expect(find.text('Save transaction'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
