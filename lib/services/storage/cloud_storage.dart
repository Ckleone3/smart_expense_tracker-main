import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_expense_tracker/models/expense.dart';
import 'storage_interface.dart';

class CloudStorage implements StorageInterface {
  @override
  Future<List<Expense>> getExpenses() => getAllExpenses();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final CollectionReference<Map<String, dynamic>> _expenses;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Future<void> initialize() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to use cloud storage');
    }
    _expenses = _firestore.collection('users/${user.uid}/expenses');
  }

  @override
  Future<void> saveExpense(Expense expense) async {
    await _expenses.doc(expense.id).set(expense.toJson());
  }

  @override
  Future<List<Expense>> getAllExpenses() async {
    final snapshot = await _expenses.get();
    return snapshot.docs
        .map((doc) => Expense.fromJson(doc.data()))
        .toList();
  }

  @override
  Future<List<Expense>> getExpensesByDateRange(
      DateTime start, DateTime end) async {
    final snapshot = await _expenses
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThanOrEqualTo: end)
        .get();
    return snapshot.docs
        .map((doc) => Expense.fromJson(doc.data()))
        .toList();
  }

  @override
  Future<void> updateExpense(Expense expense) async {
    await _expenses.doc(expense.id).update(expense.toJson());
  }

  @override
  Future<void> deleteExpense(String id) async {
    await _expenses.doc(id).delete();
  }

  @override
  Future<List<Expense>> getExpensesByCategory(String category) async {
    final snapshot =
        await _expenses.where('category', isEqualTo: category).get();
    return snapshot.docs
        .map((doc) => Expense.fromJson(doc.data()))
        .toList();
  }

  @override
  Future<double> getTotalExpenses(DateTime start, DateTime end) async {
    final expensesList = await getExpensesByDateRange(start, end);
    final total =
        expensesList.fold<double>(0.0, (sum, expense) => sum + expense.amount);
    return total;
  }

  @override
  Future<void> dispose() async {
    // No cleanup needed for Firestore
  }
}
