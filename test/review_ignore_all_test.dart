import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/models/transaction_review.dart';
import 'package:payment_tracker/screens/ignored_messages_screen.dart';
import 'package:payment_tracker/screens/transaction_review_screen.dart';
import 'package:payment_tracker/services/database_schema.dart';
import 'package:payment_tracker/services/local_storage_service.dart';
import 'package:payment_tracker/services/sms_service.dart';

void main() {
  late Database db;
  late SmsService sms;
  final ignoreAll = find.byKey(const ValueKey('ignore-all-reviews'));

  TransactionReview review(String id, {bool ignored = false}) =>
      TransactionReview(
        id: id,
        amount: 10,
        source: PaymentSource.bank,
        sender: 'BANK',
        date: DateTime(2026, 11, 1),
        rawMessage: 'Payment message $id',
        createdAt: DateTime(2026, 11, 1),
        isIgnored: ignored,
      );

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: DatabaseSchema.create),
    );
    LocalStorageService.useDatabaseForTesting(db);
    sms = SmsService();
  });
  tearDown(() async {
    sms.dispose();
    await LocalStorageService.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    Widget screen = const TransactionReviewScreen(),
    bool small = false,
  }) async {
    if (small) {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      ChangeNotifierProvider<SmsService>.value(
        value: sms,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            brightness: small ? Brightness.dark : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(small ? 1.6 : 1)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'one tap ignores offscreen reviews, preserves all other data and allows restore',
    (tester) async {
      await tester.runAsync(() async {
        await LocalStorageService.saveTransactionReviews([
          for (var i = 0; i < 20; i++) review('review-$i'),
          review('already-ignored', ignored: true),
        ]);
        await LocalStorageService.saveTransaction(
          Transaction(
            id: 'saved-transaction',
            amount: 25,
            type: TransactionType.debit,
            source: PaymentSource.bank,
            sender: 'BANK',
            date: DateTime(2026, 11, 1),
            rawMessage: 'Saved payment',
          ),
        );
      });
      await open(tester);
      final before = await tester.runAsync(LocalStorageService.createBackup);
      expect(tester.getTopLeft(ignoreAll).dy, lessThan(60));
      await tester.tap(ignoreAll);
      await settle(tester);
      expect(find.text('Nothing needs review'), findsOneWidget);
      expect(tester.widget<TextButton>(ignoreAll).onPressed, isNull);
      final pending = await tester.runAsync(
        () => LocalStorageService.getTransactionReviews(),
      );
      final ignored = await tester.runAsync(
        () => LocalStorageService.getTransactionReviews(ignored: true),
      );
      expect(pending, isEmpty);
      expect(ignored, hasLength(21));
      final after = await tester.runAsync(LocalStorageService.createBackup);
      for (final table in before!.tables.keys.where(
        (name) => name != 'transaction_reviews',
      )) {
        expect(after!.tables[table], before.tables[table], reason: table);
      }
      expect(after!.tables['transaction_reviews'], [
        for (final row in before.tables['transaction_reviews']!)
          {...row, 'is_ignored': 1},
      ]);
      await open(tester, screen: const IgnoredMessagesScreen());
      await tester.tap(find.text('Restore').first);
      await settle(tester);
      expect(
        await tester.runAsync(
          () => LocalStorageService.getTransactionReviews(),
        ),
        hasLength(1),
      );
      await open(tester);
      expect(tester.widget<TextButton>(ignoreAll).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed ignores stay in the inbox and can be retried', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await LocalStorageService.saveTransactionReviews([
        review('good'),
        review('blocked'),
      ]);
      await db.execute(
        """CREATE TRIGGER block_ignore BEFORE UPDATE OF is_ignored ON transaction_reviews
        WHEN NEW.id = 'blocked' AND NEW.is_ignored = 1
        BEGIN SELECT RAISE(ABORT, 'test write failure'); END""",
      );
    });
    await open(tester);
    await tester.tap(ignoreAll);
    await settle(tester);
    expect(
      find.text(
        'Ignored 1 of 2 messages. Try again for the remaining messages.',
      ),
      findsOneWidget,
    );
    expect(
      (await tester.runAsync(
        () => LocalStorageService.getTransactionReviews(),
      ))!.single.id,
      'blocked',
    );
    expect(tester.widget<TextButton>(ignoreAll).onPressed, isNotNull);
    await tester.runAsync(() => db.execute('DROP TRIGGER block_ignore'));
    await tester.tap(ignoreAll);
    await settle(tester);
    expect(find.text('Nothing needs review'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => LocalStorageService.getTransactionReviews(ignored: true),
      ),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty inbox disables bulk action and small dark layouts keep it accessible',
    (tester) async {
      await open(tester, small: true);
      expect(tester.widget<TextButton>(ignoreAll).onPressed, isNull);
      await tester.runAsync(
        () => LocalStorageService.saveTransactionReviews([review('one')]),
      );
      await tester.tap(find.byTooltip('Refresh inbox'));
      await settle(tester);
      expect(tester.widget<TextButton>(ignoreAll).onPressed, isNotNull);
      await tester.tap(ignoreAll);
      await settle(tester);
      expect(find.text('Nothing needs review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
