import 'package:flutter/material.dart';
import '../../db/database_helper.dart';

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  DailyReportScreenState createState() => DailyReportScreenState();
}

class DailyReportScreenState extends State<DailyReportScreen> {
  final DatabaseHelper db = DatabaseHelper();

  DateTime selectedDate = DateTime.now();

  double cashTotal = 0;
  double posTotal = 0;
  double transferTotal = 0;
  double totalIncome = 0;

  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadDailyReport();
  }

  // -----------------------------------------------------------
  // LOAD DAILY REPORT
  // -----------------------------------------------------------
  Future<void> _loadDailyReport() async {
    if (!mounted) return;

    setState(() => loading = true);

    final dateStr = _formatDate(selectedDate);
    final raw = await db.getPaymentsByExactDate(dateStr);

    // Reset totals
    cashTotal = 0;
    posTotal = 0;
    transferTotal = 0;

    for (var p in raw) {
      final method = (p['method'] ?? '').toString().toUpperCase();
      final amount = (p['amount'] is num)
          ? p['amount'] as num
          : double.tryParse(p['amount'].toString()) ?? 0.0;

      if (method == 'CASH') {
        cashTotal += amount;
      } else if (method == 'POS') {
        posTotal += amount;
      } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
        transferTotal += amount;
      }
    }

    totalIncome = cashTotal + posTotal + transferTotal;

    if (mounted) {
      setState(() => loading = false);
    }
  }

  String _formatDate(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  // -----------------------------------------------------------
  // PICK DATE
  // -----------------------------------------------------------
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
      await _loadDailyReport();
    }
  }

  // -----------------------------------------------------------
  // UI
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Daily Report"),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
          )
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    "Report for ${_formatDate(selectedDate)}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Summary Card
                  Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          _row("Cash Received", "₦$cashTotal"),
                          const SizedBox(height: 10),
                          _row("POS Received", "₦$posTotal"),
                          const SizedBox(height: 10),
                          _row("Transfers Received", "₦$transferTotal"),
                          const Divider(height: 25),
                          _row(
                            "TOTAL INCOME",
                            "₦$totalIncome",
                            bold: true,
                            color: Colors.green,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: ElevatedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.filter_alt),
                        label: const Text("Filter by date"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
    );
  }

  // -----------------------------------------------------------
  // ROW BUILDER
  // -----------------------------------------------------------
  Widget _row(
    String label,
    String value, {
    bool bold = false,
    Color color = Colors.black,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}
