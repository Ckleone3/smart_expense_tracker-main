import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Helpers for putting a transaction into one of the user's own (Firestore)
/// categories, with the same rules as the To Sort screen:
/// * Expense: the category must have enough allocated money left.
/// * Income: expense category percentages must total 100%, and the income is
///   allocated across them.
class PersonalCategories {
  PersonalCategories._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>>? _col(String name) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection(name);
  }

  /// Category names of the given type ('Income' or 'Expense').
  static Future<List<String>> names(String type) async {
    final col = _col('categories');
    if (col == null) return [];
    final snap = await col.where('type', isEqualTo: type).get();
    return snap.docs
        .map((d) => d.data()['name'])
        .whereType<String>()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Returns a message explaining why [total] can't go into [category], or
  /// null if it can.
  static Future<String?> check(
      {required bool income, required String category, required double total}) async {
    if (_col('categories') == null) return 'Sign in to use your categories.';
    if (income) {
      final snap =
          await _col('categories')!.where('type', isEqualTo: 'Expense').get();
      final pct = snap.docs.fold<double>(
          0, (s, d) => s + ((d.data()['percentage'] as num?)?.toDouble() ?? 0));
      if (pct != 100) {
        return 'Expense categories must total 100% to categorize income '
            '(now ${pct.toStringAsFixed(0)}%).';
      }
      return null;
    }
    final alloc =
        await _col('allocations')!.where('categoryId', isEqualTo: category).get();
    final spent = await _col('transactions')!
        .where('type', isEqualTo: 'Expense')
        .where('categoryId', isEqualTo: category)
        .get();
    double a = 0, s = 0;
    for (final d in alloc.docs) {
      a += (d.data()['amount'] as num?)?.toDouble() ?? 0;
    }
    for (final d in spent.docs) {
      s += (d.data()['amount'] as num?)?.toDouble() ?? 0;
    }
    final left = a - s;
    if (left - total < 0) {
      return 'Insufficient funds in $category '
          '(Ksh ${left.toStringAsFixed(2)} left).';
    }
    return null;
  }

  /// Splits an income across the expense categories by their percentages.
  static Future<void> allocateIncome(String txId, double amount) async {
    final cats =
        await _col('categories')!.where('type', isEqualTo: 'Expense').get();
    for (final doc in cats.docs) {
      final data = doc.data();
      final perc = (data['percentage'] as num?)?.toDouble() ?? 0;
      await _col('allocations')!.add({
        'transactionId': txId,
        'categoryId': data['name'],
        'amount': amount * perc / 100,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Removes the allocations made for an income (used by undo).
  static Future<void> removeAllocations(String txId) async {
    final col = _col('allocations');
    if (col == null) return;
    final snap = await col.where('transactionId', isEqualTo: txId).get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
  }
}
