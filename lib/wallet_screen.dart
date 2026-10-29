import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'cash_out_screen.dart';
import 'send_screen.dart';
import 'txn.dart';
import 'txn_form.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  String _filter = 'All'; // 'All', 'IN', 'OUT'

  Future<void> _delete(BuildContext context, Txn txn) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text(txn.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (sure == true) {
      try {
        await myTransactions().doc(txn.id).delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${txn.description}"'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  await myTransactions().doc(txn.id).set({
                    ...txn.toMap(),
                    'createdAt': txn.createdAt != null
                        ? Timestamp.fromDate(txn.createdAt!)
                        : FieldValue.serverTimestamp(),
                  });
                },
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _promptReceiveMoney(BuildContext context) {
    final descController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Receive Money'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Sender / Description',
                hintText: 'e.g. From Keza',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (RWF)',
                hintText: 'e.g. 5000',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final desc = descController.text.trim();
              final amount = int.tryParse(amountController.text.trim());
              if (desc.isEmpty || amount == null || amount <= 0) return;

              Navigator.pop(ctx);
              await myTransactions().add({
                'description': 'Received from $desc',
                'amount': amount,
                'isIn': true,
                'createdAt': FieldValue.serverTimestamp(),
              });
            },
            child: const Text('Receive'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MoMo Wallet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              userEmail,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            myTransactions().orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load your transactions.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final txns = snapshot.data!.docs.map(Txn.fromDoc).toList();

          // Save facts. Compute the rest.
          final balance = txns.fold<int>(
            0,
            (total, t) => t.isIn ? total + t.amount : total - t.amount,
          );
          final totalIn = txns.where((t) => t.isIn).fold<int>(
                0,
                (acc, t) => acc + t.amount,
              );
          final totalOut = txns.where((t) => !t.isIn).fold<int>(
                0,
                (acc, t) => acc + t.amount,
              );

          final filteredTxns = txns.where((t) {
            if (_filter == 'IN') return t.isIn;
            if (_filter == 'OUT') return !t.isIn;
            return true;
          }).toList();

          return CustomScrollView(
            slivers: [
              // 1. Balance & Summary Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: const Color(0xFFFFCC00),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Main Balance',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Cloud Synced',
                                  style: TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$balance RWF',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const Divider(height: 24, color: Colors.black26),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.arrow_downward,
                                      color: Colors.green, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '+$totalIn RWF',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.arrow_upward,
                                      color: Colors.red, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '-$totalOut RWF',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 2. Quick Action Buttons (Send, Cash Out, Receive)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.send, size: 16),
                          label: const Text('Send'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SendScreen(currentBalance: balance),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.point_of_sale, size: 16),
                          label: const Text('Cash Out'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CashOutScreen(currentBalance: balance),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Receive'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => _promptReceiveMoney(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Filter Chips
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _filter == 'All',
                        onSelected: (_) => setState(() => _filter = 'All'),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Money In'),
                        selected: _filter == 'IN',
                        onSelected: (_) => setState(() => _filter = 'IN'),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Money Out'),
                        selected: _filter == 'OUT',
                        onSelected: (_) => setState(() => _filter = 'OUT'),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Transactions List or Empty State
              if (filteredTxns.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No transactions found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap the + button to record a new transaction.',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final t = filteredTxns[index];
                        final isPlus = t.isIn;
                        final amountSign = isPlus ? '+' : '-';
                        final amountColor =
                            isPlus ? Colors.green.shade700 : Colors.red.shade700;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isPlus
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              child: Icon(
                                isPlus ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isPlus ? Colors.green : Colors.red,
                              ),
                            ),
                            title: Text(
                              t.description,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              t.createdAt != null
                                  ? '${t.createdAt!.hour.toString().padLeft(2, '0')}:${t.createdAt!.minute.toString().padLeft(2, '0')} · ${t.createdAt!.day}/${t.createdAt!.month}/${t.createdAt!.year}'
                                  : 'Just now',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Text(
                              '$amountSign${t.amount} RWF',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: amountColor,
                                fontSize: 14,
                              ),
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TxnForm(txn: t),
                              ),
                            ),
                            onLongPress: () => _delete(context, t),
                          ),
                        );
                      },
                      childCount: filteredTxns.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFFCC00),
        foregroundColor: Colors.black,
        tooltip: 'Add Transaction',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TxnForm()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
