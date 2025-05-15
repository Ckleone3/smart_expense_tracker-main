import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addCategory(String categoryName) async {
    await _firestore.collection('categories').add({"name": categoryName});
  }

  Stream<List<String>> getCategories() {
    return _firestore.collection('categories').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => doc['name'].toString()).toList();
    });
  }
}
