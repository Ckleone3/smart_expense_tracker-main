import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer';

class CurrencySettingsScreen extends StatefulWidget {
  const CurrencySettingsScreen({super.key});

  @override
  _CurrencySettingsScreenState createState() => _CurrencySettingsScreenState();
}

class _CurrencySettingsScreenState extends State<CurrencySettingsScreen> {
  String? _selectedCurrency;
  final List<String> _currencies = [
    'USD', // United States Dollar
    'EUR', // Euro
    'GBP', // British Pound
    'JPY', // Japanese Yen
    'KES', // Kenyan Shilling
    'INR', // Indian Rupee
    'CAD', // Canadian Dollar
    'AUD', // Australian Dollar
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentCurrency();
  }

  Future<void> _loadCurrentCurrency() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('settings')
          .doc('currency')
          .get();
      if (doc.exists) {
        setState(() {
          _selectedCurrency = doc['currency'] as String?;
        });
      } else {
        setState(() {
          _selectedCurrency = 'USD'; // Default currency
        });
      }
    }
  }

  Future<void> _saveCurrency(String currency) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('settings')
          .doc('currency')
          .set({
        'currency': currency,
        'timestamp': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Currency set to $currency')),
      );
    } catch (e) {
      log('Failed to save currency: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save currency: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Currency Settings')),
        body: const Center(child: Text('Please sign in to manage currency')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Currency Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select your preferred currency:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCurrency,
              decoration: const InputDecoration(
                labelText: 'Currency',
                border: OutlineInputBorder(),
              ),
              items: _currencies.map((currency) {
                return DropdownMenuItem<String>(
                  value: currency,
                  child: Text(currency),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCurrency = value;
                });
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _selectedCurrency != null
                  ? () => _saveCurrency(_selectedCurrency!)
                  : null,
              child: const Text('Save Currency'),
            ),
          ],
        ),
      ),
    );
  }
}