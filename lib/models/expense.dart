class Expense {
  String id;
  String date;
  String description;
  String amount;
  String? category;

  Expense({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    this.category,
  });

  factory Expense.fromFirestore(Map<String, dynamic> data, String documentId) {
    return Expense(
      id: documentId,
      date: data['date'] ?? 'Unknown Date',
      description: data['description'] ?? 'Unknown',
      amount: data['amount'] ?? '0.00',
      category: data['category'], // May be null
    );
  }
}
