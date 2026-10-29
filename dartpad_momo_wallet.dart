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
    // Seed initial Aline account transactions
    _userTransactions['user_aline_1'] = [
      {
        'id': 'tx_1',
        'description': 'Opening balance',
        'amount': 10000,
        'isIn': true,
        'createdAt': DateTime.now().subtract(const Duration(hours: 3)),
      },
      {
        'id': 'tx_2',
        'description': 'Sent to 0788123456',
        'amount': 2500,
        'isIn': false,
        'createdAt': DateTime.now().subtract(const Duration(hours: 2)),
      },
      {
        'id': 'tx_3',
        'description': 'Received from Keza',
        'amount': 4000,
        'isIn': true,
        'createdAt': DateTime.now().subtract(const Duration(hours: 1)),
      },
    ];
  }
  static final FirebaseBackend instance = FirebaseBackend._();

  // Registered Auth users: email -> password
  final Map<String, String> _registeredUsers = {
    'aline@gmail.com': 'password123',
  };

  // User database mapping
  final Map<String, String> _uidToEmail = {
    'user_aline_1': 'aline@gmail.com',
  };
  final Map<String, String> _emailToUid = {
    'aline@gmail.com': 'user_aline_1',
  };

  MockUser? _currentUser;
  final StreamController<MockUser?> _authController =
      StreamController<MockUser?>.broadcast();

  // Firestore collections: 'users/{uid}/transactions'
  final Map<String, List<Map<String, dynamic>>> _userTransactions = {};
  final Map<String, StreamController<MockQuerySnapshot>> _streamControllers = {};

  // Rule break simulation (triggers [cloud_firestore/permission-denied])
  bool rulesViolated = false;

  MockUser? get currentUser => _currentUser;

  // Emits current auth state immediately, then listens for future auth changes
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
        return db.compareTo(da); // descending order
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
    // Yield first snapshot immediately so stream never hangs in waiting state
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

    // Seed sample data for the newly created account
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
        'description': 'Opening balance',
        'amount': 10000,
        'isIn': true,
        'createdAt': DateTime.now().subtract(const Duration(minutes: 5)),
      },
      {
        'id': 'tx_${DateTime.now().millisecondsSinceEpoch}_2',
        'description': 'Sent to 0788123456',
        'amount': 2500,
        'isIn': false,
        'createdAt': DateTime.now().subtract(const Duration(minutes: 3)),
      },
      {
        'id': 'tx_${DateTime.now().millisecondsSinceEpoch}_3',
        'description': 'Received from Keza',
        'amount': 4000,
        'isIn': true,
        'createdAt': DateTime.now().subtract(const Duration(minutes: 1)),
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
class Txn {
  Txn({
    this.id = '',
    required this.description,
    required this.amount,
    required this.isIn,
    this.createdAt,
  });

  final String id;
  final String description;
  final int amount;
  final bool isIn;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'description': description,
        'amount': amount,
        'isIn': isIn,
      };

  factory Txn.fromDoc(MockDocumentSnapshot doc) {
    final data = doc.data();
    return Txn(
      id: doc.id,
      description: data['description'] as String,
      amount: (data['amount'] as num).toInt(),
      isIn: data['isIn'] as bool,
      createdAt: data['createdAt'] as DateTime?,
    );
  }
}

// ============================================================================
// 2. ROOT APPLICATION WITH AUTH GATE & PHONE DEVICE FRAME
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
          seedColor: const Color(0xFFFFCC00),
          primary: const Color(0xFFE5A800),
          surface: Colors.grey.shade50,
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

