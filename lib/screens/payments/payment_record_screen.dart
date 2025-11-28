import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';

class PaymentRecordScreen extends StatefulWidget {
  final int studentId;
  final String studentName;

  const PaymentRecordScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<PaymentRecordScreen> createState() => _PaymentRecordScreenState();
}

class _PaymentRecordScreenState extends State<PaymentRecordScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  bool _loading = true;

  Map<String, dynamic>? _student;
  double _outstanding = 0.0;

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String? _selectedMethod;
  DateTime _selectedDate = DateTime.now();

  final List<String> _methods = [
    "Cash",
    "Transfer",
    "POS",
    "Cheque",
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    _student = await _db.getStudentById(widget.studentId);
    _outstanding = await _db.computeOutstandingBalance(widget.studentId);

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _selectedDate,
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _savePayment() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid amount")),
      );
      return;
    }

    if (_selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select a payment method")),
      );
      return;
    }

    final payment = {
      'studentId': widget.studentId,
      'amount': amount,
      'method': _selectedMethod,
      'note': _noteCtrl.text.trim(),
      'paymentDate': _selectedDate.toIso8601String(),
      // term & session are auto-filled inside insertPayment()
    };

    try {
      await _db.insertPayment(payment);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Payment recorded successfully")),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Record Payment - ${widget.studentName}"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // STUDENT CARD
                  Card(
                    child: ListTile(
                      title: Text(widget.studentName),
                      subtitle: Text(
                        "${_student?['className'] ?? ''} ${_student?['armName'] ?? ''}",
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // OUTSTANDING BALANCE
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Outstanding Balance",
                              style: TextStyle(fontSize: 16)),
                          Text(
                            NumberFormat.currency(symbol: '')
                                .format(_outstanding),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // AMOUNT
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Amount Paid",
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // METHOD
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: "Payment Method",
                      border: OutlineInputBorder(),
                    ),
                    items: _methods
                        .map((m) =>
                            DropdownMenuItem<String>(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedMethod = v),
                    validator: (v) => v == null ? "Required" : null,
                  ),

                  const SizedBox(height: 20),

                  // DATE
                  TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "Payment Date",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: _pickDate,
                      ),
                    ),
                    controller: TextEditingController(
                      text: DateFormat("yyyy-MM-dd").format(_selectedDate),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // NOTE
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Note (Optional)",
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text("Save Payment"),
                      onPressed: _savePayment,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
