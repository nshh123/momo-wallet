import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/txn.dart';
import '../repositories/txn_repository.dart';

class WalletState extends ChangeNotifier {
  WalletState(this._repo) {
    debugPrint('Brain born for ${_repo.uid}');
    // Born: open the pipe to the backend, once.
    _subscription = _repo.watchAll().listen(
      (list) {
        _transactions = list;
        _loading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object e) {
        _loading = false;
        _error = 'Could not load your transactions.';
        notifyListeners();
      },
    );
  }

  final TxnRepository _repo;
  StreamSubscription<List<Txn>>? _subscription;

  // The data: private, so only the brain can change it.
  List<Txn> _transactions = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // 'all', 'in', 'out'

  // Read-only views for the screens.
  List<Txn> get transactions => _transactions;
  bool get loading => _loading;
  String? get error => _error;
  String get filter => _filter;

  // Habit 2: never saved, computed every time it is read.
  int get balance => _transactions.fold<int>(
        0,
        (total, t) => t.isIn ? total + t.amount : total - t.amount,
      );

  int get totalIn => _transactions
      .where((t) => t.isIn)
      .fold<int>(0, (acc, t) => acc + t.amount);

  int get totalOut => _transactions
      .where((t) => !t.isIn)
      .fold<int>(0, (acc, t) => acc + t.amount);

  // Step 18: Visible transactions according to selected filter
  List<Txn> get visible {
    if (_filter == 'in') return _transactions.where((t) => t.isIn).toList();
    if (_filter == 'out') return _transactions.where((t) => !t.isIn).toList();
    return _transactions;
  }

  void setFilter(String value) {
    _filter = value;
    notifyListeners();
  }

  // Actions: the brain hands the job to the repository.
  Future<void> add(Txn txn) => _repo.add(txn);
  Future<void> edit(String id, Txn txn) => _repo.update(id, txn);
  Future<void> remove(Txn txn) => _repo.delete(txn.id);
  Future<void> restore(Txn txn) =>
      _repo.setWithTimestamp(txn.id, txn, txn.createdAt);

  @override
  void dispose() {
    debugPrint('Brain disposed: pipe closed');
    _subscription?.cancel();
    super.dispose();
  }
}
