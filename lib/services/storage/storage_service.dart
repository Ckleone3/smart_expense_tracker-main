import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_expense_tracker/models/expense.dart';
import 'package:smart_expense_tracker/services/subscription_service.dart';
import 'local_storage.dart';
import 'cloud_storage.dart';
import 'storage_interface.dart';
import 'storage_migration_service.dart';

/// Defines available storage backends.
enum StorageType { local, cloud }

/// Manages switching between local and cloud storage based on subscription status.
/// Listens to SubscriptionService's tierStream for real-time updates.
class StorageService extends ChangeNotifier {
  late StorageInterface _storage;
  final SubscriptionService _subscriptionService;
  StreamSubscription<SubscriptionTier>? _tierSubscription;

  StorageType _currentStorageType = StorageType.local;
  bool _isPremium = false;

  StorageType get currentStorageType => _currentStorageType;
  bool get isPremium => _isPremium;

  /// Constructor: takes an optional SubscriptionService for DI.
  StorageService({SubscriptionService? subscriptionService})
      : _subscriptionService = subscriptionService ?? SubscriptionService() {
    // Initialize local storage, then subscribe
    _storage = LocalStorage();
    _initialize().then((_) {
      _subscribeToTierChanges();
    });
  }

  /// Initialize the starting storage backend.
  Future<void> _initialize() async {
    try {
      await _storage.initialize();
      debugPrint('StorageService: storage initialized (${_currentStorageType})');
    } catch (e, st) {
      debugPrint('StorageService initialization error: $e');
      debugPrint('$st');
    }
  }

  /// Subscribes to subscription tier changes after initialization.
  void _subscribeToTierChanges() {
    _tierSubscription = _subscriptionService.tierStream().listen(
      (tier) {
        _handleTierChange(tier);
      },
      onError: (error) {
        debugPrint('Error in subscription tier stream: $error');
      },
    );
  }

  /// Handles migration based on new tier value.
  Future<void> _handleTierChange(SubscriptionTier tier) async {
    final wasPremium = _isPremium;
    _isPremium = tier == SubscriptionTier.premium;

    if (wasPremium != _isPremium) {
      try {
        if (_isPremium && _currentStorageType == StorageType.local) {
          // Upgrade to cloud
          await setStorageType(StorageType.cloud);
        } else if (!_isPremium && _currentStorageType == StorageType.cloud) {
          // Downgrade to local
          await setStorageType(StorageType.local);
        }
      } catch (e) {
        debugPrint('Storage migration failed: $e');
      }
      notifyListeners();
    }
  }

  /// Switch storage backend, migrating data as needed.
  Future<void> setStorageType(StorageType type) async {
    if (type == StorageType.cloud && !_isPremium) {
      throw Exception('Cloud storage is only available for premium users');
    }
    if (type == _currentStorageType) return;

    final oldStorage = _storage;
    final newStorage = type == StorageType.local ? LocalStorage() : CloudStorage();

    try {
      // Ensure the new storage is ready to receive data
      await newStorage.initialize();

      // Perform migration
      if (oldStorage is LocalStorage && newStorage is CloudStorage) {
        await StorageMigrationService.migrateToCloud(oldStorage, newStorage);
      } else if (oldStorage is CloudStorage && newStorage is LocalStorage) {
        await StorageMigrationService.migrateToLocal(oldStorage, newStorage);
      }

      // Swap and clean up
      await oldStorage.dispose();
      _storage = newStorage;
      _currentStorageType = type;
      debugPrint('StorageService: migrated to $_currentStorageType');
    } catch (e) {
      // If migration fails, roll back
      await newStorage.dispose();
      debugPrint('Failed to migrate data: $e');
      throw Exception('Failed to migrate data: $e');
    }
    notifyListeners();
  }

  /// Delegated expense operations
  Future<void> saveExpense(Expense expense) async {
    await _storage.saveExpense(expense);
    notifyListeners();
  }

  Future<List<Expense>> getAllExpenses() async => _storage.getAllExpenses();

  Future<List<Expense>> getExpensesByDateRange(DateTime start, DateTime end) async =>
      _storage.getExpensesByDateRange(start, end);

  Future<void> updateExpense(Expense expense) async {
    await _storage.updateExpense(expense);
    notifyListeners();
  }

  Future<void> deleteExpense(String id) async {
    await _storage.deleteExpense(id);
    notifyListeners();
  }

  Future<List<Expense>> getExpensesByCategory(String category) async =>
      _storage.getExpensesByCategory(category);

  Future<double> getTotalExpenses(DateTime start, DateTime end) async =>
      _storage.getTotalExpenses(start, end);

  @override
  Future<void> dispose() async {
    await _tierSubscription?.cancel();
    await _storage.dispose();
    super.dispose();
  }
}
