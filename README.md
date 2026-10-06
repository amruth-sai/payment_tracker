# Payment Tracker

Payment Tracker is a personal Flutter Android app that reads bank and payment
SMS messages, extracts transactions with local rules, and stores everything in
an on-device SQLite database.

## Privacy

- SMS messages are parsed on the device.
- Transaction data is stored in the app's local SQLite database.
- Scans keep local outcome metadata for each SMS. Only payment-like messages
  skipped by the rules retain their body for review; other skipped messages do
  not retain their body in the app database.
- The app has no AI integration, API key, analytics, or network dependency.
- It requests only `READ_SMS`, which is needed to scan existing payment SMS.

## Features

- Rule-based detection of common Indian bank, UPI, wallet, and card SMS
- Transaction search, filtering, correction, notes, tags, and ignored items
- Review inbox for payment SMS with an unclear debit/credit direction, plus local merchant rules
- Restorable ignored review messages and a view of payment-like messages skipped by rules
- A manual path from a skipped payment-like message to the review inbox when its amount could not be read
- Incremental SMS scans and safe rechecks of skipped messages without clearing user edits
- Category source tracking and a preview before refreshing automatic categories
- Merchant cleanup rules for normalizing matching SMS to a merchant, category, and tag
- Disabled merchant suggestions from the transaction export, plus editable templates for recurring payments
- Trip windows selected by dates or boundary transactions, with a preview before assigning one My Category and trip tag to every active transaction in the window
- Salary-month closeouts for income, savings, category changes, recurring payments, and reimbursables
- Password-protected local backups with Android document picker restore, merge, and replace options
- Accounts, salary cycles, budgets for standard or My Categories, category and merchant breakdowns
- Budget coverage review for spending outside saved budgets, with direct category assignment
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
