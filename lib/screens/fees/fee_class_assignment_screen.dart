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
      _activeTerm ?? "",
      _activeSession ?? "",
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
      _activeTerm!,
      sessionVal,
      rows,
    );

    if (!mounted) return;

    final className = _classes.firstWhere(
      (c) => c['id'] == _selectedClassId,
      orElse: () => {'name': 'Unknown'},
    )['name'];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Fees saved for $className'),
        backgroundColor: Colors.green,
      ),
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
      appBar: AppBar(
        title: const Text("Assign Fees to Class"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ACTIVE TERM/SESSION DISPLAY - READ ONLY
                Card(
                  color: Colors.indigo.shade50,
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.indigo.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              'Active Period',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.event,
                                size: 18, color: Colors.indigo.shade700),
                            const SizedBox(width: 8),
                            const Text('Term: '),
                            Text(
                              _activeTerm ?? 'Not set',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 18, color: Colors.indigo.shade700),
                            const SizedBox(width: 8),
                            const Text('Session: '),
                            Text(
                              _activeSession ?? 'Not set',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info,
                                  size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Fees will be assigned for this term/session',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // CLASS SELECT
                const Text(
                  "Select Class",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                DropdownButtonFormField<int>(
                  initialValue: _selectedClassId,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.school),
                    hintText: 'Choose a class',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _classes
                      .map((c) => DropdownMenuItem<int>(
                            value: c['id'],
                            child: Text(c['name']),
                          ))
                      .toList(),
                  onChanged: _onClassChanged,
                ),

                const SizedBox(height: 24),

                // FEE ITEMS SECTION
                Row(
                  children: [
                    Icon(Icons.receipt_long, color: Colors.indigo.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "Fee Items (${_feeItems.length})",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(),

                // Empty state
                if (_feeItems.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No fee items for this term/session',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create fee items first',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Fee items list
                ..._feeItems.map((item) {
                  final id = item['id'] as int;
                  final name = item['name'] ?? '';
                  final defaultAmount = (item['defaultAmount'] ?? 0).toStringAsFixed(2);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.indigo.shade100,
                            child: Icon(Icons.attach_money,
                                color: Colors.indigo.shade700, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Default: ₦$defaultAmount',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _amountCtrl[id],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Amount",
                                border: OutlineInputBorder(),
                                prefixText: '₦',
                                isDense: true,
                              ),
                              onChanged: (_) => _recalculateTotal(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // TOTAL DISPLAY
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200, width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calculate, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            "Total Bill:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "₦${_total.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                // SAVE BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _feeItems.isEmpty ? null : _saveAssignments,
                    icon: const Icon(Icons.save),
                    label: const Text(
                      "SAVE ASSIGNMENTS",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Help text
                if (_selectedClassId == null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Select a class to assign fees',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}