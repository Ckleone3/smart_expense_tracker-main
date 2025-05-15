import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smart_expense_tracker/models/expense.dart';

void main() {
  group('Expense', () {
    final now = DateTime.now();
    final testExpense = Expense(
      id: '123',
      date: now,
      description: 'Test expense',
      amount: 100.0,
      category: 'Food',
      type: 'Expense',
      currency: 'USD',
    );

    test('should create Expense instance with correct values', () {
      expect(testExpense.id, '123');
      expect(testExpense.date, now);
      expect(testExpense.description, 'Test expense');
      expect(testExpense.amount, 100.0);
      expect(testExpense.category, 'Food');
      expect(testExpense.type, 'Expense');
      expect(testExpense.currency, 'USD');
    });

    test('should convert to JSON correctly', () {
      final json = testExpense.toJson();

      expect(json['id'], '123');
      expect(json['date'], now);
      expect(json['description'], 'Test expense');
      expect(json['amount'], 100.0);
      expect(json['category'], 'Food');
      expect(json['type'], 'Expense');
      expect(json['currency'], 'USD');
    });

    test('should create from JSON correctly', () {
      final json = {
        'id': '123',
        'date': now,
        'description': 'Test expense',
        'amount': 100.0,
        'category': 'Food',
        'type': 'Expense',
        'currency': 'USD',
      };

      final expense = Expense.fromJson(json);

      expect(expense.id, '123');
      expect(expense.date, now);
      expect(expense.description, 'Test expense');
      expect(expense.amount, 100.0);
      expect(expense.category, 'Food');
      expect(expense.type, 'Expense');
      expect(expense.currency, 'USD');
    });

    test('should handle Firestore Timestamp in fromJson', () {
      final timestamp = Timestamp.fromDate(now);
      final json = {
        'id': '123',
        'date': timestamp,
        'description': 'Test expense',
        'amount': 100.0,
        'category': 'Food',
        'type': 'Expense',
        'currency': 'USD',
      };

      final expense = Expense.fromJson(json);

      expect(expense.date, now);
    });

    test('should handle string date in fromJson', () {
      final json = {
        'id': '123',
        'date': now.toIso8601String(),
        'description': 'Test expense',
        'amount': 100.0,
        'category': 'Food',
        'type': 'Expense',
        'currency': 'USD',
      };

      final expense = Expense.fromJson(json);

      expect(expense.date, now);
    });

    test('should use default currency when not provided in JSON', () {
      final json = {
        'id': '123',
        'date': now,
        'description': 'Test expense',
        'amount': 100.0,
        'category': 'Food',
        'type': 'Expense',
      };

      final expense = Expense.fromJson(json);

      expect(expense.currency, 'USD');
    });
  });
}
