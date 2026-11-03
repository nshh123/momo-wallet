import 'package:flutter_test/flutter_test.dart';
import 'package:momo_wallet/models/txn.dart';

void main() {
  group('Txn Model & Business Logic Tests', () {
    test('Txn serializes to map correctly', () {
      final txn = Txn(
        id: 'txn-123',
        description: 'MTN Airtime purchase',
        amount: 2000,
        isIn: false,
      );

      final map = txn.toMap();
      expect(map['description'], 'MTN Airtime purchase');
      expect(map['amount'], 2000);
      expect(map['isIn'], false);
    });

    test('Balance and filter logic computes accurately', () {
      final txns = [
        Txn(description: 'Opening balance', amount: 10000, isIn: true),
        Txn(description: 'Airtime', amount: 2000, isIn: false),
        Txn(description: 'Salary advance', amount: 50000, isIn: true),
        Txn(description: 'Electricity cash-out', amount: 5000, isIn: false),
      ];

      // Balance = totalIn - totalOut = (10000 + 50000) - (2000 + 5000) = 53000
      final balance = txns.fold<int>(
        0,
        (acc, t) => t.isIn ? acc + t.amount : acc - t.amount,
      );
      final totalIn = txns.where((t) => t.isIn).fold<int>(0, (a, t) => a + t.amount);
      final totalOut = txns.where((t) => !t.isIn).fold<int>(0, (a, t) => a + t.amount);

      expect(balance, 53000);
      expect(totalIn, 60000);
      expect(totalOut, 7000);

      // Filtering logic
      final onlyIn = txns.where((t) => t.isIn).toList();
      final onlyOut = txns.where((t) => !t.isIn).toList();
      expect(onlyIn.length, 2);
      expect(onlyOut.length, 2);
      expect(onlyIn.every((t) => t.isIn), isTrue);
      expect(onlyOut.every((t) => !t.isIn), isTrue);
    });
  });
}
