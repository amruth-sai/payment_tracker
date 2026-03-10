# Payment Tracker

A privacy-first Android app that reads your SMS inbox and automatically detects, categorizes, and analyzes all your financial transactions — bank alerts, UPI payments, card purchases, and more.

Built with Flutter. Runs 100% offline. No data ever leaves your device.

---

## Features

### Core
- **Auto-detect payments** from 20+ Indian bank SMS formats (HDFC, SBI, ICICI, Axis, Kotak, etc.)
- **UPI transactions** — Google Pay, PhonePe, Paytm, BHIM
- **Credit/Debit card** purchase detection
- **Net flow summary** — total money in vs money out at a glance
- **Search & filter** — by type (all / money in / money out), full-text search
- **Transaction details** — reference ID, balance after, merchant, account, raw SMS
- **Grouped by date** — Today / Yesterday / older dates
- **Pull to refresh** — re-scans the last 90 days of SMS

### AI-Powered (Optional)
- **Gemini AI parsing** — enter your own Google Gemini API key in Settings to parse complex/unusual bank SMS formats that regex can't handle
- **Fallback** — works fully without AI using rule-based regex parsing

### Account Management
- **Multi-account tracking** — automatically groups transactions by bank account (last 4 digits)
- **Per-account summaries** — credits, debits, balance per account
- **Salary cycle detection** — identifies recurring salary deposits and tracks spending between pay periods

### Smart Budgets
- **Set monthly income** and get AI-suggested budget limits per category using the 50/30/20 rule (needs/wants/savings)
- **Per-category budgets** with progress bars showing real-time usage
- **Budget warnings** at 80% and alerts when overspent
- **Add/edit/delete** budgets manually or apply AI suggestions in one tap

### Category Tagging
- **Auto-categorization** of every transaction using merchant keyword matching (~100+ keywords across 13 categories)
- **Categories**: Food & Dining, Travel, Shopping, Rent & Housing, EMI & Loans, Entertainment, Bills & Utilities, Health, Education, Investment, Transfer, Cashback, Salary/Income
- **Pie chart breakdown** with period selector (7D/30D/90D/All) and drill-down to individual transactions per category

### Spending Heatmap
- **Calendar view** where each day is color-coded by spending intensity (darker red = more spent)
- **Month navigation** with monthly summary (total, average/day, peak day, active days)
- **Tap any day** to see that day's transactions in a bottom sheet

### Merchant Rankings
- **Top merchants** displayed as a bar chart (fl_chart)
- **Period filter** — 7D / 30D / 90D / 1Y
- **Full ranked list** with transaction counts, percentages, and category badges

### EMI Tracker
- **Auto-detects recurring monthly payments** by analyzing merchant + amount patterns with 25–40 day interval matching
- **Monthly EMI burden** summary
- **Payment history** with occurrence dates for each detected EMI

### Alerts & Insights
- **Anomaly detection** — flags merchants where recent spending is 2x+ the historical average
- **Duplicate detection** — alerts if the same amount from the same sender appears within 5 minutes
- **Budget alerts** — notifies when any category crosses 80% of its budget
- **Daily digest** — yesterday's spending summary with weekly budget usage percentage
- **EMI alerts** — flags newly detected recurring payments

### Transaction Notes
- **Add personal notes** to any transaction (e.g., "Birthday dinner", "Office supplies")
- Notes are persisted in the local SQLite database

### Transaction Correction
- **Correct misdetected types** — manually flip credit/debit if the parser got it wrong
- Corrections are marked and preserved

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Flutter 3.x (Android only) |
| Language | Dart 3.x |
| State Management | Provider |
| Local Database | SQLite (sqflite) |
| SMS Reading | another_telephony |
| Charts | fl_chart |
| AI Parsing (optional) | Google Gemini (google_generative_ai) |
| Permissions | permission_handler |

---

## Project Structure

