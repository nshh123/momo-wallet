import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MoMoApp());
}

// ============================================================================
// 1. REACTIVE FIREBASE SIMULATION ENGINE (DartPad Web-Safe)
// ============================================================================

class MockUser {
  MockUser({required this.uid, required this.email});
  final String uid;
  final String email;
}

class MockDocumentSnapshot {
  MockDocumentSnapshot({required this.id, required this.dataMap});
  final String id;
  final Map<String, dynamic> dataMap;

  Map<String, dynamic> data() => Map<String, dynamic>.from(dataMap);
}

class MockQuerySnapshot {
  MockQuerySnapshot(this.docs);
  final List<MockDocumentSnapshot> docs;
}

class MockFieldValue {
  static DateTime serverTimestamp() => DateTime.now();
}

class MockFirebaseAuthException implements Exception {
  MockFirebaseAuthException(this.code);
  final String code;
  @override
  String toString() => 'FirebaseAuthException: $code';
}

class MockFirestoreException implements Exception {
  MockFirestoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Simulated Firebase backend singleton
class FirebaseBackend {
  FirebaseBackend._() {
    // Seed initial Aline account transactions matching Session 6 tutorial
    _userTransactions['user_aline_1'] = [
      {
        'id': 'tx_1',
        'title': 'Received from Keza',
        'amount': 4000,
        'isIn': true,
        'createdAt': DateTime.now().subtract(const Duration(hours: 1)),
      },
      {
        'id': 'tx_2',
        'title': 'Sent to 0788123456',
        'amount': 2500,
        'isIn': false,
        'createdAt': DateTime.now().subtract(const Duration(hours: 2)),
      },
      {
        'id': 'tx_3',
        'title': 'Opening balance',
        'amount': 10000,
        'isIn': true,
        'createdAt': DateTime.now().subtract(const Duration(hours: 3)),
      },
    ];
  }
  static final FirebaseBackend instance = FirebaseBackend._();

  final Map<String, String> _registeredUsers = {
    'aline@gmail.com': 'password123',
  };

  final Map<String, String> _uidToEmail = {
    'user_aline_1': 'aline@gmail.com',
  };
  final Map<String, String> _emailToUid = {
    'aline@gmail.com': 'user_aline_1',
  };

  MockUser? _currentUser;
  final StreamController<MockUser?> _authController =
      StreamController<MockUser?>.broadcast();

  final Map<String, List<Map<String, dynamic>>> _userTransactions = {};
  final Map<String, StreamController<MockQuerySnapshot>> _streamControllers = {};

  bool rulesViolated = false;

  MockUser? get currentUser => _currentUser;

  Stream<MockUser?> get authStateChanges async* {
    yield _currentUser;
    yield* _authController.stream;
  }

  MockQuerySnapshot _buildSnapshot(String uid) {
    if (rulesViolated) {
      throw MockFirestoreException(
        '[cloud_firestore/permission-denied] The caller does not have permission to execute the specified operation.',
      );
    }
    final rawList = _userTransactions[uid] ?? [];
    final sorted = List<Map<String, dynamic>>.from(rawList)
      ..sort((a, b) {
        final da = a['createdAt'] as DateTime? ?? DateTime.now();
        final db = b['createdAt'] as DateTime? ?? DateTime.now();
        return db.compareTo(da); // Newest first
      });

    final docs = sorted
        .map((m) => MockDocumentSnapshot(id: m['id'] as String, dataMap: m))
        .toList();
    return MockQuerySnapshot(docs);
  }

  Stream<MockQuerySnapshot> streamTransactions(String uid) async* {
    if (!_streamControllers.containsKey(uid)) {
      _streamControllers[uid] = StreamController<MockQuerySnapshot>.broadcast();
    }
    try {
      yield _buildSnapshot(uid);
    } catch (e) {
      yield* Stream.error(e);
    }
    yield* _streamControllers[uid]!.stream;
  }

