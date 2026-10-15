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
- It requests `READ_SMS` to scan existing payment SMS; unused location/send/receive permissions are removed from the merged manifest. Debug builds also use Internet permission for Flutter tooling.
- Android automatic backup and device-transfer extraction are disabled. Explicit backups are password-encrypted.

## Features

- Rule-based detection of common Indian bank, UPI, wallet, and card SMS
- Transaction search, filtering, correction, notes, tags, and ignored items
- Review inbox for payment SMS with an unclear debit/credit direction, plus local merchant rules
- Restorable ignored review messages and a view of payment-like messages skipped by rules
- A manual path from a skipped payment-like message to the review inbox when its amount could not be read
- Incremental SMS scans and safe rechecks of skipped messages without clearing user edits
- One user-owned category list, with no preinstalled categories or merchant rules
- Category source tracking and a preview before applying user merchant rules
- Merchant cleanup rules for normalizing matching SMS to a merchant, category, and tag
- Trip windows selected by dates or boundary transactions, with a preview before assigning one category and trip tag to every active transaction in the window
- Salary-month closeouts for income, savings, category changes, recurring payments, and reimbursables
- Password-protected local backups with Android document picker restore, merge, and replace options
- Accounts, salary cycles, budgets linked to user-created categories, category and merchant breakdowns
- Budget coverage review for spending outside saved budgets, with direct category assignment
- Spending heatmap, recurring EMI detection, alerts, and transfer grouping
- User-defined categories and a configurable tracking start point
- JSON export of all active transactions, a selected period, or a salary month
  with categories, tags, and notes for sharing

## First-release data model

The app, database, parser and backup formats start at version 1. The database is
`payment_tracker_release.db`, created directly from the new schema. This version
is for a fresh installation: it does not migrate development databases or restore
older backup formats.

Create categories from **Categories** on Home. Rename or delete any category;
transactions use the same category in budgets, rules, filters and reports.
Deleting a category keeps payments and notes, clears their category, removes its
budget, and clears that category from merchant rules. Uncategorized is a display
state, not a protected category. Salary and internal transfers use separate fields.

Amounts persist as integer paise, with foreign keys enabled. The regression suite
covers category deletion/renaming, account updates, backup rollback, salary-period
boundaries, failed/refund/card parsing, stable SMS identities and transfers across
midnight. Backups use an atomic snapshot and background Android encryption/file I/O.

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
# Flutter 3.41+ / Dart 3.11+
flutter pub get
flutter run
```

## Test

```bash
flutter analyze
flutter test
flutter build apk --debug
```

GitHub Actions runs analysis, tests, and the debug Android build on pushes and pull requests.

SQLite integration tests use `sqflite_common_ffi` with sqlite3 v2 to accommodate
Windows SDK paths containing spaces. Linux test runners need libsqlite3.

## Notes

See [Message Parsing and Interpretation](MESSAGE_PARSING.md) for the SMS
processing flow, extraction rules, debit and credit logic, review decisions,
and examples.

The Android application ID and release signing configuration are still the
default development values. Set a unique application ID and provide your own
signing configuration before distributing a release APK.

The export option uses Android's share sheet. It excludes ignored transactions,
raw SMS messages, balances, and payment reference IDs.


## Remaining release work

The correctness fixes and fresh category/schema design are implemented. Before
store distribution, choose the final application ID and configure a private
release signing key. Test SMS permission denial, real message templates, and
backup save/restore/cancellation on a physical Android device. Further structural
improvements include splitting the large storage service into focused
repositories and making report loading/error handling reusable. The separate
FEATURES document is a broader product roadmap, not a claim of implemented scope.
