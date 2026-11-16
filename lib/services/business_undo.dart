import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'google_sheets_service.dart';
import 'personal_category.dart';
import 'sms_service.dart' as sms;

/// Undoes a business recording: deletes the row from the Google Sheet and puts
/// the transaction back in the To Sort list.
///
/// With [sheetAlreadyHandled] the sheet is not touched (used when the row
/// can't be reached and the user chooses to restore the transaction anyway).
/// Returns a short message for the user. Throws [SheetsException] if the row
/// couldn't be removed, in which case nothing is changed in the app.
Future<String> undoBusinessRecord(
  BusinessRecord r,
  sms.SmsService smsService, {
  bool sheetAlreadyHandled = false,
}) async {
  final sheets = GoogleSheetsService.instance;
  var removed = false;
  if (!sheetAlreadyHandled) {
    removed = await sheets.removeRow(r.spreadsheetId, r.sheet, r.transactionId);
  }

  var restored = false;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('transactions')
          .doc(r.itemId)
          .update({
        'categoryId': null,
        if (r.originalType != null) 'type': r.originalType,
      });
      restored = true;
    } catch (e) {
      log('Undo: Firestore restore skipped for ${r.itemId}: $e');
    }
  }
  final localId = r.localId ?? r.itemId;
  try {
    await smsService.updateTransactionCategory(localId, null);
    if (r.originalType != null) {
      await setLocalTransactionType(smsService, localId, r.originalType!);
    }
    restored = true;
  } catch (e) {
    log('Undo: local restore skipped for $localId: $e');
  }

  // Also recorded into a personal income category: drop its allocations.
  if (r.personalCategory != null && r.isIncoming) {
    try {
      await PersonalCategories.removeAllocations(r.itemId);
    } catch (e) {
      log('Undo: allocation cleanup failed for ${r.itemId}: $e');
    }
  }

  await sheets.deleteRecord(r.itemId);

  final where = '${r.workbookName} › ${r.sheet}';
  final sheetPart = sheetAlreadyHandled
      ? 'Sheet left unchanged'
      : removed
          ? 'Removed from $where'
          : 'Row was already gone from $where';
  return restored
      ? '$sheetPart · back in To Sort'
      : "$sheetPart · couldn't find the transaction to move back to To Sort";
}

/// Changes the type of a transaction in the local SMS store.
Future<void> setLocalTransactionType(
    sms.SmsService smsService, String transactionId, String type) async {
  final box = smsService.transactionBox;
  for (final key in box.keys) {
    final t = box.get(key);
    if (t == null || t.transactionId != transactionId) continue;
    if (t.type == type) return;
    await box.put(
      key,
      sms.Transaction(
        type: type,
        amount: t.amount,
        description: t.description,
        date: t.date,
        transactionId: t.transactionId,
        rawSms: t.rawSms,
        categoryId: t.categoryId,
      ),
    );
    return;
  }
}