  void _emitSnapshot(String uid) {
    if (!_streamControllers.containsKey(uid)) return;
    try {
      final snap = _buildSnapshot(uid);
      _streamControllers[uid]!.add(snap);
    } catch (e) {
      _streamControllers[uid]!.addError(e);
    }
  }

  Future<void> createUser({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final cleanEmail = email.trim().toLowerCase();
    if (_registeredUsers.containsKey(cleanEmail)) {
      throw MockFirebaseAuthException('email-already-in-use');
    }
    if (password.length < 6) {
      throw MockFirebaseAuthException('weak-password');
    }
    _registeredUsers[cleanEmail] = password;
    final newUid = 'user_${DateTime.now().millisecondsSinceEpoch}';
    _emailToUid[cleanEmail] = newUid;
    _uidToEmail[newUid] = cleanEmail;
    _userTransactions[newUid] = [];

    _currentUser = MockUser(uid: newUid, email: cleanEmail);
    _authController.add(_currentUser);

    await seedSampleData(newUid);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final cleanEmail = email.trim().toLowerCase();
    if (!_registeredUsers.containsKey(cleanEmail)) {
      throw MockFirebaseAuthException('user-not-found');
    }
    if (_registeredUsers[cleanEmail] != password) {
      throw MockFirebaseAuthException('wrong-password');
    }
    final uid = _emailToUid[cleanEmail]!;
    _currentUser = MockUser(uid: uid, email: cleanEmail);
    _authController.add(_currentUser);
    _emitSnapshot(uid);
  }

  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _currentUser = null;
    _authController.add(null);
  }

  Future<void> seedSampleData(String uid) async {
    final samples = [
      {
        'id': 'tx_${DateTime.now().millisecondsSinceEpoch}_1',
        'title': 'Received from Keza',
        'amount': 4000,
        'isIn': true,
        'createdAt': DateTime.now().subtract(const Duration(minutes: 1)),
      },
      {
        'id': 'tx_${DateTime.now().millisecondsSinceEpoch}_2',
        'title': 'Sent to 0788123456',
        'amount': 2500,
        'isIn': false,
        'createdAt': DateTime.now().subtract(const Duration(minutes: 3)),
      },
      {
        'id': 'tx_${DateTime.now().millisecondsSinceEpoch}_3',
        'title': 'Opening balance',
        'amount': 10000,
        'isIn': true,
        'createdAt': DateTime.now().subtract(const Duration(minutes: 5)),
      },
    ];
    _userTransactions[uid] = samples;
    _emitSnapshot(uid);
  }

  Future<void> addTransaction(String uid, Map<String, dynamic> data) async {
    if (rulesViolated) {
      throw MockFirestoreException(
        '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
      );
    }
    await Future.delayed(const Duration(milliseconds: 100));
    final id = 'tx_${DateTime.now().millisecondsSinceEpoch}';
    final docData = {
      ...data,
      'id': id,
      'createdAt': data['createdAt'] ?? DateTime.now(),
    };
    final list = _userTransactions.putIfAbsent(uid, () => []);
    list.add(docData);
    _emitSnapshot(uid);
  }

  Future<void> updateTransaction(
      String uid, String docId, Map<String, dynamic> data) async {
    if (rulesViolated) {
      throw MockFirestoreException(
        '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
      );
    }
    await Future.delayed(const Duration(milliseconds: 100));
    final list = _userTransactions[uid] ?? [];
    final idx = list.indexWhere((m) => m['id'] == docId);
    if (idx != -1) {
      list[idx] = {
        ...list[idx],
        ...data,
      };
      _emitSnapshot(uid);
    }
  }

  Future<void> deleteTransaction(String uid, String docId) async {
    if (rulesViolated) {
      throw MockFirestoreException(
        '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
      );
    }
    await Future.delayed(const Duration(milliseconds: 100));
    final list = _userTransactions[uid] ?? [];
    list.removeWhere((m) => m['id'] == docId);
    _emitSnapshot(uid);
  }

