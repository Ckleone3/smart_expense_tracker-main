# Smart Expense Tracker – Developer Guide

## Overview
Smart Expense Tracker is a Flutter-based mobile app for personal finance management. It supports both free (local/Hive) and premium (cloud/Firestore) storage, with features for SMS-based transaction parsing, manual entry, categorization (Income/Expense), reporting, and a subscription model. This guide is for developers who want to understand, set up, and extend the app.

---

## Architecture & Project Structure

- **Flutter**: UI, navigation, and business logic
- **Provider**: State management
- **Firebase**: Auth, Firestore (cloud storage, premium)
- **Hive**: Local storage (free tier)
- **Key Directories:**
  - `lib/main.dart`: App entry, navigation, global setup
  - `lib/models/expense.dart`: Transaction/expense model
  - `lib/screens/`: UI screens (auth, uncategorized/categorized, reports, settings, etc.)
  - `lib/services/`: Core services
    - `subscription_service.dart`: Subscription tier logic
    - `sms_service.dart`: SMS parsing, local transaction logic (Hive)
    - `storage/`: Storage abstraction, migration, and backend switching

---

## Main Features & Flows

### 1. Authentication
- Google Sign-In and Firebase Auth
- User registration/login

### 2. Transaction Management
- **SMS Parsing**: Reads device SMS, extracts transactions using keywords
- **Manual Entry**: Add transactions manually
- **Categorization**: Assign Income/Expense and custom categories
- **Filtering**: By date, type, and category

### 3. Categories & Budget
- Create/edit/delete categories (Income/Expense)
- Set expense category percentages (must total 100% for allocations)

### 4. Reports & Analytics
- Visual breakdowns (charts, lists)
- Category-wise and period-based reports
- Allocation tracking

### 5. SMS Integration
- Customizable keywords
- Date/range-based SMS fetching
- Batch processing

### 6. Settings & Customization
- Currency selection
- Manage SMS keywords
- Category management
- Access tutorial

### 7. Subscription Management
- Free: Local (Hive) storage, device-only
- Premium: Cloud (Firestore), sync, backup, advanced reports
- Seamless upgrade/downgrade, trial support

### 8. Storage Options
- **Local (Hive)**: Used for free users, all transaction logic (including categorization/type) is preserved
- **Cloud (Firestore)**: Used for premium users, with real-time sync and backup
- **Automatic migration**: On tier change, data is migrated between Hive and Firestore

---

## State Management
- **Provider**: Used for SubscriptionService, SmsService, StorageService, etc.
- **Streams**: Real-time updates for subscription tier, transactions, etc.

---

## Key Dependencies
- `firebase_core`, `firebase_auth`, `cloud_firestore`: Firebase integration
- `google_sign_in`: Google Auth
- `hive`, `hive_flutter`: Local storage
- `provider`: State management
- `flutter_sms_inbox`, `permission_handler`: SMS reading
- `intl`: Date formatting

---

## Main Files & Responsibilities
- `main.dart`: App root, navigation, onboarding, global providers
- `screens/auth_screens.dart`: Login, registration, welcome
- `screens/uncategorized_screen.dart`: Shows uncategorized transactions (local for free, Firestore for premium)
- `screens/categorized_screen.dart`: Categorized transactions, tabs for Income/Expense/Allocations
- `screens/category_screen.dart`: Category management
- `screens/reports_screen.dart`: Reports and analytics
- `screens/settings_screen.dart`: Settings, currency, keywords, tutorial, subscription
- `services/subscription_service.dart`: Tier detection, upgrade/downgrade, stream
- `services/sms_service.dart`: SMS parsing, local transaction CRUD (Hive), keyword logic
- `services/storage/storage_service.dart`: Storage backend switching, migration, unified API

---

## Setup & Running (Developer)

1. **Clone the repo**
2. **Install dependencies**: `flutter pub get`
3. **Configure Firebase**:
   - Add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Enable Auth and Firestore in Firebase console
4. **Set permissions**:
   - Android: SMS, internet, etc. in `AndroidManifest.xml`
5. **Run the app**: `flutter run`

---

## Extending the App
- **Add new features**: Create new screens/services in `lib/screens` or `lib/services`
- **Add new storage logic**: Implement in `lib/services/storage/`
- **Add new categories or reports**: Update models and UI screens
- **UI changes**: Update widgets in `lib/screens/`
- **State management**: Use Provider for new services

---

## Notes
- All transaction logic (including categorization/type) is preserved for both local (free) and cloud (premium) users.
- Data migration is automatic on subscription tier change.
- SMS parsing and keyword logic is shared for both storage types.
- For any changes, ensure both storage backends are supported and tested.

---

## Contact & Contribution
- Fork, branch, and submit PRs for improvements.
- For issues, use the repository's issue tracker.

---

*This guide is for developers. For user instructions, see the main README.*
