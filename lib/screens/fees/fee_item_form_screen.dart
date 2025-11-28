import 'package:flutter/material.dart';
import '../../db/database_helper.dart';

class FeeItemFormScreen extends StatefulWidget {
  final Map<String, dynamic>? item; // null = new, not null = edit

  const FeeItemFormScreen({super.key, this.item});

  @override
  State<FeeItemFormScreen> createState() => _FeeItemFormScreenState();
}

class _FeeItemFormScreenState extends State<FeeItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  final DatabaseHelper _db = DatabaseHelper();

  String? _activeTerm;
  String? _activeSession;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    // Load current active term + session
    _activeTerm = await _db.getActiveTerm();
    _activeSession =
        (await _db.getActiveSession())?['sessionName'] ?? '';

    // If editing, pre-fill fields
    if (widget.item != null) {
      _nameCtrl.text = widget.item!['name'] ?? '';
      _amountCtrl.text = (widget.item!['defaultAmount'] ?? 0).toString();
      _descCtrl.text = widget.item!['description'] ?? '';
    }

    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final double amount =
        double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

    final payload = {
      "name": _nameCtrl.text.trim(),
      "defaultAmount": amount,
      "description": _descCtrl.text.trim(),
      "term": _activeTerm,
      "session": _activeSession,
    };

    if (widget.item == null) {
      // INSERT NEW
      await _db.insertFeeItem(payload);
    } else {
      // UPDATE EXISTING
      await _db.updateFeeItem(widget.item!['id'], payload);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.item == null ? "Create Fee Item" : "Edit Fee Item"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _activeTerm == null
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // NAME
                    TextFormField(
                      controller: _nameCtrl,
                      decoration:
                          const InputDecoration(labelText: "Fee Item Name"),
                      validator: (v) =>
                          v == null || v.isEmpty ? "Enter name" : null,
                    ),
                    const SizedBox(height: 20),

                    // AMOUNT
                    TextFormField(
                      controller: _amountCtrl,
                      decoration:
                          const InputDecoration(labelText: "Default Amount"),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          v == null || v.isEmpty ? "Enter amount" : null,
                    ),
                    const SizedBox(height: 20),

                    // DESCRIPTION
                    TextFormField(
                      controller: _descCtrl,
                      decoration:
                          const InputDecoration(labelText: "Description"),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),

                    // TERM + SESSION INFO (READ ONLY)
                    Text(
                      "Term: $_activeTerm\nSession: $_activeSession",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 30),

                    // SAVE BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: const Text("Save"),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
