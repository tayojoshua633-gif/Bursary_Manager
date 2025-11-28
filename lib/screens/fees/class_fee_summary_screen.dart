import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';

class ClassFeeSummaryScreen extends StatefulWidget {
  final int classId;
  final String className;

  const ClassFeeSummaryScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ClassFeeSummaryScreen> createState() => _ClassFeeSummaryScreenState();
}

class _ClassFeeSummaryScreenState extends State<ClassFeeSummaryScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  List<Map<String, dynamic>> _summary = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _loading = true);

    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT fi.name AS feeName, cf.amount
      FROM class_fees cf
      JOIN fee_items fi ON fi.id = cf.feeItemId
      WHERE cf.classId = ?
      ORDER BY fi.name ASC
    ''', [widget.classId]);

    setState(() {
      _summary = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Fee Summary – ${widget.className}"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _summary.isEmpty
              ? const Center(
                  child: Text(
                    "No fees assigned to this class",
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1), // FIXED
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Total Fees: ₦${_summary.fold<double>(
                              0,
                              (sum, row) => sum + (row['amount'] as num).toDouble(),
                            )}",
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    ..._summary.map(
                      (row) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.payments),
                          title: Text(row['feeName']),
                          trailing: Text(
                            "₦${row['amount']}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ), // FIX: no .toList()
                  ],
                ),
    );
  }
}
