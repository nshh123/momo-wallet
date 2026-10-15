import 'package:flutter/material.dart';

void main() {
  runApp(const MoMoApp());
}

// ==========================================
// 1. MODEL
// ==========================================
class Transaction {
  Transaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.isIncoming,
    required this.date,
  });

  final String id;
  final String title;
  final int amount;
  final bool isIncoming;
  final DateTime date;
}

// ==========================================
// 2. ROOT APP
// ==========================================
class MoMoApp extends StatelessWidget {
  const MoMoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoMo Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFCC00), // MTN MoMo Yellow
          primary: const Color(0xFFE5A800),
          surface: Colors.grey[50],
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFCC00),
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: const WalletScreen(),
    );
  }
}

// ==========================================
// 3. MAIN WALLET SCREEN
// ==========================================
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const int startingCapital = 10000;

  // Sample transactions (chronological: oldest to newest)
  final List<Transaction> transactions = [
    Transaction(
      id: 'tx_1',
      title: 'Initial Deposit',
      amount: 10000,
      isIncoming: true,
      date: DateTime.now().subtract(const Duration(days: 2)),
    ),
    Transaction(
      id: 'tx_2',
      title: 'Airtime purchase',
      amount: 1000,
      isIncoming: false,
      date: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
    ),
    Transaction(
      id: 'tx_3',
      title: 'Received from Eric',
      amount: 5000,
      isIncoming: true,
      date: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    Transaction(
      id: 'tx_4',
      title: 'Electricity token',
      amount: 4000,
      isIncoming: false,
      date: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  ];

  String filter = 'All'; // 'All', 'IN', 'OUT'

  // --- Calculations ---
  int get currentBalance {
    int balance = 0;
    for (final tx in transactions) {
      balance += tx.isIncoming ? tx.amount : -tx.amount;
    }
    return balance;
  }

  int get totalIn {
    int total = 0;
    for (final tx in transactions) {
      if (tx.isIncoming) total += tx.amount;
    }
    return total;
  }

  int get totalOut {
    int total = 0;
    for (final tx in transactions) {
      if (!tx.isIncoming) total += tx.amount;
    }
    return total;
  }

  int get lowestBalance {
    if (transactions.isEmpty) return startingCapital;
    int running = 0;
    int lowest = transactions.first.amount;
    for (final tx in transactions) {
      running += tx.isIncoming ? tx.amount : -tx.amount;
      if (running < lowest) lowest = running;
    }
    return lowest;
  }

  // --- Rules & Actions ---
  void addTransaction(Transaction tx) {
    setState(() {
      transactions.add(tx);
    });
  }

  void promptReceiveMoney() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receive Money'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Description / Sender',
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              final amount = int.tryParse(amountController.text.trim());

              if (title.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Description cannot be empty')),
                );
                return;
              }
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid whole amount greater than 0')),
                );
                return;
              }

              addTransaction(
                Transaction(
                  id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
                  title: 'Received from $title',
                  amount: amount,
                  isIncoming: true,
                  date: DateTime.now(),
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('Receive'),
          ),
        ],
      ),
    );
  }

  void deleteTransaction(Transaction tx) {
    // History check: verify if deleting this tx causes balance to dip below 0
    int simulated = 0;
    for (final item in transactions) {
      if (item.id == tx.id) continue;
      simulated += item.isIncoming ? item.amount : -item.amount;
      if (simulated < 0) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot delete: balance would drop below 0 RWF in history!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final index = transactions.indexOf(tx);
    setState(() {
      transactions.remove(tx);
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${tx.title} deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              transactions.insert(index, tx);
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Newest transactions first for display
    final List<Transaction> reversedList = transactions.reversed.toList();
    final List<Transaction> filteredList = reversedList.where((tx) {
      if (filter == 'IN') return tx.isIncoming;
      if (filter == 'OUT') return !tx.isIncoming;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Colors.black),
            SizedBox(width: 8),
            Text(
              'MoMo Wallet',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Top Balance Card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFCC00), Color(0xFFFFB300)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available Balance',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${currentBalance.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} RWF',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Action Buttons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _ActionButton(
                        icon: Icons.send,
                        label: 'Send',
                        onTap: () async {
                          final result = await Navigator.push<Transaction>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SendMoneyScreen(
                                currentBalance: currentBalance,
                              ),
                            ),
                          );
                          if (result != null) addTransaction(result);
                        },
                      ),
                      _ActionButton(
                        icon: Icons.local_atm,
                        label: 'Cash Out',
                        onTap: () async {
                          final result = await Navigator.push<Transaction>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CashOutScreen(
                                currentBalance: currentBalance,
                              ),
                            ),
                          );
                          if (result != null) addTransaction(result);
                        },
                      ),
                      _ActionButton(
                        icon: Icons.call_received,
                        label: 'Receive',
                        onTap: promptReceiveMoney,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Statistics Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Total IN',
                    value: '+$totalIn RWF',
                    color: Colors.green[700]!,
                    icon: Icons.arrow_downward,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    title: 'Total OUT',
                    value: '-$totalOut RWF',
                    color: Colors.red[700]!,
                    icon: Icons.arrow_upward,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    title: 'Lowest',
                    value: '$lowestBalance RWF',
                    color: Colors.blue[800]!,
                    icon: Icons.trending_down,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Transactions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                ChoiceChip(
                  label: const Text('All'),
                  selected: filter == 'All',
                  onSelected: (_) => setState(() => filter = 'All'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('IN'),
                  selected: filter == 'IN',
                  onSelected: (_) => setState(() => filter = 'IN'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('OUT'),
                  selected: filter == 'OUT',
                  onSelected: (_) => setState(() => filter = 'OUT'),
                ),
              ],
            ),
          ),

          const Divider(height: 16),

          // Transactions List
          Expanded(
            child: filteredList.isEmpty
                ? const Center(
                    child: Text(
                      'No transactions to display',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final tx = filteredList[index];
                      return Dismissible(
                        key: Key(tx.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => deleteTransaction(tx),
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: tx.isIncoming
                                ? Colors.green.withOpacity(0.15)
                                : Colors.red.withOpacity(0.15),
                            child: Icon(
                              tx.isIncoming
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              color: tx.isIncoming ? Colors.green[800] : Colors.red[800],
                            ),
                          ),
                          title: Text(
                            tx.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${tx.date.day}/${tx.date.month}/${tx.date.year} ${tx.date.hour}:${tx.date.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${tx.isIncoming ? '+' : '-'}${tx.amount} RWF',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: tx.isIncoming
                                      ? Colors.green[700]
                                      : Colors.red[700],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => deleteTransaction(tx),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. SEND MONEY SCREEN (LAB 2)
// ==========================================
class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key, required this.currentBalance});

  final int currentBalance;

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final phoneController = TextEditingController();
  final amountController = TextEditingController();

  void send() {
    final phone = phoneController.text.trim();
    final amountText = amountController.text.trim();
    final amount = int.tryParse(amountText);

    // Rule 1: Check phone number digits
    if (phone.length != 10 || !RegExp(r'^\d{10}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number must be exactly 10 digits')),
      );
      return;
    }

    // Rule 2: Check phone starts with 078 or 079
    if (!phone.startsWith('078') && !phone.startsWith('079')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number must start with 078 or 079 (MTN)')),
      );
      return;
    }

    // Rule 3: Valid integer amount
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    // Rule 4: Minimum amount 100 RWF
    if (amount < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum transfer amount is 100 RWF')),
      );
      return;
    }

    // Rule 5: Cannot exceed balance
    if (amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient balance')),
      );
      return;
    }

    // Success -> Return new OUT transaction
    Navigator.pop(
      context,
      Transaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Sent to $phone',
        amount: amount,
        isIncoming: false,
        date: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    phoneController.dispose();
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Money'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Balance: ${widget.currentBalance} RWF',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Recipient Phone',
                hintText: '078XXXXXXX or 079XXXXXXX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (RWF)',
                hintText: 'Minimum 100 RWF',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.monetization_on),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE5A800),
                  foregroundColor: Colors.black,
                ),
                onPressed: send,
                child: const Text('Send Money', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. CASH OUT SCREEN (LAB 6: NOTE BREAKDOWN)
// ==========================================
class CashOutScreen extends StatefulWidget {
  const CashOutScreen({super.key, required this.currentBalance});

  final int currentBalance;

  @override
  State<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends State<CashOutScreen> {
  final amountController = TextEditingController();
  Map<int, int> noteBreakdown = {};

  void calculateNotes() {
    final amountText = amountController.text.trim();
    final amount = int.tryParse(amountText);

    if (amount == null || amount <= 0) {
      setState(() => noteBreakdown = {});
      return;
    }

    if (amount % 100 != 0) {
      setState(() => noteBreakdown = {});
      return;
    }

    // Rwandan notes: 5000, 2000, 1000, 500, 100
    final notes = [5000, 2000, 1000, 500, 100];
    final Map<int, int> breakdown = {};
    int remaining = amount;

    for (final note in notes) {
      final count = remaining ~/ note;
      if (count > 0) {
        breakdown[note] = count;
        remaining %= note;
      }
    }

    setState(() {
      noteBreakdown = breakdown;
    });
  }

  void confirmCashOut() {
    final amountText = amountController.text.trim();
    final amount = int.tryParse(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (amount % 100 != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount must be a multiple of 100 RWF')),
      );
      return;
    }

    if (amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient balance')),
      );
      return;
    }

    Navigator.pop(
      context,
      Transaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Cash out',
        amount: amount,
        isIncoming: false,
        date: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Cash Out'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Balance: ${widget.currentBalance} RWF',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              onChanged: (_) => calculateNotes(),
              decoration: const InputDecoration(
                labelText: 'Amount to Cash Out (RWF)',
                hintText: 'Must be a multiple of 100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.point_of_sale),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Agent Notes Dispensed:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            if (noteBreakdown.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Enter a valid amount (multiple of 100) to see notes breakdown.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  border: Border.all(color: Colors.amber),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: noteBreakdown.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${entry.key} RWF Note:',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '× ${entry.value}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE5A800),
                  foregroundColor: Colors.black,
                ),
                onPressed: confirmCashOut,
                child: const Text('Confirm Cash Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// HELPER WIDGETS
// ==========================================
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.black, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
