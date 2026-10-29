import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'txn.dart';

class CashOutScreen extends StatefulWidget {
  const CashOutScreen({super.key, required this.currentBalance});

  final int currentBalance;

  @override
  State<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends State<CashOutScreen> {
  final _amountController = TextEditingController();
  int _calculatedAmount = 0;
  bool _busy = false;

  final List<int> _currencyNotes = [5000, 2000, 1000, 500, 100];

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() {
      final val = int.tryParse(_amountController.text.trim()) ?? 0;
      setState(() => _calculatedAmount = val);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Map<int, int> _calculateNoteBreakdown(int total) {
    final breakdown = <int, int>{};
    int remaining = total;
    for (final note in _currencyNotes) {
      final count = remaining ~/ note;
      if (count > 0) {
        breakdown[note] = count;
        remaining %= note;
      }
    }
    return breakdown;
  }

  Future<void> _processCashOut() async {
    final amount = _calculatedAmount;
    if (amount <= 0 || amount % 100 != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount must be a multiple of 100 RWF')),
      );
      return;
    }
    if (amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insufficient balance for cash-out!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await myTransactions().add({
        'description': 'Cash out at MoMo agent',
        'amount': amount,
        'isIn': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully cashed out $amount RWF'),
            backgroundColor: Colors.green[800],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cash out failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = _calculateNoteBreakdown(_calculatedAmount);

    return Scaffold(
      appBar: AppBar(title: const Text('Agent Cash Out')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Withdrawal Amount (RWF)',
                  hintText: 'Must be multiple of 100',
                  prefixIcon: Icon(Icons.point_of_sale),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Currency Notes Breakdown',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      if (breakdown.isEmpty)
                        const Text(
                          'Enter an amount to calculate physical currency notes.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        )
                      else
                        ...breakdown.entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${e.key} RWF Note'),
                                Text(
                                  '× ${e.value}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy ? null : _processCashOut,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFFE5A800),
                  foregroundColor: Colors.black,
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Confirm Cash Out',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
