import 'package:smart_expense_tracker/models/expense.dart';

/// Base interface for all storage implementations
abstract class StorageInterface {
  /// Initialize the storage
  Future<void> initialize();

  /// Store an expense
  Future<void> saveExpense(Expense expense);

  /// Get all expenses
  Future<List<Expense>> getAllExpenses();

  /// Alias for getAllExpenses for compatibility with migration tests
  Future<List<Expense>> getExpenses() => getAllExpenses();

  /// Get expenses for a specific time range
  Future<List<Expense>> getExpensesByDateRange(DateTime start, DateTime end);

  /// Update an expense
  Future<void> updateExpense(Expense expense);

  /// Delete an expense
  Future<void> deleteExpense(String id);

  /// Get expenses by category
  Future<List<Expense>> getExpensesByCategory(String category);

  /// Get total expenses for a time period
  Future<double> getTotalExpenses(DateTime start, DateTime end);

  /// Close/cleanup storage
  Future<void> dispose();
}