```
lib/
├── main.dart                              # App entry, theme, Provider setup
├── models/
│   ├── transaction.dart                   # Transaction model + TransactionCategory enum
│   ├── account.dart                       # Bank account model
│   ├── budget.dart                        # Budget per category
│   ├── emi.dart                           # Detected recurring EMI payment
│   ├── salary_cycle.dart                  # Salary cycle tracking
│   └── app_alert.dart                     # In-app alert (anomaly, duplicate, budget, digest)
├── services/
│   ├── sms_service.dart                   # SMS reading + state management (ChangeNotifier)
│   ├── sms_parser.dart                    # Regex-based SMS parser (20+ bank formats)
│   ├── ai_sms_parser.dart                 # Google Gemini AI parser (optional)
│   ├── local_storage_service.dart         # SQLite database (v3 schema, all CRUD ops)
│   ├── category_service.dart              # Merchant keyword → category mapping
│   ├── budget_service.dart                # Budget suggestions (50/30/20) + checking
│   ├── anomaly_service.dart               # Anomaly detection, duplicate detection, daily digest
│   └── emi_service.dart                   # Recurring payment detection
├── screens/
│   ├── home_screen.dart                   # Main dashboard with quick actions + alerts
│   ├── all_transactions_screen.dart       # Full transaction list with search
│   ├── accounts_screen.dart               # Per-account summaries
│   ├── salary_cycle_screen.dart           # Salary cycle tracking
│   ├── settings_screen.dart               # AI API key, re-parse, stats
│   ├── spending_breakdown_screen.dart     # Spending by source type
│   ├── category_breakdown_screen.dart     # Pie chart by category
│   ├── budget_screen.dart                 # Budget management + AI suggestions
│   ├── spending_heatmap_screen.dart       # Calendar heatmap
│   ├── merchant_rankings_screen.dart      # Top merchants bar chart
│   ├── emi_tracker_screen.dart            # Detected EMIs list
│   └── alerts_screen.dart                 # Anomalies, duplicates, budget alerts, digest
└── widgets/
    ├── summary_card.dart                  # Net flow summary
    ├── transaction_card.dart              # Transaction list item
    └── transaction_detail_sheet.dart      # Detail bottom sheet with notes + category
```

---

## Getting Started

### Prerequisites
- Flutter SDK 3.x+ ([install guide](https://flutter.dev/docs/get-started/install))
- Android device or emulator (API 21+)
- USB debugging enabled on device

> **Note:** iOS is not supported — Apple restricts SMS access for third-party apps.

### Install & Run

```bash
git clone https://github.com/<your-username>/payment_tracker.git
cd payment_tracker

flutter pub get
flutter run
```

### Build APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## Configuration

### AI Parsing (Optional)

The app works fully without any API key using rule-based regex parsing. To enable AI-powered parsing for non-standard SMS formats:

1. Get a free API key from [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Open the app → Settings → Enter your Gemini API key → Save
3. The key is stored locally on your device in SharedPreferences

> **No API key is hardcoded or included in this repository.** The feature is entirely opt-in.

### Adding a New Bank

In `lib/services/sms_parser.dart`, add the bank's sender ID:

```dart
static const _knownSenders = [
  'HDFCBK', 'SBIINB', ...,
  'MYBANK',  // ← add here
];
```

---

## Privacy

- **100% offline** — no internet required (except optional AI feature)
- **No tracking, no analytics, no crash reporting**
- SMS data is parsed and stored locally in an on-device SQLite database
- AI API key (if used) is stored only in local SharedPreferences on your device
- The app requests only SMS read permission — nothing else

---

## Database Schema

SQLite v3 with the following tables:
- `transactions` — all parsed transactions with category and note fields
- `processed_sms` — tracks which SMS have been parsed (avoids re-processing)
- `accounts` — detected bank accounts
- `salary_cycles` — salary deposit tracking
- `user_settings` — key-value settings store
- `budgets` — per-category monthly budget limits
- `alerts` — in-app alerts (anomalies, duplicates, budget warnings, digest)
- `emis` — detected recurring EMI payments

---

## Troubleshooting

**"No payment messages found"**
- Ensure SMS permission is granted (Settings → Apps → Payment Tracker → Permissions → SMS → Allow)
- Check that your bank's sender ID is in the `_knownSenders` list in `sms_parser.dart`
- Enable AI parsing in Settings for non-standard SMS formats

**Build errors**
```bash
flutter clean
flutter pub get
flutter run
```

---

## License

This project is open source and available under the [MIT License](LICENSE).
