// lib/screens/staff/staff_setup/staff_salary_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../db/database_helper.dart';
import '../../../models/staff.dart';

class StaffSalaryScreen extends StatefulWidget {
  const StaffSalaryScreen({super.key});

  @override
  State<StaffSalaryScreen> createState() => _StaffSalaryScreenState();
}

class _StaffSalaryScreenState extends State<StaffSalaryScreen> {
  final _dbHelper = DatabaseHelper();
  final _currencyFormat = NumberFormat.currency(symbol: '\u20A6', decimalDigits: 2);
  List<Staff> _allStaff = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final staffData = await _dbHelper.getStaff();
      setState(() {
        _allStaff = staffData.map((e) => Staff.fromMap(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editSalary(Staff staff) async {
    final controller = TextEditingController(
      text: staff.salary > 0 ? staff.salary.toStringAsFixed(2) : '',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Salary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              staff.fullName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${staff.staffId} - ${staff.staffType}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Monthly Salary',
                border: OutlineInputBorder(),
                prefixText: '\u20A6 ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 0;
              Navigator.pop(ctx, value);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await _dbHelper.updateStaffSalary(staff.id!, result);
        _loadStaff();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Salary updated'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Salary'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allStaff.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No staff found',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _allStaff.length,
                  itemBuilder: (ctx, i) {
                    final staff = _allStaff[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.green.withValues(alpha: 0.2),
                              child: Text(
                                staff.fullName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    staff.fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${staff.staffId} - ${staff.staffType}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    staff.salary > 0
                                        ? _currencyFormat.format(staff.salary)
                                        : 'No salary set',
                                    style: TextStyle(
                                      color: staff.salary > 0
                                          ? Colors.green
                                          : Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _editSalary(staff),
                              icon: Icon(
                                staff.salary > 0 ? Icons.edit : Icons.add,
                                size: 16,
                              ),
                              label: Text(staff.salary > 0 ? 'Edit' : 'Set'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
