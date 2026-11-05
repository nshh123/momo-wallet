import 'package:cloud_firestore/cloud_firestore.dart';

class Txn {
  Txn({
    this.id = '',
    required this.description,
    required this.amount,
    required this.isIn,
    this.createdAt,
    this.photoUrl,
  });

  final String id;
  final String description;
  final int amount;
  final bool isIn;
  final DateTime? createdAt;
  final String? photoUrl;

  Map<String, dynamic> toMap() => {
        'description': description,
        'amount': amount,
        'isIn': isIn,
        'photoUrl': photoUrl,
      };

  factory Txn.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Txn(
      id: doc.id,
      description: data['description'] as String,
      amount: (data['amount'] as num).toInt(),
      isIn: data['isIn'] as bool,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      photoUrl: data['photoUrl'] as String?,
    );
  }
}
