# Payment Tracker

Payment Tracker is a personal Flutter Android app that reads bank and payment
SMS messages, extracts transactions with local rules, and stores everything in
an on-device SQLite database.

## Privacy

- SMS messages are parsed on the device.
- Transaction data is stored in the app's local SQLite database.
- The app has no AI integration, API key, analytics, or network dependency.
- It requests only `READ_SMS`, which is needed to scan existing payment SMS.

## Features

- Rule-based detection of common Indian bank, UPI, wallet, and card SMS
- Transaction search, filtering, correction, notes, tags, and ignored items
- Review inbox for payment SMS with an unclear debit/credit direction, plus local merchant rules
- Accounts, salary cycles, budgets, category and merchant breakdowns
- Spending heatmap, recurring EMI detection, alerts, and transfer grouping
- User-defined categories and a configurable tracking start point
- JSON export of all active transactions, a selected period, or a salary month
  with categories, tags, and notes for sharing

## Stack

| Area | Technology |
| --- | --- |
| UI | Flutter / Material 3 |
| State | Provider |
| Storage | SQLite (`sqflite`) |
| SMS access | `another_telephony` |
| Charts | `fl_chart` |

## Run

```bash
flutter pub get
flutter run
```

## Test

```bash
flutter analyze
flutter test
```

## Notes

The Android application ID and release signing configuration are still the
default development values. Set a unique application ID and provide your own
signing configuration before distributing a release APK.

The export option uses Android's share sheet. It excludes ignored transactions,
raw SMS messages, balances, and payment reference IDs.
