import 'package:hive_flutter/hive_flutter.dart';
import 'package:smart_expense_tracker/models/expense.dart';
import 'storage_interface.dart';

class LocalStorage implements StorageInterface {
  static const String _boxName = 'expenses';
  late Box<Expense> _box;

  @override
  Future<List<Expense>> getExpenses() => getAllExpenses();

  @override
  Future<void> initialize() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ExpenseAdapter());
    }
    _box = await Hive.openBox<Expense>(_boxName);
  }

  @override
  Future<void> saveExpense(Expense expense) async {
    await _box.put(expense.id, expense);
  }

  @override
  Future<List<Expense>> getAllExpenses() async {
    return _box.values.toList();
  }

  @override
  Future<List<Expense>> getExpensesByDateRange(
      DateTime start, DateTime end) async {
    return _box.values
        .where((expense) =>
            expense.date.isAfter(start.subtract(const Duration(days: 1))) &&
            expense.date.isBefore(end.add(const Duration(days: 1))))
        .toList();
  }

  @override
  Future<void> updateExpense(Expense expense) async {
    await _box.put(expense.id, expense);
  }

  @override
  Future<void> deleteExpense(String id) async {
    await _box.delete(id);
  }

  @override
  Future<List<Expense>> getExpensesByCategory(String category) async {
    return _box.values
        .where((expense) => expense.category == category)
        .toList();
  }

  @override
  Future<double> getTotalExpenses(DateTime start, DateTime end) async {
    final total = _box.values
        .where((expense) =>
            expense.date.isAfter(start.subtract(const Duration(days: 1))) &&
            expense.date.isBefore(end.add(const Duration(days: 1))))
        .fold<double>(0.0, (sum, expense) => sum + expense.amount);
    return total;
  }

  @override
  Future<void> dispose() async {
    await _box.compact();
    await _box.close();
  }
}
