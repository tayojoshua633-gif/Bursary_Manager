// lib/screens/settings/clear_data_screen.dart

import 'package:flutter/material.dart';
import '../../db/database_helper.dart';

// Existing screens in your project
import '../classes/class_list_screen.dart';
import '../payments/payment_student_select_screen.dart';

class ClearDataScreen extends StatefulWidget {
  const ClearDataScreen({super.key});

  @override
  State<ClearDataScreen> createState() => _ClearDataScreenState();
}

class _ClearDataScreenState extends State<ClearDataScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  String _activeTerm = "";
  String _activeSession = "";
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    setState(() => _loading = true);

    _activeTerm = await _db.getActiveTerm();
    _activeSession =
        (await _db.getActiveSession())?['sessionName'] ?? "";

    if (mounted) setState(() => _loading = false);
  }

  // -------------------------------------------------------------------
  // CLEAR STUDENTS – CLASS OR ALL
  // -------------------------------------------------------------------

  Future<void> _clearStudentsInClass(int classId) async {
    final db = await _db.database;

    await db.delete("students", where: "classId = ?", whereArgs: [classId]);
    await db.delete("student_bills", where: "studentId NOT IN (SELECT id FROM students)");
    await db.delete("payments", where: "studentId NOT IN (SELECT id FROM students)");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Students cleared for selected class")),
    );
  }

  Future<void> _clearAllStudents() async {
    final db = await _db.database;

    await db.delete("students");
    await db.delete("student_bills");
    await db.delete("student_fee_breakdown");
    await db.delete("payments");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("All students, bills & payments cleared")),
    );
  }

  // -------------------------------------------------------------------
  // CLEAR PAYMENTS – CLASS OR SINGLE STUDENT
  // -------------------------------------------------------------------

  Future<void> _clearPaymentsInClass(int classId) async {
    final db = await _db.database;

    await db.rawDelete("""
      DELETE FROM payments 
      WHERE studentId IN (SELECT id FROM students WHERE classId = ?)
        AND term = ?
        AND session = ?
    """, [classId, _activeTerm, _activeSession]);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Payments cleared for selected class")),
    );
  }

  Future<void> _clearStudentPayments(int studentId) async {
    final db = await _db.database;

    await db.delete(
      "payments",
      where: "studentId = ? AND term = ? AND session = ?",
      whereArgs: [studentId, _activeTerm, _activeSession],
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Payments cleared for selected student")),
    );
  }

  // -------------------------------------------------------------------
  // CONFIRMATION DIALOG
  // -------------------------------------------------------------------

  Future<bool> _confirm(String message) async {
    return await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Confirm Action"),
            content: Text(message),
            actions: [
              TextButton(
                child: const Text("Cancel"),
                onPressed: () => Navigator.pop(context, false),
              ),
              ElevatedButton(
                child: const Text("Proceed"),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ??
        false;
  }

  // -------------------------------------------------------------------
  // BUILD UI
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Data Clearing Tools")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Active term + session
                Card(
                  child: ListTile(
                    title: Text("Active Term: $_activeTerm"),
                    subtitle: Text("Active Session: $_activeSession"),
                  ),
                ),

                const SizedBox(height: 20),

                // ------------------------------------------------------------
                // SECTION A — CLEAR STUDENTS
                // ------------------------------------------------------------
                const Text(
                  "A) Clear Students",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                // CLEAR STUDENTS IN CLASS
                ElevatedButton.icon(
                  icon: const Icon(Icons.group_remove),
                  label: const Text("Clear Students in Selected Class"),
                  onPressed: () async {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClassListScreen(
                          onClassSelected: (classId) async {
                            Navigator.pop(context); // close class picker

                            bool ok = await _confirm(
                              "Are you sure you want to CLEAR all students"
                              " in this class?",
                            );
                            if (!ok) return;

                            await _clearStudentsInClass(classId);
                          },
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),

                // CLEAR ALL STUDENTS
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete_forever),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  label: const Text("Clear ALL Students in Database"),
                  onPressed: () async {
                    bool ok = await _confirm(
                      "This will DELETE ALL STUDENTS, bills, payments.\n\n"
                      "Do you want to continue?",
                    );
                    if (!ok) return;

                    await _clearAllStudents();
                  },
                ),

                const SizedBox(height: 30),

                // ------------------------------------------------------------
                // SECTION B — CLEAR PAYMENTS
                // ------------------------------------------------------------
                const Text(
                  "B) Clear Student Payments",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                // CLEAR PAYMENTS IN CLASS
                ElevatedButton.icon(
                  icon: const Icon(Icons.money_off),
                  label: const Text("Clear Payments for Selected Class"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClassListScreen(
                          onClassSelected: (classId) async {
                            Navigator.pop(context);

                            bool ok = await _confirm(
                              "Clear ALL payments for this class (active term/session only)?",
                            );
                            if (!ok) return;

                            await _clearPaymentsInClass(classId);
                          },
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),

                // CLEAR PAYMENT FOR A SINGLE STUDENT
                ElevatedButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text("Search Student & Clear Payments"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentStudentSelectScreen(
                          onStudentSelected: (id, name) async {
                            Navigator.pop(context);

                            bool ok = await _confirm(
                              "Clear ALL payments for $name\n"
                              "(active term/session only)?",
                            );
                            if (!ok) return;

                            await _clearStudentPayments(id);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
