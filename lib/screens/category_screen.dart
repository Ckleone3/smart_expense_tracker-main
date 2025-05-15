import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  _CategoryScreenState createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _incomeController = TextEditingController();
  final TextEditingController _expenseController = TextEditingController();
  final TextEditingController _expensePercentageController = TextEditingController();
  double remainingPercentage = 100.0;

  @override
  void initState() {
    super.initState();
    _updateRemainingPercentage();
  }

  Future<void> _updateRemainingPercentage() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      log('No user signed in - cannot calculate remaining percentage');
      return;
    }
    log('Calculating remaining percentage for user: $userId');
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('categories')
          .where('type', isEqualTo: 'Expense')
          .get();
      double total = 0;
      for (var doc in snapshot.docs) {
        total += (doc['percentage'] as num?)?.toDouble() ?? 0;
      }
      setState(() {
        remainingPercentage = 100.0 - total;
      });
      log('Remaining percentage updated: $remainingPercentage');
    } catch (e) {
      log('Error calculating remaining percentage: $e');
    }
  }

  void _addCategory(String name, String type, {double? percentage}) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      log('No user signed in - cannot add category');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please sign in to add categories')),
      );
      return;
    }

    if (name.isEmpty) {
      log('Empty category name');
      return;
    }

    if (type == 'Expense') {
      if (percentage == null || percentage <= 0 || percentage > remainingPercentage) {
        log('Invalid percentage: $percentage (remaining: $remainingPercentage)');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter a valid percentage (0 < % ≤ $remainingPercentage)')),
        );
        return;
      }
    }

    log('Adding category: $name, type: $type, percentage: $percentage for user: $userId');
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('categories')
          .add({
        'name': name,
        'type': type,
        'percentage': type == 'Expense' ? percentage : null,
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$type category "$name" added')),
      );

      if (type == 'Income') {
        _incomeController.clear();
      } else {
        _expenseController.clear();
        _expensePercentageController.clear();
        await _updateRemainingPercentage();
      }
      log('Category added successfully');
    } catch (e) {
      log('Error adding category: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add category: $e')),
      );
    }
  }

  void _deleteCategory(String categoryId) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Category'),
        content: Text('Are you sure you want to delete this category?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              log('Deleting category ID: $categoryId');
              try {
                await _firestore
                    .collection('users')
                    .doc(userId)
                    .collection('categories')
                    .doc(categoryId)
                    .delete();
                Navigator.pop(context);
                await _updateRemainingPercentage();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Category deleted')),
                );
                log('Category deleted successfully');
              } catch (e) {
                log('Error deleting category: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete category: $e')),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      log('No user signed in - showing sign-in prompt');
      return Scaffold(
        appBar: AppBar(title: Text('Manage Categories')),
        body: Center(child: Text('Please sign in to manage categories')),
      );
    }
    log('Building CategoryScreen for user: $userId');

    return Scaffold(
      appBar: AppBar(title: Text('Manage Categories')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Income Categories', style: Theme.of(context).textTheme.headlineSmall),
            TextField(
              controller: _incomeController,
              decoration: InputDecoration(labelText: 'Add Income Category'),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _addCategory(_incomeController.text, 'Income'),
              child: Text('Add Income Category'),
            ),
            SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('users')
                    .doc(userId)
                    .collection('categories')
                    .where('type', isEqualTo: 'Income')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    log('Income categories stream error: ${snapshot.error}');
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    log('Loading income categories...');
                    return Center(child: CircularProgressIndicator());
                  }
                  final categories = snapshot.data!.docs;
                  log('Loaded ${categories.length} income categories');
                  return ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final doc = categories[index];
                      return ListTile(
                        title: Text(doc['name']),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteCategory(doc.id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SizedBox(height: 16),
            Text('Expense Categories', style: Theme.of(context).textTheme.headlineSmall),
            Text('Remaining Percentage: $remainingPercentage%', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _expenseController,
              decoration: InputDecoration(labelText: 'Add Expense Category'),
            ),
            TextField(
              controller: _expensePercentageController,
              decoration: InputDecoration(labelText: 'Percentage (%)'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _addCategory(
                _expenseController.text,
                'Expense',
                percentage: double.tryParse(_expensePercentageController.text),
              ),
              child: Text('Add Expense Category'),
            ),
            SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('users')
                    .doc(userId)
                    .collection('categories')
                    .where('type', isEqualTo: 'Expense')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    log('Expense categories stream error: ${snapshot.error}');
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    log('Loading expense categories...');
                    return Center(child: CircularProgressIndicator());
                  }
                  final categories = snapshot.data!.docs;
                  log('Loaded ${categories.length} expense categories');
                  return ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final doc = categories[index];
                      final percentage = doc['percentage']?.toDouble() ?? 0.0;
                      return ListTile(
                        title: Text('${doc['name']} ($percentage%)'),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteCategory(doc.id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _incomeController.dispose();
    _expenseController.dispose();
    _expensePercentageController.dispose();
    super.dispose();
  }
}