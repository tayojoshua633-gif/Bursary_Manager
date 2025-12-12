// lib/screens/payments/payment_record_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';
import 'payment_receipt_screen.dart';

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
  String _term = "";
  String _session = "";

  // CORRECTED: Term-specific calculations
  double _previousBalance = 0.0;     // Debt from previous terms
  double _currentTermBill = 0.0;     // Fees for current term only
  double _grandTotal = 0.0;          // Previous Balance + Current Term Bill
  double _paymentsThisTerm = 0.0;    // Payments made this term
  double _outstanding = 0.0;         // Grand Total - Payments This Term

  // For display: Sum of all grand totals across all terms

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String? _selectedMethod;
  DateTime _selectedDate = DateTime.now();

  // Payment methods
  final List<String> _methods = ["Cash", "Transfer", "POS"];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ---------------------------------------------------------------------------
  // LOAD ALL BILLING + PAYMENT DATA
  // ---------------------------------------------------------------------------
  Future<void> _loadData() async {
    setState(() => _loading = true);

    final db = await _db.database;

    // Load student WITH class and arm names using JOIN
    final studentRows = await db.rawQuery('''
      SELECT 
        s.*,
        c.name as className,
        a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.id = ?
    ''', [widget.studentId]);

    if (studentRows.isNotEmpty) {
      _student = studentRows.first;
    }

    _term = await _db.getActiveTerm();
    _session = (await _db.getActiveSession())?['sessionName'] ?? "";

    // Get current term bill
    final bill = await _db.getBillForStudent(widget.studentId, _term, _session);
    
    if (bill != null) {
      // Grand Total = totalAmount (already includes previousBalance)
      _grandTotal = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
      _previousBalance = (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;
      // Current Term Bill = Grand Total - Previous Balance
      _currentTermBill = _grandTotal - _previousBalance;
    } else {
      _grandTotal = 0.0;
      _previousBalance = 0.0;
      _currentTermBill = 0.0;
    }

    // Get payments for CURRENT TERM only
    final pays = await _db.getPayments(
      widget.studentId,
      term: _term,
      session: _session,
    );

    _paymentsThisTerm = pays.fold<double>(
      0.0,
      (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0.0),
    );

    // CORRECTED: Outstanding = Grand Total (Current Term) - Payments (Current Term)
    _outstanding = _grandTotal - _paymentsThisTerm;


    if (mounted) setState(() => _loading = false);
  }

  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
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
      'term': _term,
      'session': _session,
    };

    int paymentId = 0;

    try {
      paymentId = await _db.insertPayment(payment);

      if (!mounted) return;

      // Show success toast
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Payment recorded successfully"),
          backgroundColor: Colors.green,
        ),
      );

      // OPEN RECEIPT PAGE
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentReceiptScreen(
            paymentId: paymentId,
            studentId: widget.studentId,
          ),
        ),
      );

      // After returning from receipt, close this screen too
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Record Payment — ${widget.studentName}"),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Student Info Card
                  Card(
                    elevation: 2,
                    color: Colors.blue.shade50,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade700,
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      title: Text(
                        widget.studentName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        "${_student?['className'] ?? 'No Class'} - ${_student?['armName'] ?? 'No Arm'}",
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Adm. No:',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          Text(
                            _student?['admissionNo'] ?? 'N/A',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Term/Session Info
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.event, size: 20, color: Colors.indigo),
                              const SizedBox(height: 4),
                              Text(
                                _term,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.calendar_today, size: 20, color: Colors.indigo),
                              const SizedBox(height: 4),
                              Text(
                                _session,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Financial Summary Header
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        "Current Term Financial Summary",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Previous Balance
                  _infoCard(
                    "Previous Balance",
                    _previousBalance,
                    Colors.orange,
                    Icons.history,
                  ),
                  const SizedBox(height: 8),

                  // Current Term Bill
                  _infoCard(
                    "Current Term Fees",
                    _currentTermBill,
                    Colors.blue,
                    Icons.receipt_long,
                  ),
                  const SizedBox(height: 8),

                  const Divider(thickness: 1),
                  const SizedBox(height: 8),

                  // Grand Total (Current Term)
                  _infoCard(
                    "Grand Total (This Term)",
                    _grandTotal,
                    Colors.purple,
                    Icons.summarize,
                    subtitle: "Previous + Current Fees",
                  ),
                  const SizedBox(height: 8),

                  // Payments This Term
                  _infoCard(
                    "Paid This Term",
                    _paymentsThisTerm,
                    Colors.green,
                    Icons.payment,
                  ),
                  const SizedBox(height: 8),

                  const Divider(thickness: 2),
                  const SizedBox(height: 8),

                  // CORRECTED Outstanding Balance (Current Term)
                  Card(
                    elevation: 3,
                    color: _outstanding > 0 ? Colors.red.shade50 : Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _outstanding > 0 ? Icons.warning : Icons.check_circle,
                                color: _outstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Outstanding (This Term)",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Grand Total - Paid This Term",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            "₦${NumberFormat("#,##0.00").format(_outstanding)}",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _outstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),


                  const SizedBox(height: 24),

                  // Payment Form Header
                  const Row(
                    children: [
                      Icon(Icons.add_card, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        "Record New Payment",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Amount Field
                  TextField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: "Amount Paid",
                      prefixText: "₦",
                      prefixIcon: const Icon(Icons.money),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.green.shade50,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Payment Method Dropdown
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: "Payment Method",
                      prefixIcon: const Icon(Icons.payment),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: _methods
                        .map((m) =>
                            DropdownMenuItem<String>(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedMethod = v),
                  ),

                  const SizedBox(height: 16),

                  // Payment Date Field
                  TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "Payment Date",
                      prefixIcon: const Icon(Icons.calendar_today),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar),
                        onPressed: _pickDate,
                      ),
                    ),
                    controller: TextEditingController(
                      text: DateFormat("EEEE, MMM dd, yyyy").format(_selectedDate),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Note Field
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "Note (Optional)",
                      prefixIcon: const Icon(Icons.note),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      hintText: "Enter any additional notes...",
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save, size: 24),
                      label: const Text(
                        "Save Payment",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _savePayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _infoCard(
    String title,
    double amount,
    Color color,
    IconData icon, {
    String? subtitle,
  }) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                  ],
                ),
              ],
            ),
            Text(
              "₦${NumberFormat("#,##0.00").format(amount)}",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}