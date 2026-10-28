import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  runApp(const MoMoApp());
}

// ==========================================
// 1. MODELS & PERSISTENCE
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'isIncoming': isIncoming,
      'date': date.toIso8601String(),
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      title: json['title'] as String,
      amount: (json['amount'] as num).toInt(),
      isIncoming: json['isIncoming'] as bool,
      date: DateTime.parse(json['date'] as String),
    );
  }
}

class LiveWeather {
  LiveWeather({
    required this.temperature,
    required this.humidity,
    required this.code,
    required this.time,
  });

  final double temperature;
  final int humidity;
  final int code;
  final String time;

  factory LiveWeather.fromJson(Map<String, dynamic> json) {
    return LiveWeather(
      temperature: (json['temperature_2m'] as num).toDouble(),
      humidity: (json['relative_humidity_2m'] as num).toInt(),
      code: (json['weather_code'] as num).toInt(),
      time: (json['time'] as String?) ?? '',
    );
  }
}

// ==========================================
// 2. BULLETPROOF STORAGE SERVICE (DartPad Safe)
// ==========================================
class StorageService {
  static SharedPreferences? _prefs;
  static final Map<String, String> _memory = {};

  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  static Future<void> setString(String key, String value) async {
    _memory[key] = value;
    try {
      if (_prefs == null) {
        _prefs = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 4));
      }
      await _prefs?.setString(key, value);
    } catch (_) {}
  }

  static Future<String?> getString(String key) async {
    try {
      if (_prefs == null) {
        _prefs = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 4));
      }
      final val = _prefs?.getString(key);
      if (val != null) return val;
    } catch (_) {}
    return _memory[key];
  }
}

// ==========================================
// 3. WEATHER HELPER & API CALL
// ==========================================
String describeWeather(int code) {
  if (code == 0) return 'Clear';
  if (code <= 2) return 'Partly cloudy';
  if (code == 3) return 'Cloudy';
  if (code == 45 || code == 48) return 'Foggy';
  if (code >= 51 && code <= 67) return 'Rainy';
  if (code >= 80 && code <= 82) return 'Showers';
  if (code >= 95) return 'Stormy';
  return 'Fair';
}

IconData iconForWeather(int code) {
  if (code == 0) return Icons.wb_sunny;
  if (code <= 3) return Icons.cloud;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 95) return Icons.thunderstorm;
  if (code >= 51) return Icons.water_drop;
  return Icons.wb_cloudy;
}

Future<LiveWeather> fetchKigaliWeather() async {
  final url = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=-1.9441&longitude=30.0619'
    '&current=temperature_2m,relative_humidity_2m,weather_code'
    '&timezone=Africa%2FKigali',
  );

  final response = await http.get(url).timeout(const Duration(seconds: 5));
  if (response.statusCode != 200) {
    throw Exception('Failed to load weather: ${response.statusCode}');
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return LiveWeather.fromJson(data['current'] as Map<String, dynamic>);
}

// ==========================================
// 4. ROOT APP (With Phone Frame Simulation)
// ==========================================
class MoMoApp extends StatefulWidget {
  const MoMoApp({super.key});

  @override
  State<MoMoApp> createState() => _MoMoAppState();
}

class _MoMoAppState extends State<MoMoApp> {
  bool enablePhoneFrame = true;

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
      builder: (context, child) {
        if (!enablePhoneFrame) return child!;
        return _PhoneDeviceFrame(
          child: child!,
        );
      },
      home: const WalletScreen(),
    );
  }
}

