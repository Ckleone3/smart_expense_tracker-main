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
  late final StreamSubscription<SubscriptionTier> _tierSubscription;

  StorageType _currentStorageType = StorageType.local;
  bool _isPremium = false;

  StorageType get currentStorageType => _currentStorageType;
  bool get isPremium => _isPremium;

  /// Constructor: takes an optional SubscriptionService for DI.
  StorageService({SubscriptionService? subscriptionService})
      : _subscriptionService = subscriptionService ?? SubscriptionService() {
    _storage = LocalStorage();
    _initialize();
    _listenToSubscriptionChanges();
  }

  /// Initialize local storage first.
  Future<void> _initialize() async {
    await _storage.initialize();
  }

  /// Subscribes to subscription tier changes.
  void _listenToSubscriptionChanges() {
    _tierSubscription = _subscriptionService.tierStream().listen((tier) async {
      final wasPremium = _isPremium;
      _isPremium = tier == SubscriptionTier.premium;

      // If subscription status changed:
      if (wasPremium != _isPremium) {
        // If user lost premium access but was using cloud, migrate back local
        if (!_isPremium && _currentStorageType == StorageType.cloud) {
          await setStorageType(StorageType.local);
        }
        notifyListeners();
      }
    });
  }

  /// Switches storage backend, migrating data as needed.
  Future<void> setStorageType(StorageType type) async {
    if (type == StorageType.cloud && !_isPremium) {
      throw Exception('Cloud storage is only available for premium users');
    }

    if (type != _currentStorageType) {
      final oldStorage = _storage;
      final newStorage =
          type == StorageType.local ? LocalStorage() : CloudStorage();

      try {
        // Migrate data between storages
        if (oldStorage is LocalStorage && newStorage is CloudStorage) {
          await StorageMigrationService.migrateToCloud(oldStorage, newStorage);
        } else if (oldStorage is CloudStorage && newStorage is LocalStorage) {
          await StorageMigrationService.migrateToLocal(oldStorage, newStorage);
        }

        await oldStorage.dispose();
        _storage = newStorage;
        _currentStorageType = type;
        notifyListeners();
      } catch (e) {
        // Rollback on failure
        await newStorage.dispose();
        throw Exception('Failed to migrate data: $e');
      }
    }
  }

  /// Delegated expense operations
  Future<void> saveExpense(Expense expense) async {
    await _storage.saveExpense(expense);
    notifyListeners();
  }

  Future<List<Expense>> getAllExpenses() async {
    return _storage.getAllExpenses();
  }

  Future<List<Expense>> getExpensesByDateRange(
      DateTime start, DateTime end) async {
    return _storage.getExpensesByDateRange(start, end);
  }

  Future<void> updateExpense(Expense expense) async {
    await _storage.updateExpense(expense);
    notifyListeners();
  }

  Future<void> deleteExpense(String id) async {
    await _storage.deleteExpense(id);
    notifyListeners();
  }

  Future<List<Expense>> getExpensesByCategory(String category) async {
    return _storage.getExpensesByCategory(category);
  }

  Future<double> getTotalExpenses(DateTime start, DateTime end) async {
    return _storage.getTotalExpenses(start, end);
  }

  @override
  Future<void> dispose() async {
    await _tierSubscription.cancel();
    await _storage.dispose();
    super.dispose();
  }
}
