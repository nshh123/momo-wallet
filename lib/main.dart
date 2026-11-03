// ============================================================================
// Session 7: State Management Translation Table
// MoMo Wallet               | What it is                    | This Project
// ----------------------------------------------------------------------------
// Txn, txn.dart             | Model                         | Txn, models/txn.dart
// transactions collection   | Firestore collection          | users/{uid}/transactions
// TxnRepository             | Repository (backend talker)   | TxnRepository, repositories/txn_repository.dart
// WalletState               | State class (the brain)       | WalletState, state/wallet_state.dart
// balance                   | Computed value (Habit 2)      | balance, totalIn, totalOut, visible
// WalletScreen, TxnForm     | List screen & Form screen     | WalletScreen, TxnForm, screens/
// ============================================================================

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MoMoApp());
}

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
      home: const AuthGate(),
    );
  }
}
