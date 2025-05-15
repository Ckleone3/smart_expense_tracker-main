import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'expense.g.dart';

@HiveType(typeId: 0)
class Expense extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime date;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final double amount;

  @HiveField(4)
  final String category;

  @HiveField(5)
  final String type; // 'Income' or 'Expense'

  @HiveField(6)
  final String currency;

  Expense({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.category,
    required this.type,
    required this.currency,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
      'description': description,
      'amount': amount,
      'category': category,
      'type': type,
      'currency': currency,
    };
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'],
      date: json['date'] is Timestamp
          ? (json['date'] as Timestamp).toDate()
          : json['date'] is DateTime
              ? json['date']
              : DateTime.parse(json['date'].toString()),
      description: json['description'],
      amount: (json['amount'] as num).toDouble(),
      category: json['category'],
      type: json['type'],
      currency: json['currency'] ?? 'USD',
    );
  }
}
