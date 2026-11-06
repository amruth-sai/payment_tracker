import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:payment_tracker/main.dart';
import 'package:payment_tracker/models/app_alert.dart';
import 'package:payment_tracker/models/app_category.dart';
import 'package:payment_tracker/models/transaction.dart';
import 'package:payment_tracker/models/transaction_review.dart';
import 'package:payment_tracker/screens/accounts_screen.dart';
import 'package:payment_tracker/screens/all_transactions_screen.dart';
import 'package:payment_tracker/screens/alerts_screen.dart';
import 'package:payment_tracker/screens/budget_screen.dart';
import 'package:payment_tracker/screens/categories_screen.dart';
import 'package:payment_tracker/screens/category_breakdown_screen.dart';
import 'package:payment_tracker/screens/emi_tracker_screen.dart';
import 'package:payment_tracker/screens/home_screen.dart';
import 'package:payment_tracker/screens/ignored_messages_screen.dart';
import 'package:payment_tracker/screens/ignored_transactions_screen.dart';
import 'package:payment_tracker/screens/import_message_screen.dart';
import 'package:payment_tracker/screens/main_shell_screen.dart';
import 'package:payment_tracker/screens/merchant_rankings_screen.dart';
import 'package:payment_tracker/screens/merchant_rules_screen.dart';
import 'package:payment_tracker/screens/salary_cycle_screen.dart';
import 'package:payment_tracker/screens/salary_month_closeout_screen.dart';
import 'package:payment_tracker/screens/settings_screen.dart';
import 'package:payment_tracker/screens/spending_breakdown_screen.dart';
import 'package:payment_tracker/screens/spending_heatmap_screen.dart';
import 'package:payment_tracker/screens/tracking_settings_screen.dart';
import 'package:payment_tracker/screens/transaction_review_screen.dart';
import 'package:payment_tracker/screens/transaction_window_category_screen.dart';
import 'package:payment_tracker/screens/transfer_management_screen.dart';
import 'package:payment_tracker/services/database_schema.dart';
import 'package:payment_tracker/services/local_storage_service.dart';
import 'package:payment_tracker/services/sms_service.dart';
import 'package:payment_tracker/widgets/new_transactions_review_sheet.dart';
import 'package:payment_tracker/widgets/summary_card.dart';
import 'package:payment_tracker/widgets/tracking_onboarding_sheet.dart';
import 'package:payment_tracker/widgets/transaction_card.dart';

class CountingSmsService extends SmsService {
  int scans = 0;
  int cacheReloads = 0;
  bool showNewlyFound = false;
  String? testError;
  bool testLoading = false;

  @override
  String? get error => testError;
  @override
  bool get isLoading => testLoading;
  @override
  List<Transaction> get newlyFoundTransactions =>
      showNewlyFound ? transactions.take(1).toList() : [];
  @override
  void clearNewlyFoundTransactions() {
    showNewlyFound = false;
    super.clearNewlyFoundTransactions();
  }

  @override
  Future<void> loadTransactions({
    int? daysBack,
    bool scanFromBeginning = false,
  }) async {
    scans++;
    await reloadFromCache();
  }

  @override
  Future<void> reloadFromCache() async {
    cacheReloads++;
    await super.reloadFromCache();
  }
}

