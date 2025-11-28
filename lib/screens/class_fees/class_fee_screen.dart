import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';

class ClassFeeScreen extends StatefulWidget {
  final int classId;
  final String className;

  const ClassFeeScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ClassFeeScreen> createState() => _ClassFeeScreenState();
}

class _ClassFeeScreenState extends State<ClassFeeScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Map<String, dynamic>> _feeItems = [];
  final Map<int, TextEditingController> _amountControllers = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFeeItems();
  }

  Future<void> _loadFeeItems() async {
    final db = await _db.database;

    final items = await db.query('fee_items', orderBy: 'name ASC');
    final savedFees = await db.query(
      'class_fees',
      where: 'classId = ?',
      whereArgs: [widget.classId],
    );

    Map<int, double> savedMap = {};
for (var f in savedFees) {
  final int feeItemId = f['feeItemId'] as int;
  final double amount = (f['amount'] as num).toDouble();
  savedMap[feeItemId] = amount;
}


    setState(() {
      _feeItems = items;

      for (var item in items) {
        final id = item['id'] as int;
        final controller = TextEditingController(
          text: savedMap[id]?.toString() ?? '',
        );
        _amountControllers[id] = controller;
      }

      _loading = false;
    });
  }

  Future<void> _save() async {
    final db = await _db.database;

    await db.delete(
      'class_fees',
      where: 'classId = ?',
      whereArgs: [widget.classId],
    );

    for (var item in _feeItems) {
      final id = item['id'] as int;
      final text = _amountControllers[id]!.text.trim();
      if (text.isNotEmpty) {
        await db.insert('class_fees', {
          'classId': widget.classId,
          'feeItemId': id,
          'amount': double.tryParse(text) ?? 0,
        });
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Class fees saved successfully')),
    );

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Class Fees — ${widget.className}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (var item in _feeItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextFormField(
                      controller: _amountControllers[item['id']]!,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: item['name'],
                        border: const OutlineInputBorder(),
                        prefixText: '₦ ',
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _save,
                  child: const Text('Save Fees'),
                ),
              ],
            ),
    );
  }
}