// AuthGate (Step 2 of Lab)
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
// 3. LOGIN & REGISTRATION SCREEN (Step 1 of Lab)
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
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: Color(0xFFE5A800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'MoMo Wallet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Cloud Database · Firebase Authentication',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v ?? '').length < 6 ? 'At least 6 characters' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(newAccount: false),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFFE5A800),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text(
                      'Log in',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _submit(newAccount: true),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Create account'),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  const SizedBox(height: 24),
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
// 4. MAIN WALLET SCREEN (Step 2 Logout & Step 4 Live Streams)
// ============================================================================

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  String _filter = 'All';

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
      final uid = FirebaseBackend.instance.currentUser?.uid;
      if (uid == null) return;
      try {
        await FirebaseBackend.instance.deleteTransaction(uid, txn.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${txn.description}"'),
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
                'description': 'Received from $desc',
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
          // Step 6 Security Rules Break Simulator Button (for permission-denied screenshot)
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
                ? 'Rules Violated: Access Denied (Tap to restore)'
                : 'Simulate Security Rule Violation (For Screenshot)',
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

          final txns = snapshot.data!.docs.map(Txn.fromDoc).toList();

          // Computed, never saved
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

              // 2. Action Buttons (Send, Cash Out, Receive)
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

              // 4. Live Transactions or Empty State
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
                            'Tap + to record your first transaction.',
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
                                  ? '${t.createdAt!.hour.toString().padLeft(2, '0')}:${t.createdAt!.minute.toString().padLeft(2, '0')}'
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

// ============================================================================
// 5. TRANSACTION FORM (Step 3 Add & Step 5 Edit)
// ============================================================================

class TxnForm extends StatefulWidget {
  const TxnForm({super.key, this.txn});
  final Txn? txn;

  @override
  State<TxnForm> createState() => _TxnFormState();
}

class _TxnFormState extends State<TxnForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  late bool _isIn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _descriptionController =
        TextEditingController(text: widget.txn?.description ?? '');
    _amountController = TextEditingController(
        text: widget.txn != null ? widget.txn!.amount.toString() : '');
    _isIn = widget.txn?.isIn ?? true;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final description = _descriptionController.text.trim();
    final amount = int.parse(_amountController.text.trim());
    final uid = FirebaseBackend.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final txnData = {
        'description': description,
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
                  controller: _descriptionController,
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
                    backgroundColor: const Color(0xFFE5A800),
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
// 6. SEND & CASH OUT SCREENS
// ============================================================================

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.currentBalance});
  final int currentBalance;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _sendMoney() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = _phoneController.text.trim();
    final amount = int.parse(_amountController.text.trim());

    if (amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insufficient funds for this transfer!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final uid = FirebaseBackend.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await FirebaseBackend.instance.addTransaction(uid, {
        'description': 'Sent to $phone',
        'amount': amount,
        'isIn': false,
        'createdAt': DateTime.now(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully sent $amount RWF to $phone'),
            backgroundColor: Colors.green[800],
          ),
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Colors.amber),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Available Balance',
                              style: TextStyle(fontSize: 12, color: Colors.black54)),
                          Text(
                            '${widget.currentBalance} RWF',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'MTN Recipient Phone Number',
                    hintText: '078XXXXXXX or 079XXXXXXX',
                    prefixIcon: Icon(Icons.phone_android),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    final p = (val ?? '').trim();
                    if (p.isEmpty) return 'Enter a recipient phone number';
                    if (!RegExp(r'^(078|079)\d{7}$').hasMatch(p)) {
                      return 'Must be 10 digits starting with 078 or 079';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount (RWF)',
                    hintText: 'Minimum 100 RWF',
                    prefixIcon: Icon(Icons.money),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    final n = int.tryParse((val ?? '').trim());
                    if (n == null || n < 100) {
                      return 'Minimum transfer amount is 100 RWF';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _sendMoney,
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
                          'Confirm & Transfer',
                          style: TextStyle(fontWeight: FontWeight.bold),
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

    final uid = FirebaseBackend.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await FirebaseBackend.instance.addTransaction(uid, {
        'description': 'Cash out at MoMo agent',
        'amount': amount,
        'isIn': false,
        'createdAt': DateTime.now(),
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

// ============================================================================
// 7. PHONE DEVICE FRAME SIMULATION (For Professional DartPad Screenshots)
// ============================================================================

class _PhoneDeviceFrame extends StatelessWidget {
  const _PhoneDeviceFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E24), // Background canvas
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: FittedBox(
        fit: BoxFit.contain,
        child: Container(
          width: 390,
          height: 844, // iPhone aspect ratio
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(48),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
            border: Border.all(color: const Color(0xFF333338), width: 9),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: Stack(
              children: [
                // Inner Screen Content
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 36, bottom: 20),
                    child: child,
                  ),
                ),

                // Top Status Bar & Dynamic Island
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 38,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    color: Colors.transparent,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '9:41',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          width: 110,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        const Row(
                          children: [
                            Icon(Icons.signal_cellular_alt,
                                size: 14, color: Colors.black),
                            SizedBox(width: 4),
                            Icon(Icons.wifi, size: 14, color: Colors.black),
                            SizedBox(width: 4),
                            Icon(Icons.battery_full,
                                size: 16, color: Colors.black),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Home Indicator Bar
                Positioned(
                  bottom: 6,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 134,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(2),
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