void main() {
  late CountingSmsService sms;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.create,
      ),
    );
    LocalStorageService.useDatabaseForTesting(db);
    await LocalStorageService.setOnboardingCompleted(true);
    final now = DateTime.now();
    await LocalStorageService.saveCategory(
      AppCategory(
        id: 'c',
        name: 'Everyday',
        emoji: 'E',
        colorValue: 0xff123456,
        createdAt: now,
      ),
    );
    await LocalStorageService.saveTransactions([
      for (var i = 0; i < 3; i++)
        Transaction(
          id: 'tx-$i',
          amount: (i + 1) * 100,
          type: i == 2 ? TransactionType.credit : TransactionType.debit,
          source: PaymentSource.bank,
          sender: i == 1 ? 'BANK_B' : 'BANK_A',
          merchant: i == 0 ? 'Coffee Shop' : 'Merchant $i',
          date: DateTime(now.year, now.month, now.day, 0, i),
          categoryId: 'c',
          tag: 'personal',
          rawMessage: 'payment $i',
        ),
    ]);
    sms = CountingSmsService();
  });
  tearDown(() async {
    sms.dispose();
    await LocalStorageService.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(480, 1000),
    double textScale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<SmsService>.value(
        value: sms,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const MainShellScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tab(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('tab-$id')));
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.pageBack();
    await settle(tester);
  }

  Future<void> activityTool(WidgetTester tester, String text) async {
    await tester.tap(find.byTooltip('Activity tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await settle(tester);
  }

  testWidgets(
    'application entry has four tabs, real summary first and one service startup',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<SmsService>.value(
          value: sms,
          child: const PaymentTrackerApp(),
        ),
      );
      await settle(tester);
      expect(find.byType(MainShellScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(4),
      );
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      final summary = tester.widget<SummaryCard>(find.byType(SummaryCard));
      expect(summary.totalIn, sms.currentCycleCredits);
      expect(summary.totalOut, sms.currentCycleDebits);
      expect(summary.txCount, sms.currentCycleTransactions.length);
      expect(summary.title, sms.currentCycleLabel);
      expect(summary.subtitle, sms.currentCycleSubtitle);
      expect(find.text('Breakdown'), findsNothing);
      expect(find.text('Accounts'), findsNothing);
      expect(
        tester.getTopLeft(find.byType(SummaryCard)).dy,
        lessThan(tester.getTopLeft(find.widgetWithText(FilterChip, 'All')).dy),
      );
      expect(sms.scans, 1);
    },
  );

  testWidgets(
    'tab switches retain Home and Activity filters and perform no scans or writes',
    (tester) async {
      await open(tester);
      final homeState = tester.state(find.byType(HomeScreen));
      await tester.tap(find.widgetWithText(FilterChip, 'Money Out'));
      await tester.tap(find.widgetWithText(FilterChip, 'BANK_A'));
      await settle(tester);
      final before = await tester.runAsync(LocalStorageService.createBackup);
      final reloads = sms.cacheReloads;
      await tab(tester, 'activity');
      final activityState = tester.state(find.byType(AllTransactionsScreen));
      await tester.enterText(find.byType(TextField), 'Coffee');
      await tester.tap(find.byKey(const ValueKey('banks-BANK_A')));
      await settle(tester);
      await tab(tester, 'insights');
      await tab(tester, 'plan');
      await tab(tester, 'home');
      expect(tester.state(find.byType(HomeScreen)), same(homeState));
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Money Out'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'BANK_A'))
            .selected,
        isTrue,
      );
      await tab(tester, 'activity');
      expect(
        tester.state(find.byType(AllTransactionsScreen)),
        same(activityState),
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Coffee',
      );
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('banks-BANK_A')))
            .selected,
        isTrue,
      );
      final after = await tester.runAsync(LocalStorageService.createBackup);
      expect(after!.tables, before!.tables);
      expect(sms.scans, 1);
      expect(sms.cacheReloads, reloads);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home See All targets Activity and updates its direction on repeated requests',
    (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Money Out'));
      await tester.ensureVisible(find.text('See All'));
      await tester.tap(find.text('See All'));
      await settle(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      await tester.tap(find.widgetWithText(Tab, 'Money In'));
      await tester.pumpAndSettle();
      await tab(tester, 'home');
      await tester.ensureVisible(find.text('See All'));
      await tester.tap(find.text('See All'));
      await settle(tester);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      expect(sms.scans, 1);
    },
  );

  testWidgets(
    'every Insights and Plan destination opens its existing screen and returns',
    (tester) async {
      await open(tester, size: const Size(600, 1400));
      await tester.runAsync(() async {
        await LocalStorageService.markAsSalary('tx-2', true);
        await sms.reloadFromCache();
      });
      await settle(tester);
      for (final entry in <String, Type>{
        'spending': SpendingBreakdownScreen,
        'category-breakdown': CategoryBreakdownScreen,
        'heatmap': SpendingHeatmapScreen,
        'merchants': MerchantRankingsScreen,
        'accounts': AccountsScreen,
        'salary': SalaryCycleScreen,
        'budgets': BudgetScreen,
        'emis': EMITrackerScreen,
        'categories': CategoriesScreen,
      }.entries) {
        final plan = [
          'accounts',
          'salary',
          'budgets',
          'emis',
          'categories',
        ].contains(entry.key);
        await tab(tester, plan ? 'plan' : 'insights');
        final target = find.byKey(ValueKey('destination-${entry.key}'));
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(target);
        await settle(tester);
        expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
        expect(find.byType(NavigationBar), findsNothing);
        if (entry.key == 'salary') {
          await tester.tap(find.byTooltip('Salary month closeout'));
          await settle(tester);
          expect(find.byType(SalaryMonthCloseoutScreen), findsOneWidget);
          await back(tester);
        }
        await back(tester);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          plan ? 3 : 2,
        );
      }
      expect(sms.scans, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Activity tools preserve review, ignored, skipped, transfers, paste and categorization routes',
    (tester) async {
      await open(tester, size: const Size(600, 1400));
      await tab(tester, 'activity');
      final activityState = tester.state(find.byType(AllTransactionsScreen));
      for (final entry in <String, Type>{
        'Review Inbox': TransactionReviewScreen,
        'Ignored Transactions': IgnoredTransactionsScreen,
        'Skipped / Ignored Messages': IgnoredMessagesScreen,
        'Transfer Management': TransferManagementScreen,
        'Paste Payment Message': ImportMessageScreen,
        'Manage categories': CategoriesScreen,
        'Categorize a date or transaction window':
            TransactionWindowCategoryScreen,
      }.entries) {
        await activityTool(tester, entry.key);
        expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
        if (entry.value == IgnoredTransactionsScreen) {
          await tester.tap(find.byTooltip('Message decisions'));
          await settle(tester);
          expect(find.byType(IgnoredMessagesScreen), findsOneWidget);
          await back(tester);
        }
        await back(tester);
        expect(
          tester.state(find.byType(AllTransactionsScreen)),
          same(activityState),
        );
      }
      expect(sms.scans, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Settings remains reachable on every tab and preserves scan-on-return callback',
    (tester) async {
      await open(tester);
      for (final name in ['home', 'activity', 'insights', 'plan']) {
        await tab(tester, name);
        final scans = sms.scans;
        await tester.tap(find.byTooltip('Settings'));
        await settle(tester);
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('Tracking Settings'), findsOneWidget);
        expect(find.text('Paste payment message'), findsOneWidget);
        if (name == 'home') {
          await tester.tap(find.text('Tracking Settings'));
          await settle(tester);
          expect(find.byType(TrackingSettingsScreen), findsOneWidget);
          await back(tester);
          final rules = find.text('Manage Merchant Rules');
          await tester.scrollUntilVisible(
            rules,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(rules);
          await settle(tester);
          expect(find.byType(MerchantRulesScreen), findsOneWidget);
          await back(tester);
          for (final label in [
            'Create Encrypted Backup',
            'Restore Encrypted Backup',
            'Choose & Share JSON',
            'Recheck Skipped Messages',
          ]) {
            final control = find.text(label);
            await tester.scrollUntilVisible(
              control,
              150,
              scrollable: find.byType(Scrollable).first,
            );
            expect(control, findsOneWidget);
          }
        }
        await back(tester);
        expect(sms.scans, scans + 1);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real alert/review counts refresh and review/salary callbacks refresh cached data',
    (tester) async {
      await tester.runAsync(() async {
        await LocalStorageService.saveAlerts([
          AppAlert(
            id: 'alert',
            type: AlertType.anomaly,
            title: 'Test alert',
            message: 'Existing data',
          ),
        ]);
        await LocalStorageService.saveTransactionReviews([
          TransactionReview(
            id: 'review',
            amount: 50,
            source: PaymentSource.bank,
            sender: 'BANK_A',
            date: DateTime.now(),
            rawMessage: 'INR 50 transaction alert',
            createdAt: DateTime.now(),
          ),
        ]);
      });
      await open(tester, size: const Size(600, 1400));
      expect(find.text('1 unread alert'), findsOneWidget);
      expect(find.text('1 transaction needs review'), findsOneWidget);
      await tester.tap(find.byTooltip('Alerts'));
      await settle(tester);
      expect(find.byType(AlertsScreen), findsOneWidget);
      await tester.tap(find.text('Test alert'));
      await settle(tester);
      await back(tester);
      expect(find.text('1 unread alert'), findsNothing);
      final cacheBefore = sms.cacheReloads;
      await tester.tap(find.text('1 transaction needs review'));
      await settle(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Debit'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await settle(tester);
      await back(tester);
      expect(find.text('1 transaction needs review'), findsNothing);
      expect(sms.transactions.any((tx) => tx.id == 'review'), isTrue);
      expect(sms.cacheReloads, greaterThan(cacheBefore));
      await tester.runAsync(() async {
        await LocalStorageService.saveAlerts([
          AppAlert(
            id: 'new-alert',
            type: AlertType.anomaly,
            title: 'New scan alert',
            message: 'Existing data',
          ),
        ]);
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
      });
      await settle(tester);
      expect(find.text('1 unread alert'), findsOneWidget);
      await tab(tester, 'plan');
      await tester.tap(find.byKey(const ValueKey('destination-salary')));
      await settle(tester);
      final beforeReturn = sms.cacheReloads;
      await back(tester);
      expect(sms.cacheReloads, beforeReturn + 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Android Back exits selection first, returns tabs Home, and ignores hidden Activity selection',
    (tester) async {
      await open(tester, size: const Size(600, 1400));
      await tab(tester, 'activity');
      await tester.longPress(find.byKey(const ValueKey('transaction-tx-2')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('1 selected'), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tab(tester, 'activity');
      await tester.longPress(find.byKey(const ValueKey('transaction-tx-2')));
      await tester.pumpAndSettle();
      await tab(tester, 'plan');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tab(tester, 'activity');
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Exit selection'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'startup onboarding and newly-found review run once across tab changes',
    (tester) async {
      await tester.runAsync(
        () => LocalStorageService.setOnboardingCompleted(false),
      );
      sms.showNewlyFound = true;
      await open(tester, size: const Size(600, 1400));
      expect(find.byType(TrackingOnboardingSheet), findsOneWidget);
      expect(sms.scans, 0);
      await tester.tap(find.text('Track everything'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Continue'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settle(tester);
      expect(find.byType(NewTransactionsReviewSheet), findsOneWidget);
      await tester.tap(find.text('Confirm All'));
      await settle(tester);
      await tab(tester, 'activity');
      await tab(tester, 'home');
      expect(find.byType(TrackingOnboardingSheet), findsNothing);
      expect(find.byType(NewTransactionsReviewSheet), findsNothing);
      expect(sms.scans, 1);
    },
  );

  testWidgets(
    'small dark screens and larger type retain accessible navigation without overflow',
    (tester) async {
      await open(
        tester,
        size: const Size(320, 740),
        textScale: 1.6,
        dark: true,
      );
      for (final name in ['home', 'insights', 'plan', 'activity', 'home']) {
        await tab(tester, name);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull, reason: name);
      }
      final summary = tester.widget<SummaryCard>(find.byType(SummaryCard));
      expect(summary.totalIn, sms.currentCycleCredits);
      expect(summary.totalOut, sms.currentCycleDebits);
    },
  );

  testWidgets(
    'Activity refreshes salary-cycle choices on return without dropping its filters',
    (tester) async {
      await open(tester, size: const Size(600, 1400));
      await tab(tester, 'activity');
      await tester.tap(find.byKey(const ValueKey('banks-BANK_A')));
      await tester.pumpAndSettle();
      await tab(tester, 'plan');
      await tester.tap(find.byKey(const ValueKey('destination-salary')));
      await settle(tester);
      await tester.runAsync(
        () => LocalStorageService.markAsSalary('tx-2', true),
      );
      await back(tester);
      await tab(tester, 'activity');
      expect(find.text('All Time'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'All Time'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('banks-BANK_A')))
            .selected,
        isTrue,
      );
      expect(sms.currentCycle, isNotNull);
      await tab(tester, 'home');
      final summary = tester.widget<SummaryCard>(find.byType(SummaryCard));
      expect(summary.subtitle, sms.currentCycleSubtitle);
      expect(summary.txCount, sms.currentCycleTransactions.length);
      expect(sms.scans, 1);
    },
  );

  testWidgets(
    'Activity keeps its scroll position when another primary tab is visited',
    (tester) async {
      await tester.runAsync(() async {
        final now = DateTime.now();
        await LocalStorageService.saveTransactions([
          for (var i = 0; i < 40; i++)
            Transaction(
              id: 'scroll-$i',
              amount: 1,
              type: TransactionType.debit,
              source: PaymentSource.bank,
              sender: 'BANK_A',
              merchant: 'History $i',
              date: now,
              rawMessage: 'payment $i',
            ),
        ]);
      });
      await open(tester);
      await tab(tester, 'activity');
      await tester.drag(
        find.byKey(const PageStorageKey('transactions-0')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      final first = find.byType(TransactionCard).hitTestable().first;
      final id = tester.widget<TransactionCard>(first).tx.id;
      final before = tester.getTopLeft(first).dy;
      await tab(tester, 'insights');
      await tab(tester, 'activity');
      expect(
        tester.getTopLeft(find.byKey(ValueKey('transaction-$id'))).dy,
        closeTo(before, 1),
      );
      expect(sms.scans, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading and permission-error states retain navigation and scan/retry controls',
    (tester) async {
      await tester.runAsync(() async {
        final db = await LocalStorageService.database;
        await db.delete('transactions');
      });
      sms.testLoading = true;
      await tester.pumpWidget(
        ChangeNotifierProvider<SmsService>.value(
          value: sms,
          child: const MaterialApp(home: MainShellScreen()),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      sms.testLoading = false;
      sms.testError = 'SMS permission denied. Please grant it in Settings.';
      sms.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Try Again'), findsOneWidget);
      final scans = sms.scans;
      await tester.tap(find.text('Try Again'));
      await settle(tester);
      expect(sms.scans, scans + 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard in Activity is handled once and dismissing it restores all four destinations',
    (tester) async {
      await open(tester, size: const Size(390, 844));
      await tab(tester, 'activity');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    },
  );
}
