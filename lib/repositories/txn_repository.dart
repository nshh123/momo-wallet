import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/txn.dart';

class TxnRepository {
  TxnRepository(this.uid);

  final String uid;

  // users/{uid}/transactions: the path protected by security rules.
  CollectionReference<Map<String, dynamic>> get _transactions =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('transactions');

  // The pipe: the list now, and again after every change.
  Stream<List<Txn>> watchAll() => _transactions
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Txn.fromDoc).toList());

  Future<void> add(Txn txn) => _transactions.add({
        ...txn.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> update(String id, Txn txn) =>
      _transactions.doc(id).update(txn.toMap());

  Future<void> delete(String id) => _transactions.doc(id).delete();

  // Restore or set a transaction with custom/preserved timestamp
  Future<void> setWithTimestamp(String id, Txn txn, DateTime? timestamp) =>
      _transactions.doc(id).set({
        ...txn.toMap(),
        'createdAt': timestamp != null
            ? Timestamp.fromDate(timestamp)
            : FieldValue.serverTimestamp(),
      });

  // Sample data for a brand new account.
  Future<void> addSamples() async {
    final samples = [
      Txn(description: 'Opening balance', amount: 10000, isIn: true),
      Txn(description: 'Sent to 0788123456', amount: 2500, isIn: false),
      Txn(description: 'Received from Keza', amount: 4000, isIn: true),
    ];
    final batch = FirebaseFirestore.instance.batch();
    for (final t in samples) {
      batch.set(_transactions.doc(), {
        ...t.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
