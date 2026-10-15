import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/screens/transfer_management_screen.dart';
import 'package:payment_tracker/services/database_schema.dart';
import 'package:payment_tracker/services/local_storage_service.dart';
import 'package:payment_tracker/services/sms_service.dart';
import 'package:payment_tracker/services/transfer_service.dart';

List<Transaction> payments(int count) => [
  for (var i = 0; i < count; i++)
    for (final type in [TransactionType.debit, TransactionType.credit])
      Transaction(
        id: '${type.name}-$i',
        amount: (i + 1) * 100,
        type: type,
        source: PaymentSource.bank,
        sender: type == TransactionType.debit ? 'BANK_A' : 'BANK_B',
        date: DateTime(2026, 10, 15, 12),
        rawMessage: 'transfer',
      ),
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
  });
  tearDown(LocalStorageService.close);

  test(
    'merges more than 50 pairs, preserves current edits, and supports unmerge',
    () async {
      final transactions = payments(60);
      await LocalStorageService.saveTransactions(transactions);
      final pairs = TransferService.detectPotentialTransfers(transactions);
      expect(pairs, hasLength(60));
      await db.update(
        'transactions',
        {'note': 'Edited after suggestions loaded'},
        where: 'id = ?',
        whereArgs: ['debit-0'],
      );
      expect(await TransferService.mergeTransfers(pairs), 60);
      final saved = await LocalStorageService.getAllTransactions();
      expect(TransferService.getMergedTransfers(saved), hasLength(60));
      expect(TransferService.verifyDataIntegrity(saved).hasIssues, isFalse);
      expect(TransferService.detectPotentialTransfers(saved), isEmpty);
      final debit = saved.firstWhere((tx) => tx.id == 'debit-0');
      expect(debit.note, 'Edited after suggestions loaded');
      await TransferService.unmergeTransfer(debit);
      expect(
        TransferService.getMergedTransfers(
          await LocalStorageService.getAllTransactions(),
        ),
        hasLength(59),
      );
    },
  );

  for (final invalidation in ['ignored', 'missing', 'linked', 'amount']) {
    test(
      'rolls back the whole batch when a later pair is $invalidation',
      () async {
        final transactions = payments(2);
        await LocalStorageService.saveTransactions(transactions);
        final pairs = TransferService.detectPotentialTransfers(transactions);
        final id = pairs.last.creditTransaction.id;
        if (invalidation == 'missing') {
          await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
        } else {
          await db.update(
            'transactions',
            switch (invalidation) {
              'ignored' => {'is_ignored': 1},
              'linked' => {'transfer_group_id': 'existing'},
              _ => {'amount': 12345},
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        final before = await db.query('transactions', orderBy: 'id');
        await expectLater(
          TransferService.mergeTransfers(pairs),
          throwsStateError,
        );
        expect(await db.query('transactions', orderBy: 'id'), before);
      },
    );
  }

  test(
    'rejects overlapping pairs and repeated merges without changing saved data',
    () async {
      final transactions = payments(2);
      await LocalStorageService.saveTransactions(transactions);
      final pairs = TransferService.detectPotentialTransfers(transactions);
      await expectLater(
        TransferService.mergeTransfers([pairs.first, pairs.first]),
        throwsStateError,
      );
      expect(
        (await LocalStorageService.getAllTransactions()).any(
          (tx) => tx.isPartOfTransfer,
        ),
        isFalse,
      );
      await TransferService.mergeTransfers(pairs);
      final before = await db.query('transactions', orderBy: 'id');
      await expectLater(
        TransferService.mergeTransfers(pairs),
        throwsStateError,
      );
      expect(await db.query('transactions', orderBy: 'id'), before);
    },
  );

  testWidgets('merge all excludes dismissed suggestions and refreshes totals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(450, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sms = SmsService();
    addTearDown(sms.dispose);
    await tester.runAsync(() async {
      await LocalStorageService.saveTransactions(payments(3));
      await sms.reloadFromCache();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: sms,
        child: const MaterialApp(home: TransferManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Merge all (3 pairs)'), findsOneWidget);
    await tester.tap(find.text('Not a Transfer').first);
    await tester.pumpAndSettle();
    expect(find.text('Merge all (2 pairs)'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('merge-all-transfers')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('No potential transfers found'), findsOneWidget);
    expect(TransferService.getMergedTransfers(sms.transactions), hasLength(2));
    expect(sms.credits, hasLength(1));
    expect(sms.debits, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
