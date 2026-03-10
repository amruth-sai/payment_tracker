// Basic Flutter widget test for Payment Tracker

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:payment_tracker/main.dart';
import 'package:payment_tracker/services/sms_service.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SmsService(),
        child: const PaymentTrackerApp(),
      ),
    );

    // Verify the app title is displayed
    expect(find.text('Payment Tracker'), findsOneWidget);
  });
}
