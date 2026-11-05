import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/txn.dart';
import '../state/wallet_state.dart';
import 'cash_out_screen.dart';
import 'send_screen.dart';
import 'txn_form.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  Future<void> _delete(BuildContext context, Txn txn) async {
    final wallet = context.read<WalletState>();
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text(txn.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (sure == true) {
      try {
        await wallet.remove(txn);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${txn.description}"'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  await wallet.restore(txn);
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

  void _openForm(BuildContext context, Txn? txn) {
    final wallet = context.read<WalletState>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<WalletState>.value(
          value: wallet,
          child: TxnForm(txn: txn),
        ),
      ),
    );
  }

  void _openSend(BuildContext context) {
    final wallet = context.read<WalletState>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<WalletState>.value(
          value: wallet,
          child: const SendScreen(),
        ),
      ),
    );
  }

  void _openCashOut(BuildContext context) {
    final wallet = context.read<WalletState>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<WalletState>.value(
          value: wallet,
          child: const CashOutScreen(),
        ),
      ),
    );
  }

  void _promptReceiveMoney(BuildContext context) {
    final wallet = context.read<WalletState>();
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
              await wallet.add(
                Txn(
                  description: 'Received from $desc',
                  amount: amount,
                  isIn: true,
                ),
              );
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
    final wallet = context.watch<WalletState>();

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
      body: _buildBody(context, wallet),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFFCC00),
        foregroundColor: Colors.black,
        tooltip: 'Add Transaction',
        onPressed: () => _openForm(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WalletState wallet) {
    if (wallet.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                wallet.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      );
    }

    if (wallet.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final txns = wallet.visible;
    final balance = wallet.balance;
    final totalIn = wallet.totalIn;
    final totalOut = wallet.totalOut;

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
                            'State Provider',
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
                    onPressed: () => _openSend(context),
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
                    onPressed: () => _openCashOut(context),
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

        // 3. Filter Chips (Step 18)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('ALL'),
                  selected: wallet.filter == 'all',
                  onSelected: (_) =>
                      context.read<WalletState>().setFilter('all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('MONEY IN'),
                  selected: wallet.filter == 'in',
                  onSelected: (_) =>
                      context.read<WalletState>().setFilter('in'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('MONEY OUT'),
                  selected: wallet.filter == 'out',
                  onSelected: (_) =>
                      context.read<WalletState>().setFilter('out'),
                ),
              ],
            ),
          ),
        ),

        // 4. Transactions List or Empty State
        if (wallet.transactions.isEmpty)
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
                      'No transactions yet.',
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
        else if (txns.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing matches this filter.',
                  style: TextStyle(fontSize: 15, color: Colors.grey),
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
                  final t = txns[index];
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
                      leading: t.photoUrl == null
                          ? CircleAvatar(
                              backgroundColor: isPlus
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              child: Icon(
                                isPlus
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: isPlus ? Colors.green : Colors.red,
                              ),
                            )
                          : CircleAvatar(
                              backgroundImage: NetworkImage(t.photoUrl!),
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
                      onTap: () => _openForm(context, t),
                      onLongPress: () => _delete(context, t),
                    ),
                  );
                },
                childCount: txns.length,
              ),
            ),
          ),
      ],
    );
  }
}
