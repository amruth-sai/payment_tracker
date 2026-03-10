# 📱 Payment Tracker — Flutter App

A personal finance app that reads your SMS inbox and automatically detects and lists all incoming and outgoing payments from banks, UPI apps, and card transactions.

---

## ✨ Features

- **Auto-detect payments** from bank SMS alerts (HDFC, SBI, ICICI, Axis, Kotak, etc.)
- **UPI transactions** — Google Pay, PhonePe, Paytm
- **Credit/Debit card** purchases
- **Net flow summary** — total money in vs out at a glance
- **Search & filter** by type (all / money in / money out)
- **Transaction detail** view with reference ID, balance, merchant
- **Grouped by date** (Today / Yesterday / date)
- **Pull to refresh** — re-scans the last 90 days

---

## 🚀 Setup Instructions

### Prerequisites
- Flutter SDK 3.x ([install guide](https://flutter.dev/docs/get-started/install))
- Android Studio or VS Code with Flutter plugin
- Android device or emulator (API 21+)

> ⚠️ **iOS is NOT supported** — Apple restricts SMS access for third-party apps.

---

### 1. Clone / Copy the project

```bash
# If you downloaded the zip, just unzip and cd into it
cd payment_tracker
```

### 2. Add the `provider` package

The `pubspec.yaml` includes these dependencies — run:

```bash
flutter pub get
```

> If `provider` isn't in pubspec.yaml yet, add it:
```yaml
dependencies:
  provider: ^6.1.2
```

### 3. Run on your Android device

```bash
# Connect your phone via USB (enable USB debugging)
flutter run
```

Or build an APK:

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## 🏗️ Project Structure

```
lib/
├── main.dart                          # App entry + theme
├── models/
│   └── transaction.dart               # Transaction data model
├── services/
│   ├── sms_service.dart               # SMS reading + state management
│   └── sms_parser.dart                # Regex-based payment parser
├── screens/
│   ├── home_screen.dart               # Main screen with summary
│   └── all_transactions_screen.dart   # Full list with search & tabs
└── widgets/
    ├── transaction_card.dart          # Individual transaction row
    ├── transaction_detail_sheet.dart  # Bottom sheet with full details
    └── summary_card.dart              # Net flow summary card
```

---

## 🔍 How the SMS Parser Works

The parser (`sms_parser.dart`) uses regex patterns to:

1. **Filter** — only process SMS from known bank sender IDs (e.g. `HDFCBK`, `SBIINB`)
2. **Extract amount** — handles formats like `Rs.1,234.56`, `INR 1234`, `₹5,000`
3. **Detect type** — keywords like `credited`, `debited`, `received`, `paid`
4. **Identify source** — UPI, card, bank transfer, wallet
5. **Extract extras** — merchant name, account last 4 digits, reference ID, balance

### Adding a new bank

In `sms_parser.dart`, add your bank's sender ID to `_knownSenders`:

```dart
static const _knownSenders = [
  'HDFCBK', 'SBIINB', ...,
  'MYBANK',  // ← add here
];
```

---

## 🛡️ Privacy

- **No internet connection required** — everything runs 100% locally on your device
- SMS data never leaves your phone
- No analytics, no crash reporting, no tracking

---

## 📦 Dependencies

| Package | Purpose |
|---------|---------|
| `telephony` | Read SMS inbox on Android |
| `permission_handler` | Runtime SMS permission request |
| `provider` | State management |
| `intl` | Date and number formatting |
| `fl_chart` | (Optional) Charts for spending overview |

---

## 🔧 Troubleshooting

**"No payment messages found"**
- Make sure you granted SMS permission
- Check if your bank SMS sender ID is in `_knownSenders` list
- Some banks use OTP-only numbers — add them manually

**Build errors**
```bash
flutter clean
flutter pub get
flutter run
```

**Permission denied on Android 12+**
- Go to Settings → Apps → Payment Tracker → Permissions → SMS → Allow
