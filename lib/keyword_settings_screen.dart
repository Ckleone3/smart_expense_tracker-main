import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:smart_expense_tracker/services/sms_service.dart';
import 'dart:developer';

class KeywordSettingsScreen extends StatefulWidget {
  const KeywordSettingsScreen({super.key});

  @override
  _KeywordSettingsScreenState createState() => _KeywordSettingsScreenState();
}

class _KeywordSettingsScreenState extends State<KeywordSettingsScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final smsService = Provider.of<SmsService>(context, listen: false);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    log('KeywordSettingsScreen: User ID = $userId');

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SMS Keywords')),
        body: const Center(child: Text('Please sign in to manage keywords')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Keywords'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Add Keyword (e.g., Ksh, M-PESA)',
                      border: OutlineInputBorder(),
                      hintText:
                          'Max 20 keywords', // Updated from 'Max 10 keywords'
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final keyword = _controller.text.trim();
                    if (keyword.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a keyword')),
                      );
                      return;
                    }
                    try {
                      await smsService.addKeyword(keyword);
                      _controller.clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Keyword added: $keyword')),
                      );
                    } catch (e) {
                      log('Add keyword failed: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to add keyword: $e')),
                      );
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('sms_keywords')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  log('Stream error: ${snapshot.error}');
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final keywords = snapshot.data!.docs;
                log('Loaded ${keywords.length} keywords');
                if (keywords.isEmpty) {
                  return const Center(
                    child: Text(
                      'No keywords added yet',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: keywords.length,
                  itemBuilder: (context, index) {
                    final doc = keywords[index];
                    final keyword = doc['keyword'] as String;
                    return ListTile(
                      title: Text(keyword),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          try {
                            await smsService.deleteKeyword(doc.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Keyword deleted: $keyword')),
                            );
                          } catch (e) {
                            log('Delete keyword failed: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text('Failed to delete keyword: $e')),
                            );
                          }
                        },
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
