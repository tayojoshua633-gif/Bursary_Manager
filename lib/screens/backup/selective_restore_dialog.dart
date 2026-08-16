// lib/screens/backup/selective_restore_dialog.dart
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/intl.dart';

class SelectiveRestoreDialog extends StatefulWidget {
  final String backupFilePath;
  final String backupFileName;

  const SelectiveRestoreDialog({
    super.key,
    required this.backupFilePath,
    required this.backupFileName,
  });

  @override
  State<SelectiveRestoreDialog> createState() => _SelectiveRestoreDialogState();
}

class _SelectiveRestoreDialogState extends State<SelectiveRestoreDialog> {
  Map<String, bool> _selectedTables = {};
  Map<String, int> _tableCounts = {};
  bool _loading = true;
  String? _error;

  // Critical tables that should be restored together
  final Map<String, String> _tableDescriptions = {
    'students': 'Student records, photos, admission numbers',
    'classes': 'Class definitions (Primary 1, JSS 1, etc.)',
    'arms': 'Class subdivisions (A, B, C)',
    'fee_items': 'Fee definitions (Tuition, Development Levy, etc.)',
    'class_fees': 'Fee assignments to classes',
    'student_bills': 'Generated bills for students',
    'student_fee_breakdown': 'Itemized bill details',
    'payments': 'Payment records and receipts',
    'expenses': 'Expense tracking records',
    'print_counters': 'Daily print count history (bills, receipts, payment history)',
    'sessions': 'Academic sessions (2025/2026, etc.)',
    'settings': 'App configuration settings',
    'users': '⚠️ USER ACCOUNTS - Restoring will overwrite current users',
    'licenses': '⚠️ LICENSE - Restoring will overwrite this device\'s activation',
    'permissions': 'User permissions configuration',
    'promotion_history': 'Student promotion tracking',
    'school_profile': 'School information and branding',
    'special_fee_items': 'Special/optional fee definitions',
    'special_class_fees': 'Special fee assignments to classes',
    'excluded_default_fees': 'Fee exclusions for specific students',
    'stock_items': 'Stock/inventory item records',
    'sales': 'Sales transaction records',
    'stock_movements': 'Stock movement history (in/out)',
    'sales_debtors': 'Outstanding sales debtor records',
    'parents': 'Parent/guardian information',
    'staff': 'Staff member records',
    'staff_offices': 'Office/department definitions',
    'staff_class_allocations': 'Staff-to-class assignments',
    'staff_office_allocations': 'Staff-to-office assignments',
    'suppliers': 'Supplier/vendor records',
    'staff_incentives': 'Staff incentive/bonus records',
    'staff_loans': 'Staff loan records',
    'staff_deductions': 'Staff salary deduction records',
    'staff_salary_payments': 'Staff salary payment history',
    'school_divisions': 'School division definitions (Junior, Senior, etc.)',
    'division_class_allocations': 'Class-to-division assignments',
    'subjects': 'Subject definitions (Mathematics, English, etc.)',
    'activities': 'Activity/extracurricular definitions',
    'class_subject_allocations': 'Subject assignments to classes',
    'class_activity_allocations': 'Activity assignments to classes',
    'class_teacher_allocations': 'Class teacher assignments',
    'subject_teacher_allocations': 'Subject teacher assignments',
    'exams': 'Exam/assessment definitions',
    'grading_definitions': 'Grading scale definitions (A, B, C, etc.)',
    'student_scores': 'Student exam/test scores',
    'psychomotor_skills': 'Psychomotor skill definitions',
    'affective_traits': 'Affective trait definitions',
    'student_psychomotor_scores': 'Student psychomotor skill assessments',
    'student_affective_scores': 'Student affective trait assessments',
    'result_computations': 'Computed result/report card data',
    'fee_priority': 'Fee payment priority ordering for Fee Tracker',
    'staff_salary_history': 'Staff salary increment history per month',
    'expense_categories': 'Expense category definitions (preset & custom)',
    'external_examinations': 'External exam definitions (WAEC, NECO, JAMB, etc.)',
    'examination_registrations': 'Student exam registration records per session',
    'transport_routes': 'Transportation route definitions',
    'student_transport_allocations': 'Student-to-route assignments',
    'audit_log': 'Financial activity log (who edited/deleted what, and when)',
    'sms_log': 'SMS notification history sent to parents',
  };

