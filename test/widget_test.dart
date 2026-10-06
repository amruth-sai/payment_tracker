import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/widgets/transaction_card.dart';

void main() {
  testWidgets('transaction card shows a parsed payment', (tester) async {
    final transaction = Transaction(
      id: 'sms-1',
      amount: 1250,
      type: TransactionType.debit,
      source: PaymentSource.upi,
      sender: 'HDFC',
      merchant: 'Coffee Shop',
      date: DateTime(2026, 10, 6, 10),
      rawMessage: 'Rs.1250 debited for UPI payment.',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TransactionCard(tx: transaction)),
    ));

    expect(find.text('Coffee Shop'), findsOneWidget);
    expect(find.textContaining('1,250'), findsWidgets);
  });
}
