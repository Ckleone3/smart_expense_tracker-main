import 'package:smart_expense_tracker/services/storage/storage_interface.dart';
import 'package:smart_expense_tracker/services/storage/cloud_storage.dart';
import 'package:smart_expense_tracker/services/storage/local_storage.dart';

class StorageMigrationService {
  /// Migrate data from one storage type to another
  static Future<void> migrateData(
      StorageInterface from, StorageInterface to) async {
    // Get all expenses from source
    final expenses = await from.getAllExpenses();

    // Initialize destination storage
    await to.initialize();

    // Transfer each expense
    for (final expense in expenses) {
      await to.saveExpense(expense);
    }
  }

  /// Migrate from local to cloud storage
  static Future<void> migrateToCloud(
      LocalStorage localStorage, CloudStorage cloudStorage) async {
    await migrateData(localStorage, cloudStorage);
  }

  /// Migrate from cloud to local storage
  static Future<void> migrateToLocal(
      CloudStorage cloudStorage, LocalStorage localStorage) async {
    await migrateData(cloudStorage, localStorage);
  }
}