// ==========================================
// 5. MAIN WALLET SCREEN
// ==========================================
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const int startingCapital = 10000;

  List<Transaction> transactions = [];
  List<Transaction> deletedTransactions = [];

  String filter = 'All'; // 'All', 'IN', 'OUT', 'DELETED'

  // Live Weather API States
  LiveWeather? liveWeather;
  bool weatherLoading = true;
  String? weatherError;
  bool simulateOffline = false;

  @override
  void initState() {
    super.initState();
    initApp();
  }

  Future<void> initApp() async {
    await loadStoredTransactions();
    await loadWeather();
  }

  // --- Persistence Methods ---
  Future<void> loadStoredTransactions() async {
    try {
      final savedTxJson = await StorageService.getString('momo_transactions');
      final savedDelJson = await StorageService.getString('momo_deleted_transactions');

      if (savedTxJson != null) {
        final list = jsonDecode(savedTxJson) as List;
        transactions = list.map((x) => Transaction.fromJson(x as Map<String, dynamic>)).toList();
      } else {
        await resetToDefaultData(silent: true);
      }

      if (savedDelJson != null) {
        final list = jsonDecode(savedDelJson) as List;
        deletedTransactions = list.map((x) => Transaction.fromJson(x as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    if (mounted) setState(() {});
  }

  Future<void> saveStoredTransactions() async {
    final txList = transactions.map((t) => t.toJson()).toList();
    final delList = deletedTransactions.map((t) => t.toJson()).toList();

    await StorageService.setString('momo_transactions', jsonEncode(txList));
    await StorageService.setString('momo_deleted_transactions', jsonEncode(delList));
  }

  Future<void> resetToDefaultData({bool silent = false}) async {
    transactions = [
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
    deletedTransactions = [];
    await saveStoredTransactions();

    if (!silent && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo transactions reset to default')),
      );
    }
  }

  Future<void> restartApp() async {
    setState(() {
      transactions = [];
      deletedTransactions = [];
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Simulating app restart (loading saved data from storage)...'),
        duration: Duration(milliseconds: 700),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 300));
    await loadStoredTransactions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restart complete: ${transactions.length} transactions restored.'),
          backgroundColor: Colors.green[800],
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // --- Live Weather API Call ---
  Future<void> loadWeather() async {
    setState(() {
      weatherLoading = true;
      weatherError = null;
    });

    try {
      if (simulateOffline) {
        await Future.delayed(const Duration(milliseconds: 350));
        throw Exception('No internet connection (simulated)');
      }

      final w = await fetchKigaliWeather();
      if (!mounted) return;
      setState(() {
        liveWeather = w;
        weatherLoading = false;
        weatherError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        weatherLoading = false;
        weatherError = 'Could not load weather. Check your internet connection.';
      });
    }
  }

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
    saveStoredTransactions();
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
      deletedTransactions.add(tx);
    });
    saveStoredTransactions();

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${tx.title} deleted (moved to DELETED)'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              deletedTransactions.remove(tx);
              transactions.insert(index, tx);
            });
            saveStoredTransactions();
          },
        ),
      ),
    );
  }

  void restoreTransaction(Transaction tx) {
    setState(() {
      deletedTransactions.remove(tx);
      transactions.add(tx);
    });
    saveStoredTransactions();

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${tx.title} restored to wallet')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Transaction> reversedList = transactions.reversed.toList();
    final List<Transaction> filteredList;

    if (filter == 'DELETED') {
      filteredList = deletedTransactions.reversed.toList();
    } else {
      filteredList = reversedList.where((tx) {
        if (filter == 'IN') return tx.isIncoming;
        if (filter == 'OUT') return !tx.isIncoming;
        return true;
      }).toList();
    }

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
        actions: [
          // Simulate App Restart (Loads from Storage for after.png verification)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Simulate App Restart (Loads from Storage)',
            onPressed: restartApp,
          ),
          // Offline Simulation Toggle (Helps take the no-internet screenshot easily in DartPad)
          IconButton(
            icon: Icon(simulateOffline ? Icons.wifi_off : Icons.wifi),
            tooltip: simulateOffline ? 'Switch Online' : 'Simulate Offline Mode (For Screenshot)',
            onPressed: () {
              setState(() {
                simulateOffline = !simulateOffline;
              });
              loadWeather();
            },
          ),
          // Options Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Options',
            onSelected: (val) {
              if (val == 'restart') {
                restartApp();
              } else if (val == 'reset') {
                resetToDefaultData();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'restart',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 18),
                    SizedBox(width: 8),
                    Text('Simulate Restart'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, size: 18),
                    SizedBox(width: 8),
                    Text('Reset Demo Data'),
                  ],
                ),
              ),
            ],
          ),
        ],
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
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
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

          // Live API Weather Widget (Session 5: Loading, Error with Retry, Data)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: _WeatherCard(
              weather: liveWeather,
              loading: weatherLoading,
              error: weatherError,
              onRetry: loadWeather,
            ),
          ),

          const SizedBox(height: 6),

          // Filter Chips (Scrollable row with DELETED chip)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Transactions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
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
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('DELETED (${deletedTransactions.length})'),
                          selected: filter == 'DELETED',
                          selectedColor: Colors.red[100],
                          onSelected: (_) => setState(() => filter = 'DELETED'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 16),

          // Transactions List
          Expanded(
            child: filteredList.isEmpty
                ? Center(
                    child: Text(
                      filter == 'DELETED'
                          ? 'No deleted transactions'
                          : 'No transactions to display',
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final tx = filteredList[index];

                      if (filter == 'DELETED') {
                        // Deleted view: greyed out with Restore button
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[300],
                            child: const Icon(Icons.delete_outline, color: Colors.grey),
                          ),
                          title: Text(
                            tx.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey,
                            ),
                          ),
                          subtitle: Text(
                            'Deleted · ${tx.date.day}/${tx.date.month}/${tx.date.year}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${tx.isIncoming ? '+' : '-'}${tx.amount} RWF',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.grey,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.restore, color: Colors.blue),
                                tooltip: 'Restore to Wallet',
                                onPressed: () => restoreTransaction(tx),
                              ),
                            ],
                          ),
                        );
                      }

                      // Active view: Dismissible with delete
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
                                ? const Color(0x264CAF50)
                                : const Color(0x26F44336),
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
                                tooltip: 'Delete',
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
// 6. SEND MONEY SCREEN (LAB 2)
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

    if (phone.length != 10 || !RegExp(r'^\d{10}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number must be exactly 10 digits')),
      );
      return;
    }

    if (!phone.startsWith('078') && !phone.startsWith('079')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number must start with 078 or 079 (MTN)')),
      );
      return;
    }

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (amount < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum transfer amount is 100 RWF')),
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
            const SizedBox(height: 16),
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
// 7. CASH OUT SCREEN (LAB 6: NOTE BREAKDOWN)
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
// 8. HELPER WIDGETS
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
          color: const Color(0x14000000),
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

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.weather,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final LiveWeather? weather;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9C4), // soft amber
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFE082)),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE5A800)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Fetching live Kigali weather from Open-Meteo...',
                style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }

    if (error != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE), // soft red
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFCDD2)),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.red[700], size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Internet Connection',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[900],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    error!,
                    style: TextStyle(fontSize: 11, color: Colors.red[800]),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    if (weather == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFFFCC00),
            radius: 18,
            child: Icon(iconForWeather(weather!.code), color: Colors.black87, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Kigali ${weather!.temperature.round()}°C',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5A800),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        describeWeather(weather!.code),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Humidity ${weather!.humidity}% • Live Open-Meteo API',
                  style: TextStyle(fontSize: 11, color: Colors.grey[800]),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18, color: Colors.black54),
            tooltip: 'Refresh Weather',
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 9. DARTPAD PHONE DEVICE FRAME SIMULATOR
// ==========================================
class _PhoneDeviceFrame extends StatelessWidget {
  const _PhoneDeviceFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E28), // Soft studio backdrop
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          width: 390,
          height: 820,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(48),
            border: Border.all(color: const Color(0xFF2C2F38), width: 9),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 35,
                spreadRadius: 2,
                offset: Offset(0, 15),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(39),
            child: Stack(
              children: [
                // Inner Screen with mobile status bar insets
                MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 36, bottom: 20),
                  ),
                  child: child,
                ),

                // Simulated Top Status Bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '09:41',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                          Container(
                            width: 85,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          const Row(
                            children: [
                              Icon(Icons.signal_cellular_4_bar, size: 14, color: Colors.black),
                              SizedBox(width: 4),
                              Icon(Icons.wifi, size: 14, color: Colors.black),
                              SizedBox(width: 4),
                              Icon(Icons.battery_full, size: 16, color: Colors.black),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Simulated Bottom Home Indicator
                Positioned(
                  bottom: 6,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 120,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
