// lib/screens/billing/bill_generate_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';

class BillGenerateScreen extends StatefulWidget {
  final int studentId;
  final String studentName;

  const BillGenerateScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<BillGenerateScreen> createState() => _BillGenerateScreenState();
}

class _BillGenerateScreenState extends State<BillGenerateScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  bool _loading = true;

  Map<String, dynamic>? _student;
  String _term = '';
  String _session = '';

  List<_FeeLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    _student = await _db.getStudentById(widget.studentId);

    _term = await _db.getActiveTerm();
    final sess = await _db.getActiveSession();
    _session = sess?['sessionName'] ?? '';

    // Convert classId safely
    int? classId;
    final rawClass = _student?['classId'];
    classId = rawClass is int ? rawClass : int.tryParse(rawClass.toString());

    List<Map<String, dynamic>> classFees = [];

    if (classId != null) {
      try {
        classFees = await _db.getClassFees(
          classId,
          term: _term,
          session: _session,
        );
      } catch (_) {}
    }

    if (classFees.isNotEmpty) {
      _lines = classFees.map((cf) {
        final id = cf['feeItemId'] is int
            ? cf['feeItemId']
            : int.tryParse(cf['feeItemId'].toString()) ?? 0;

        final amt = cf['amount'] is num
            ? (cf['amount'] as num).toDouble()
            : double.tryParse(cf['amount'].toString()) ?? 0.0;

        return _FeeLine(
          feeItemId: id,
          label: cf['feeItemName']?.toString() ?? "Fee",
          amount: amt,
        );
      }).toList();
    } else {
      final items = await _db.getFeeItems(term: _term, session: _session);

      _lines = items.map((it) {
        final id = it['id'] is int
            ? it['id']
            : int.tryParse(it['id'].toString()) ?? 0;

        final amt = it['defaultAmount'] is num
            ? (it['defaultAmount'] as num).toDouble()
            : double.tryParse(it['defaultAmount'].toString()) ?? 0.0;

        return _FeeLine(
          feeItemId: id,
          label: it['name']?.toString() ?? "Fee",
          amount: amt,
        );
      }).toList();
    }

    if (mounted) setState(() => _loading = false);
  }

  // ------------------ Totals ------------------

  double get _subtotal =>
      _lines.fold(0.0, (p, l) => p + (l.amount ?? 0.0));

  double get _grandTotal => _subtotal;

  // ------------------ Save Bill ------------------

  Future<void> _saveBill() async {
    if (_lines.every((l) => (l.amount ?? 0.0) <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter valid fee amounts")),
      );
      return;
    }

    final bill = {
      'studentId': widget.studentId,
      'totalAmount': _subtotal,
      'previousBalance': 0, // Always zero now
      'term': _term,
      'session': _session,
      'billDate': DateTime.now().toIso8601String(),
    };

    final breakdown = _lines
        .map((l) => {
              'feeItemId': l.feeItemId,
              'amount': l.amount ?? 0.0,
              'label': l.label,
            })
        .toList();

    try {
      final id = await _db.insertStudentBill(bill, breakdown);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Bill created (ID: $id)")),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save bill: $e")),
      );
    }
  }

  // ------------------ Edit Amount ------------------

  void _editAmountDialog(_FeeLine line) {
    final ctrl = TextEditingController(
      text: (line.amount ?? 0.0).toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Edit Amount – ${line.label}"),
        content: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: "Amount"),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: const Text("Save"),
            onPressed: () {
              line.amount = double.tryParse(ctrl.text) ?? 0.0;
              setState(() {});
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // ------------------ Widgets ------------------

  Widget _buildLineItem(_FeeLine line) {
    return ListTile(
      title: Text(line.label),
      subtitle: Text("Fee ID: ${line.feeItemId}"),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(NumberFormat("#,##0.00").format(line.amount ?? 0.0)),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editAmountDialog(line),
          ),
        ],
      ),
    );
  }

  Widget _totalsRow(String label, double value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(NumberFormat("#,##0.00").format(value)),
      ],
    );
  }

  // ------------------ Build ------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Generate Bill – ${widget.studentName}"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Student Info
                  Card(
                    child: ListTile(
                      title: Text(widget.studentName),
                      subtitle: Text(
                        "${_student?['className'] ?? ''} ${_student?['armName'] ?? ''}",
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Term and session
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text("Term"),
                                Text(_term),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text("Session"),
                                Text(_session),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Fee list
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _lines.isEmpty
                            ? const Center(
                                child:
                                    Text("No fee items for this class."),
                              )
                            : ListView.separated(
                                itemCount: _lines.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) =>
                                    _buildLineItem(_lines[i]),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Totals
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _totalsRow("Subtotal", _subtotal),
                          const Divider(),
                          _totalsRow("Grand Total", _grandTotal),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: const Text("Save Bill"),
                          onPressed: _saveBill,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          child: const Text("Cancel"),
                          onPressed: () => Navigator.pop(context, false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _FeeLine {
  final int feeItemId;
  final String label;
  double? amount;

  _FeeLine({
    required this.feeItemId,
    required this.label,
    required this.amount,
  });
}