  Future<void> restoreTransaction(
      String uid, String docId, Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final list = _userTransactions.putIfAbsent(uid, () => []);
    list.add({
      ...data,
      'id': docId,
      'createdAt': data['createdAt'] ?? DateTime.now(),
    });
    _emitSnapshot(uid);
  }

  void toggleRuleViolation() {
    rulesViolated = !rulesViolated;
    if (_currentUser != null) {
      _emitSnapshot(_currentUser!.uid);
    }
  }
}

// Model
class TransactionItem {
  TransactionItem({
    required this.id,
    required this.title,
    required this.amount,
    required this.isIn,
    required this.createdAt,
  });

  final String id;
  final String title;
  final int amount;
  final bool isIn;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'title': title,
        'amount': amount,
        'isIn': isIn,
      };

  factory TransactionItem.fromDoc(MockDocumentSnapshot doc) {
    final data = doc.data();
    return TransactionItem(
      id: doc.id,
      title: (data['title'] ?? data['description'] ?? 'Transaction') as String,
      amount: (data['amount'] as num).toInt(),
      isIn: data['isIn'] as bool,
      createdAt: (data['createdAt'] as DateTime?) ?? DateTime.now(),
    );
  }
}

String formatRwf(int amount) {
  return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
}

// ============================================================================
// 2. ROOT APP (With the Exact Session 4/5 Phone Simulator Frame)
// ============================================================================

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
      builder: (context, child) {
        return _PhoneDeviceFrame(child: child!);
      },
      home: const AuthGate(),
    );
  }
}

// ============================================================================
// 3. AUTH GATE (Session 6 Step 2)
// ============================================================================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MockUser?>(
      stream: FirebaseBackend.instance.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            FirebaseBackend.instance.currentUser == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data ?? FirebaseBackend.instance.currentUser;
        if (user == null) {
          return const LoginScreen();
        }
        return const WalletScreen();
      },
    );
  }
}

