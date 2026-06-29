import 'dart:developer';
import 'dart:math' show Random;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google accounts that act as the developer/owner (admin). These bypass
/// activation and can manage keys. Keep ONLY the email(s) you sign into the
/// app with. Must match the matching list in firestore.rules.
const Set<String> kAdminEmails = {
  'lckipling@gmail.com',
  'cheruiyotleonard3@gmail.com',
};

bool isAdminUser() {
  final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
  return email != null && kAdminEmails.contains(email);
}

/// Outcome of an activation attempt.
enum ActivationResult {
  success,
  invalidKey, // key doesn't exist
  inactive, // key disabled by developer
  usedOnAnotherDevice, // key already bound to a different phone
  notSignedIn,
  networkError,
}

/// Device-locked licensing: each activation key binds to one device.
///
/// A reshared APK on a different phone has no valid/unused key, so it cannot
/// activate — the user is told to contact the developer.
class LicenseService {
  static const _channel = MethodChannel('rent_capture');
  static const _kKey = 'license_key';
  static const _kDevice = 'license_device';

  final FirebaseFirestore _firestore;
  LicenseService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<String> deviceId() async {
    try {
      final id = await _channel.invokeMethod<String>('getDeviceId');
      return id ?? '';
    } catch (_) {
      return '';
    }
  }

  /// True if this device was already activated (validated once, then trusted
  /// offline so the app works without internet afterwards).
  Future<bool> isActivated() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_kKey);
    final dev = prefs.getString(_kDevice);
    if (key == null || dev == null) return false;
    final current = await deviceId();
    return current.isNotEmpty && current == dev;
  }

  /// Validates [rawKey] against Firestore and binds it to this device on first
  /// use. Requires the user to be signed in (for Firestore access).
  Future<ActivationResult> activate(String rawKey) async {
    final key = rawKey.trim();
    if (key.isEmpty) return ActivationResult.invalidKey;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return ActivationResult.notSignedIn;

    final dev = await deviceId();
    final ref = _firestore.collection('licenses').doc(key);

    try {
      final result = await _firestore.runTransaction<ActivationResult>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return ActivationResult.invalidKey;
        final data = snap.data()!;
        if (data['active'] != true) return ActivationResult.inactive;

        final bound = (data['deviceId'] as String?) ?? '';
        if (bound.isEmpty) {
          tx.update(ref, {
            'deviceId': dev,
            'activatedBy': uid,
            'activatedAt': FieldValue.serverTimestamp(),
          });
          return ActivationResult.success;
        }
        return bound == dev
            ? ActivationResult.success
            : ActivationResult.usedOnAnotherDevice;
      });

      if (result == ActivationResult.success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kKey, key);
        await prefs.setString(_kDevice, dev);
      }
      return result;
    } catch (e) {
      log('Activation error: $e');
      return ActivationResult.networkError;
    }
  }

  // ---- Admin (developer-only) key management ----

  /// Generates a readable, unambiguous key like "CK-7F3A-9K2P".
  String generateKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I
    final rng = Random.secure();
    String seg() =>
        List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
    return 'CK-${seg()}-${seg()}';
  }

  /// Creates a new, unused license key (admin only — enforced by rules too).
  Future<String> createLicense({String note = ''}) async {
    final key = generateKey();
    await _firestore.collection('licenses').doc(key).set({
      'active': true,
      'deviceId': '',
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return key;
  }

  Future<void> setActive(String key, bool active) =>
      _firestore.collection('licenses').doc(key).update({'active': active});

  /// Frees a key so the client can re-activate on a new phone.
  Future<void> resetDevice(String key) => _firestore
      .collection('licenses')
      .doc(key)
      .update({'deviceId': '', 'activatedBy': '', 'activatedAt': null});

  Future<void> deleteLicense(String key) =>
      _firestore.collection('licenses').doc(key).delete();

  Stream<QuerySnapshot<Map<String, dynamic>>> licensesStream() => _firestore
      .collection('licenses')
      .orderBy('createdAt', descending: true)
      .snapshots();
}
