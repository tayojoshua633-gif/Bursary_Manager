import 'package:flutter/material.dart';
import '../../db/database_helper.dart';

class FeeClassAssignmentScreen extends StatefulWidget {
  const FeeClassAssignmentScreen({super.key});

  @override
  State<FeeClassAssignmentScreen> createState() =>
      _FeeClassAssignmentScreenState();
}

class _FeeClassAssignmentScreenState extends State<FeeClassAssignmentScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _feeItems = [];

  String? _activeTerm;
  String? _activeSession;
  int? _selectedClassId;

  final Map<int, TextEditingController> _amountCtrl = {};
  bool _loading = true;
  double _total = 0;

  final List<String> _terms = ["1st Term", "2nd Term", "3rd Term"];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // -----------------------------------------------------------
  // LOAD ACTIVE TERM/SESSION + CLASSES + FEE ITEMS
  // -----------------------------------------------------------
  Future<void> _load() async {
    setState(() => _loading = true);

    _activeTerm = await _db.getActiveTerm();
    _activeSession =
        (await _db.getActiveSession())?['sessionName'] ?? "";

    _classes = await _db.getClasses();
    _feeItems = await _db.getFeeItems(
      term: _activeTerm,
      session: _activeSession,
    );

    _amountCtrl.clear();

    for (var item in _feeItems) {
      final id = item['id'] as int;
      final defaultAmount =
          (item['defaultAmount'] ?? 0).toString();

      _amountCtrl[id] = TextEditingController(text: defaultAmount)
        ..addListener(_recalculateTotal);
    }

    _recalculateTotal();
    if (mounted) setState(() => _loading = false);
  }

  // -----------------------------------------------------------
  // WHEN A CLASS IS SELECTED
  // -----------------------------------------------------------
  Future<void> _onClassChanged(int? classId) async {
    if (classId == null) return;

    _selectedClassId = classId;
    setState(() => _loading = true);

    final rows = await _db.getClassFees(
      classId,
      term: _activeTerm ?? "",
      session: _activeSession ?? "",
    );

    for (var item in _feeItems) {
      final id = item['id'] as int;

      final match = rows.firstWhere(
        (r) => r['feeItemId'] == id,
        orElse: () => {},
      );

      final amount =
          match.isNotEmpty ? (match['amount'] ?? 0) : (item['defaultAmount'] ?? 0);

      _amountCtrl[id]?.text = amount.toString();
    }

    _recalculateTotal();
    if (mounted) setState(() => _loading = false);
  }

  // -----------------------------------------------------------
  // UPDATE TOTAL BILL
  // -----------------------------------------------------------
  void _recalculateTotal() {
    double t = 0;

    for (var item in _feeItems) {
      final id = item['id'] as int;
      final ctrl = _amountCtrl[id];
      if (ctrl == null) continue;

      final amount = double.tryParse(ctrl.text.trim()) ?? 0;
      t += amount;
    }

    setState(() => _total = t);
  }

  // -----------------------------------------------------------
  // SAVE TO DATABASE
  // -----------------------------------------------------------
  Future<void> _saveAssignments() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a class")),
      );
      return;
    }

    final sessionVal = _activeSession ?? "";

    List<Map<String, dynamic>> rows = [];

    for (var item in _feeItems) {
      final id = item['id'] as int;
      final ctrl = _amountCtrl[id];

      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        final amount = double.tryParse(ctrl.text.trim()) ?? 0;

        rows.add({
          'classId': _selectedClassId,
          'feeItemId': id,
          'amount': amount,
          'term': _activeTerm,
          'session': sessionVal,
        });
      }
    }

    await _db.replaceClassFeesFor(
      _selectedClassId!,
      term: _activeTerm!,
      session: sessionVal,
      fees: rows,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Class fee assignments saved")),
    );

    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    for (var c in _amountCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // -----------------------------------------------------------
  // UI
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Assign Fees to Class")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // CLASS SELECT
                const Text("Select Class",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),

                DropdownButtonFormField<int>(
                  initialValue: _selectedClassId,
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                  items: _classes
                      .map((c) => DropdownMenuItem<int>(
                            value: c['id'],
                            child: Text(c['name']),
                          ))
                      .toList(),
                  onChanged: _onClassChanged,
                ),

                const SizedBox(height: 20),

                // TERM SELECT
                const Text("Select Term",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),

                DropdownButtonFormField<String>(
                  initialValue: _activeTerm,
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                  items: _terms
                      .map((t) => DropdownMenuItem<String>(
                            value: t,
                            child: Text(t),
                          ))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    _activeTerm = v;
                    await _load();
                    if (_selectedClassId != null) {
                      await _onClassChanged(_selectedClassId);
                    }
                  },
                ),

                const SizedBox(height: 20),

                // FEE ITEMS
                const Text("Fee Items",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Divider(),

                ..._feeItems.map((item) {
                  final id = item['id'] as int;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['name'],
                            style:
                                const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _amountCtrl[id],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Amount",
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _recalculateTotal(),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    "Total: ₦${_total.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                ElevatedButton(
                  onPressed: _saveAssignments,
                  child: const Text("SAVE"),
                ),
              ],
            ),
    );
  }
}