  @override
  void initState() {
    super.initState();
    _loadBackupPreview();
  }

  Future<void> _loadBackupPreview() async {
    setState(() => _loading = true);

    try {
      // Open backup database
      final backupDb = await databaseFactoryFfi.openDatabase(
        widget.backupFilePath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      // Get all table names
      final tables = await backupDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' "
        "ORDER BY name",
      );

      // Get row count for each table
      final Map<String, int> counts = {};
      final Map<String, bool> selected = {};

      for (var table in tables) {
        final tableName = table['name'] as String;
        final countResult = await backupDb.rawQuery(
          'SELECT COUNT(*) as count FROM `$tableName`',
        );
        final count = countResult.first['count'] as int? ?? 0;

        counts[tableName] = count;

        // Default: select all tables EXCEPT users and licenses.
        // users  — prevents accidentally overwriting accounts on this device.
        // licenses — each device must keep its own activation key.
        selected[tableName] =
            tableName != 'users' && tableName != 'licenses';
      }

      await backupDb.close();

      if (mounted) {
        setState(() {
          _tableCounts = counts;
          _selectedTables = selected;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int get _selectedCount => _selectedTables.values.where((v) => v).length;
  int get _selectedRecords => _tableCounts.entries
      .where((e) => _selectedTables[e.key] == true)
      .fold(0, (sum, entry) => sum + entry.value);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restore, color: Colors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Selective Restore',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.backupFileName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.normal,
              color: Colors.grey,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading backup:',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Warning banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Select which tables to restore. Uncheck items you want to keep unchanged.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Summary
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selected Tables:',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '$_selectedCount of ${_selectedTables.length}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'Records:',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  NumberFormat('#,###').format(_selectedRecords),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Quick actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  for (var key in _selectedTables.keys) {
                                    // licenses is always kept unchecked
                                    if (key == 'licenses') continue;
                                    _selectedTables[key] = true;
                                  }
                                });
                              },
                              icon: const Icon(Icons.check_box, size: 16),
                              label: const Text('All', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  for (var key in _selectedTables.keys) {
                                    _selectedTables[key] = false;
                                  }
                                });
                              },
                              icon: const Icon(Icons.check_box_outline_blank, size: 16),
                              label: const Text('None', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Table list
                      const Text(
                        'Tables to Restore:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Expanded(
                        child: ListView(
                          children: _selectedTables.keys.map((tableName) {
                            final count = _tableCounts[tableName] ?? 0;
                            final isSelected = _selectedTables[tableName] ?? false;
                            final description = _tableDescriptions[tableName] ?? 'Database table';
                            final isUsersTable = tableName == 'users';
                            final isLicenseTable = tableName == 'licenses';
                            final isWarningTable = isUsersTable || isLicenseTable;
                            final warningColor = isUsersTable
                                ? Colors.red
                                : Colors.orange;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: isWarningTable
                                  ? (isSelected
                                      ? warningColor.shade50
                                      : Colors.grey.shade50)
                                  : (isSelected ? Colors.green.shade50 : null),
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedTables[tableName] = value ?? false;
                                  });
                                },
                                title: Row(
                                  children: [
                                    Text(
                                      tableName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: isWarningTable
                                            ? warningColor.shade700
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isUsersTable)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade700,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'CRITICAL',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    if (isLicenseTable)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade700,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'SKIP',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(
                                      description,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${NumberFormat('#,###').format(count)} record${count != 1 ? 's' : ''}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _selectedCount == 0
              ? null
              : () {
                  final selectedTablesList = _selectedTables.entries
                      .where((e) => e.value)
                      .map((e) => e.key)
                      .toList();
                  Navigator.pop(context, selectedTablesList);
                },
          icon: const Icon(Icons.restore),
          label: Text(_selectedCount == 0
              ? 'Select Tables'
              : 'Restore $_selectedCount Table${_selectedCount != 1 ? 's' : ''}'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
          ),
        ),
      ],
    );
  }
}
