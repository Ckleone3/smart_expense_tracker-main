# Smart Expense Tracker

A comprehensive mobile application built with Flutter for tracking expenses and managing personal finances efficiently. The app features both cloud-based (Firebase) and local storage options, with a subscription model for enhanced features.

## Features

### 1. Authentication
- Google Sign-in integration
- User registration and login functionality
- Secure authentication using Firebase Auth

### 2. Transaction Management
- **SMS Transaction Processing**: Automatically parse SMS messages for transactions
- **Categorization**: Organize transactions into custom categories
- **Manual Entry**: Add transactions manually when needed
- **Filters**: Sort and filter transactions by date, category, and type

### 3. Categories and Budget Management
- Create and manage income categories
- Set up expense categories with percentage allocations
- Track remaining budget percentages
- Customize categories based on personal needs

### 4. Reports and Analytics
- Visual representations of income and expenses
- Category-wise expense breakdown
- Period-based financial reports
- Allocation tracking and management

### 5. SMS Integration
- Automatic SMS parsing for transactions
- Customizable SMS keywords
- Date range filtering for SMS transactions
- Batch processing capabilities

### 6. Settings and Customization
- Currency preferences
- SMS keyword management
- Category management
- Tutorial access

### 7. Storage Options
#### Cloud Storage (Premium)
- Firebase Firestore integration
- Real-time data synchronization
- Cross-device access
- Secure data backup

#### Local Storage (Free)
- Offline access
- Device-specific storage
- Data privacy
- No internet dependency

## Technical Implementation

### Core Technologies
- Flutter Framework
- Firebase Services
  - Authentication
  - Firestore
  - Cloud Functions
- SQLite/Hive for local storage
- Provider for state management

### Project Structure
```
lib/
├── main.dart
├── models/
├── screens/
│   ├── auth_screens.dart
│   ├── categorized_screen.dart
│   ├── category_screen.dart
│   ├── dashboard_screen.dart
│   ├── reports_screen.dart
│   ├── settings_screen.dart
│   ├── sms_filter_screen.dart
│   └── tutorial_screen.dart
└── services/
    └── sms_service.dart
```

## Getting Started

### Prerequisites
- Flutter SDK
- Firebase project setup
- Android Studio / VS Code
- Google Play Services (for Android)

### Installation
1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Configure Firebase:
   - Add your `google-services.json` for Android
   - Add your `GoogleService-Info.plist` for iOS
4. Run the app:
   ```bash
   flutter run
   ```

### Configuration
1. Set up Firebase project
2. Configure Google Sign-In
3. Add required permissions in Android Manifest
4. Configure SMS permissions
