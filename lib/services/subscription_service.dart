import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Your subscription tiers.
enum SubscriptionTier {
  free,
  premium,
}

/// Manages reading/updating subscription status in Firestore,
/// and exposes a real‐time stream of the current tier.
class SubscriptionService extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  SubscriptionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Emits the current tier and updates automatically whenever the
  /// Firestore `status` doc changes.
  Stream<SubscriptionTier> tierStream() async* {
    final user = _auth.currentUser;
    if (user == null) {
      yield SubscriptionTier.free;
      return;
    }
    yield* _firestore
        .collection('users')
        .doc(user.uid)
        .collection('subscription')
        .doc('status')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return SubscriptionTier.free;
      return (doc.data()?['tier'] == 'premium')
          ? SubscriptionTier.premium
          : SubscriptionTier.free;
    });
  }

  /// Switch to Premium in Firestore
  Future<void> upgradeToPremium() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in to upgrade');
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('subscription')
        .doc('status')
        .set({
      'tier': 'premium',
      'startDate': FieldValue.serverTimestamp(),
      'active': true,
    });
  }

  /// Switch back to Free in Firestore
  Future<void> downgradeToFree() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in to downgrade');
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('subscription')
        .doc('status')
        .set({
      'tier': 'free',
      'endDate': FieldValue.serverTimestamp(),
      'active': false,
    });
  }
}
