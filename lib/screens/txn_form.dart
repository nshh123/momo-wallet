import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/txn.dart';
import '../state/wallet_state.dart';

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
  File? _photo; // picked receipt on phone, not uploaded yet

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

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 70,
    );
    if (picked == null) return;
    setState(() => _photo = File(picked.path));
  }

  Widget _photoPreview() {
    if (_photo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(_photo!, height: 180, fit: BoxFit.cover),
      );
    }
    final saved = widget.txn?.photoUrl;
    if (saved != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          saved,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => const SizedBox(
            height: 180,
            child: Center(child: Icon(Icons.broken_image)),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Read the brain before any await
    final wallet = context.read<WalletState>();
    final description = _descriptionController.text.trim();
    final amount = int.parse(_amountController.text.trim());

    setState(() => _busy = true);
    try {
      String? photoUrl = widget.txn?.photoUrl;
      if (_photo != null) {
        photoUrl = await wallet.uploadPhoto(_photo!);
      }

      final txn = Txn(
        description: description,
        amount: amount,
        isIn: _isIn,
        photoUrl: photoUrl,
      );

      if (widget.txn == null) {
        await wallet.add(txn);
      } else {
        await wallet.edit(widget.txn!.id, txn);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.txn == null
                ? 'Transaction and receipt saved'
                : 'Transaction updated'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.txn != null;
    final balance = context.watch<WalletState>().balance;

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
                // Live Balance Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFCC00).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFCC00)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Current Balance:',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '$balance RWF',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

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
                    hintText: 'e.g. Sent to Aline, Cash in',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a description' : null,
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
                    if (v == null || v.trim().isEmpty) return 'Enter an amount';
                    final n = int.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Enter a positive whole number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Receipt Photo Section
                _photoPreview(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pickPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFCC00),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isEditing ? 'Save Changes' : 'Record Transaction'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