// ============================================================================
// 4. LOGIN SCREEN (Session 6 Step 1)
// ============================================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(text: 'aline@gmail.com');
  final _password = TextEditingController(text: 'password123');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool newAccount}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final backend = FirebaseBackend.instance;
      if (newAccount) {
        await backend.createUser(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await backend.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on MockFirebaseAuthException catch (e) {
      setState(() => _error = _message(e.code));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Log in instead.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Wrong email or password.';
      case 'weak-password':
        return 'Choose a stronger password (min 6 characters).';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        return 'Something went wrong ($code).';
    }
  }

  void _fillSample(String email, String pass) {
    setState(() {
      _email.text = email;
      _password.text = pass;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFCC00),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      size: 42,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'MoMo Wallet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cloud Database · Firebase Authentication',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      final email = (v ?? '').trim();
                      if (email.isEmpty) return 'Enter your email';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(email)) {
                        return 'Enter a valid email, like aline@gmail.com';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) =>
                        (v ?? '').length < 6 ? 'At least 6 characters' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(newAccount: false),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFFFFCC00),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Log in',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _submit(newAccount: true),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Create account'),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.person, size: 14),
                        label: const Text('Account 1 (Aline)',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () =>
                            _fillSample('aline@gmail.com', 'password123'),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.person_add, size: 14),
                        label: const Text('Account 2 (Eric)',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () =>
                            _fillSample('eric@gmail.com', 'secret456'),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.warning, size: 14),
                        label: const Text('Test Wrong Password',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () =>
                            _fillSample('aline@gmail.com', 'wrongpassword'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 5. MAIN WALLET SCREEN (Exact Original Layout + Firebase Cloud Sync)
// ============================================================================

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const int startingCapital = 10000;
  String filter = 'All'; // 'All', 'IN', 'OUT'

  Future<void> _delete(BuildContext context, TransactionItem txn) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text(txn.title),
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
      final uid = FirebaseBackend.instance.currentUser?.uid;
      if (uid == null) return;
      try {
        await FirebaseBackend.instance.deleteTransaction(uid, txn.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${txn.title}"'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  await FirebaseBackend.instance.restoreTransaction(
                    uid,
                    txn.id,
                    txn.toMap(),
                  );
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
                hintText: 'e.g. Keza',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (RWF)',
                hintText: 'e.g. 4000',
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

              final uid = FirebaseBackend.instance.currentUser?.uid;
              if (uid == null) return;

              Navigator.pop(ctx);
              await FirebaseBackend.instance.addTransaction(uid, {
                'title': 'Received from $desc',
                'amount': amount,
                'isIn': true,
                'createdAt': DateTime.now(),
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
    final user = FirebaseBackend.instance.currentUser;
    final userEmail = user?.email ?? 'User';
    final uid = user?.uid ?? '';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.account_balance_wallet, color: Colors.black),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MoMo Wallet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                Text(
                  userEmail,
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Step 6 Rules Break Simulator Toggle (triggers permission-denied screenshot)
          IconButton(
            icon: Icon(
              FirebaseBackend.instance.rulesViolated
                  ? Icons.lock
                  : Icons.lock_open,
              color: FirebaseBackend.instance.rulesViolated
                  ? Colors.red
                  : Colors.black,
            ),
            tooltip: FirebaseBackend.instance.rulesViolated
                ? 'Rules Broken: Access Denied (Tap to restore)'
                : 'Simulate Rule Violation [cloud_firestore/permission-denied]',
            onPressed: () {
              setState(() {
                FirebaseBackend.instance.toggleRuleViolation();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    FirebaseBackend.instance.rulesViolated
                        ? 'Simulating rule break: request.auth.uid == userId -> false'
                        : 'Rules restored: access granted.',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          // Step 2 Logout Button
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => FirebaseBackend.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<MockQuerySnapshot>(
        stream: FirebaseBackend.instance.streamTransactions(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gpp_bad, color: Colors.red, size: 54),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load your transactions.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () {
                        setState(() {
                          FirebaseBackend.instance.toggleRuleViolation();
                        });
                      },
                      child: const Text('Restore Database Access'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final txns = snapshot.data!.docs
              .map(TransactionItem.fromDoc)
              .toList();

          // Save facts. Compute the rest dynamically:
          final currentBalance = txns.fold<int>(
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

          int lowestBalance = startingCapital;
          if (txns.isNotEmpty) {
            final chronological = List<TransactionItem>.from(txns)
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            int running = 0;
            lowestBalance = chronological.first.amount;
            for (final tx in chronological) {
              running += tx.isIn ? tx.amount : -tx.amount;
              if (running < lowestBalance) lowestBalance = running;
            }
          }

          final filteredList = txns.where((tx) {
            if (filter == 'IN') return tx.isIn;
            if (filter == 'OUT') return !tx.isIn;
            return true;
          }).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              // 1. Available Balance Yellow Card with Action Buttons Inside (Original Design)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFCC00),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
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
                      '${formatRwf(currentBalance)} RWF',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Action Buttons Row Inside Card
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ActionButton(
                          icon: Icons.send,
                          label: 'Send',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SendMoneyScreen(currentBalance: currentBalance),
                              ),
                            );
                          },
                        ),
                        _ActionButton(
                          icon: Icons.local_atm,
                          label: 'Cash Out',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AgentCashOutScreen(currentBalance: currentBalance),
                              ),
                            );
                          },
                        ),
                        _ActionButton(
                          icon: Icons.call_received,
                          label: 'Receive',
                          onTap: () => _promptReceiveMoney(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 2. Statistics Row: Total IN, Total OUT, Lowest (Original Design)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Total IN',
                        value: '+${formatRwf(totalIn)} RWF',
                        color: Colors.green[700]!,
                        icon: Icons.arrow_downward,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        title: 'Total OUT',
                        value: '-${formatRwf(totalOut)} RWF',
                        color: Colors.red[700]!,
                        icon: Icons.arrow_upward,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        title: 'Lowest',
                        value: '${formatRwf(lowestBalance)} RWF',
                        color: Colors.blue[800]!,
                        icon: Icons.trending_down,
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Cloud Synced Badge & Weather Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_done, color: Color(0xFFE5A800), size: 26),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kigali 27°C · Cloudy',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'Cloud Firestore · Synced & Private',
                            style: TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5A800),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Live',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Section Title & Filter Chips
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    const Text(
                      'Transactions',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 6,
                      children: [
                        FilterChip(
                          label: const Text('All'),
                          selected: filter == 'All',
                          onSelected: (_) => setState(() => filter = 'All'),
                        ),
                        FilterChip(
                          label: const Text('IN'),
                          selected: filter == 'IN',
                          onSelected: (_) => setState(() => filter = 'IN'),
                        ),
                        FilterChip(
                          label: const Text('OUT'),
                          selected: filter == 'OUT',
                          onSelected: (_) => setState(() => filter = 'OUT'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 5. Transaction List with Swipe-to-delete, Long-press-to-confirm, and Tap-to-edit
              if (filteredList.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  alignment: Alignment.center,
                  child: const Text(
                    'No transactions to display',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              else
                ...filteredList.map((tx) {
                  return Dismissible(
                    key: Key(tx.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      await _delete(context, tx);
                      return false; // let the stream update the list
                    },
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: tx.isIn
                            ? const Color(0x264CAF50)
                            : const Color(0x26F44336),
                        child: Icon(
                          tx.isIn ? Icons.arrow_downward : Icons.arrow_upward,
                          color: tx.isIn ? Colors.green[800] : Colors.red[800],
                        ),
                      ),
                      title: Text(
                        tx.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')} · ${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${tx.isIn ? '+' : '-'}${formatRwf(tx.amount)} RWF',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: tx.isIn ? Colors.green[700] : Colors.red[700],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Delete',
                            onPressed: () => _delete(context, tx),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TxnEditForm(txn: tx),
                          ),
                        );
                      },
                      onLongPress: () => _delete(context, tx),
                    ),
                  );
                }),
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
            MaterialPageRoute(builder: (_) => const TxnEditForm()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ============================================================================
// 6. ACTION BUTTON & STAT CARD COMPONENTS (Original Styling)
// ============================================================================

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
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 7. EDIT & ADD TRANSACTION FORM (Session 6 Step 5)
// ============================================================================

class TxnEditForm extends StatefulWidget {
  const TxnEditForm({super.key, this.txn});
  final TransactionItem? txn;

  @override
  State<TxnEditForm> createState() => _TxnEditFormState();
}

class _TxnEditFormState extends State<TxnEditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late bool _isIn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.txn?.title ?? '');
    _amountController = TextEditingController(
        text: widget.txn != null ? widget.txn!.amount.toString() : '');
    _isIn = widget.txn?.isIn ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final title = _titleController.text.trim();
    final amount = int.parse(_amountController.text.trim());
    final uid = FirebaseBackend.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final txnData = {
        'title': title,
        'amount': amount,
        'isIn': _isIn,
      };

      if (widget.txn == null) {
        await FirebaseBackend.instance.addTransaction(uid, txnData);
      } else {
        await FirebaseBackend.instance
            .updateTransaction(uid, widget.txn!.id, txnData);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.txn == null
                ? 'Transaction added to Firestore'
                : 'Transaction updated'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.txn != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Transaction' : 'New Transaction'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Money In (+)'),
                      icon: Icon(Icons.arrow_downward, color: Colors.green),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Money Out (-)'),
                      icon: Icon(Icons.arrow_upward, color: Colors.red),
                    ),
                  ],
                  selected: {_isIn},
                  onSelectionChanged: (val) {
                    setState(() => _isIn = val.first);
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g. Keza, Salary, Transport',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a description' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount (RWF)',
                    hintText: 'e.g. 5000',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) return 'Enter a positive amount';
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFFFFCC00),
                    foregroundColor: Colors.black,
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          isEditing ? 'Save Changes' : 'Add Transaction',
                          style: const TextStyle(fontWeight: FontWeight.bold),
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

// ============================================================================
// 8. SEND MONEY SCREEN (Original Lab 2)
// ============================================================================

class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key, required this.currentBalance});
  final int currentBalance;

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final phoneController = TextEditingController();
  final amountController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    phoneController.dispose();
    amountController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final phone = phoneController.text.trim();
    final amountText = amountController.text.trim();
    final amount = int.tryParse(amountText);

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter recipient phone number')),
      );
      return;
    }

    if (!RegExp(r'^(078|079)\d{7}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number must start with 078 or 079 and be 10 digits')),
      );
      return;
    }

    if (amount == null || amount < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum transfer amount is 100 RWF')),
      );
      return;
    }

    if (amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient balance for this transfer!')),
      );
      return;
    }

    final uid = FirebaseBackend.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await FirebaseBackend.instance.addTransaction(uid, {
        'title': 'Sent to $phone',
        'amount': amount,
        'isIn': false,
        'createdAt': DateTime.now(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully sent ${formatRwf(amount)} RWF to $phone')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send Money')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, color: Colors.amber),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available Balance', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      Text(
                        '${formatRwf(widget.currentBalance)} RWF',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Recipient Phone Number',
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
                prefixIcon: Icon(Icons.money),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _handleSend,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFCC00),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send Money', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 9. AGENT CASH OUT SCREEN (Original Lab 6)
