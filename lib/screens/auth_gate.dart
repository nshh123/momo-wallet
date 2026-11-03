import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../repositories/txn_repository.dart';
import '../state/wallet_state.dart';
import 'login_screen.dart';
import 'wallet_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }
        // Signed in: one brain for this user, given to the wallet screen.
        return ChangeNotifierProvider<WalletState>(
          create: (_) => WalletState(TxnRepository(user.uid)),
          child: const WalletScreen(),
        );
      },
    );
  }
}
