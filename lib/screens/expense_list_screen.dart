import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense.dart';
import '../services/category_service.dart';

class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  _ExpenseListScreenState createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CategoryService _categoryService = CategoryService();
  final Map<String, String?> _selectedCategories = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Expense List')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('expenses').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }

                var expenses = snapshot.data!.docs.map((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  return Expense(
                    id: doc.id,
                    date: data['date'] ?? 'Unknown Date',
                    description: data['description'] ?? 'Unknown',
                    amount: data['amount'] ?? '0.00',
                    category: data['category'],
                  );
                }).toList();

                return ListView.builder(
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    var expense = expenses[index];

                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text("Ksh ${expense.amount} - ${expense.description}",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Date: ${expense.date}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StreamBuilder<List<String>>(
                              stream: _categoryService.getCategories(),
                              builder: (context, categorySnapshot) {
                                if (!categorySnapshot.hasData) {
                                  return CircularProgressIndicator();
                                }

                                return DropdownButton<String>(
                                  value: _selectedCategories[expense.id] ?? expense.category,
                                  hint: Text('Select Category'),
                                  items: categorySnapshot.data!.map((category) {
                                    return DropdownMenuItem(
                                      value: category,
                                      child: Text(category),
                                    );
                                  }).toList(),
                                  onChanged: (newCategory) {
                                    setState(() {
                                      _selectedCategories[expense.id] = newCategory;
                                    });
                                    _firestore.collection('expenses').doc(expense.id).update({
                                      'category': newCategory
                                    });
                                  },
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                _firestore.collection('expenses').doc(expense.id).delete();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