// ============================================================================

class AgentCashOutScreen extends StatefulWidget {
  const AgentCashOutScreen({super.key, required this.currentBalance});
  final int currentBalance;

  @override
  State<AgentCashOutScreen> createState() => _AgentCashOutScreenState();
}

class _AgentCashOutScreenState extends State<AgentCashOutScreen> {
  final amountController = TextEditingController();
  int calculatedAmount = 0;
  bool _busy = false;

  final List<int> notes = [5000, 2000, 1000, 500, 100];

  @override
  void initState() {
    super.initState();
    amountController.addListener(() {
      final val = int.tryParse(amountController.text.trim()) ?? 0;
      setState(() => calculatedAmount = val);
    });
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  Map<int, int> getNoteBreakdown(int total) {
    final breakdown = <int, int>{};
    int remaining = total;
    for (final note in notes) {
      final count = remaining ~/ note;
      if (count > 0) {
        breakdown[note] = count;
        remaining %= note;
      }
    }
    return breakdown;
  }

  Future<void> _handleCashOut() async {
    final amount = calculatedAmount;
    if (amount <= 0 || amount % 100 != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount must be a multiple of 100 RWF')),
      );
      return;
    }
    if (amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient balance for cash-out!')),
      );
      return;
    }

    final uid = FirebaseBackend.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await FirebaseBackend.instance.addTransaction(uid, {
        'title': 'Cash out at MoMo agent',
        'amount': amount,
        'isIn': false,
        'createdAt': DateTime.now(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully cashed out ${formatRwf(amount)} RWF')),
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
    final breakdown = getNoteBreakdown(calculatedAmount);

    return Scaffold(
      appBar: AppBar(title: const Text('Agent Cash Out')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (Multiple of 100)',
                hintText: 'e.g. 7500',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              color: Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[300]!),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Note Breakdown',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    if (breakdown.isEmpty)
                      const Text('Enter an amount to see notes breakdown', style: TextStyle(color: Colors.grey))
                    else
                      ...breakdown.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${formatRwf(e.key)} RWF Note'),
                              Text('× ${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _handleCashOut,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFCC00),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirm Cash Out', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 10. EXACT ORIGINAL DARTPAD PHONE DEVICE FRAME SIMULATOR
// ============================================================================

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
