// lib/screens/students/student_details_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/student.dart';
import '../../db/database_helper.dart';
import '../payments/payment_record_screen.dart';
import '../payments/payment_history_screen.dart';
import '../billing/bill_generate_screen.dart';
import 'student_edit_screen.dart';

class StudentDetailsScreen extends StatefulWidget {
  final Student student;

  const StudentDetailsScreen({super.key, required this.student});

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  late Student current;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStudentWithClassArm();
  }

  // Load student with class and arm names using JOIN
  Future<void> _loadStudentWithClassArm() async {
    setState(() => _loading = true);

    try {
      final db = await DatabaseHelper().database;
      
      // Query with JOIN to get class and arm names
      final result = await db.rawQuery('''
        SELECT 
          s.*,
          c.name as className,
          a.name as armName
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        WHERE s.id = ?
      ''', [widget.student.id]);

      if (result.isNotEmpty && mounted) {
        setState(() {
          current = Student.fromMap(result.first);
          _loading = false;
        });
      } else {
        // Fallback to original student data
        setState(() {
          current = widget.student;
          _loading = false;
        });
      }
    } catch (e) {
      // Fallback to original student data on error
      if (mounted) {
        setState(() {
          current = widget.student;
          _loading = false;
        });
      }
    }
  }

  Widget info(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value ?? '-'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Student Details")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    ImageProvider? photo;
    if (current.photoPath != null &&
        current.photoPath!.isNotEmpty &&
        File(current.photoPath!).existsSync()) {
      photo = FileImage(File(current.photoPath!));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("${current.surname} ${current.firstName}"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // PHOTO
            CircleAvatar(
              radius: 65,
              backgroundImage: photo,
              backgroundColor: Colors.blue.shade100,
              child: photo == null
                  ? Icon(
                      Icons.person,
                      size: 70,
                      color: Colors.blue.shade700,
                    )
                  : null,
            ),

            const SizedBox(height: 20),

            // FULL DETAILS CARD
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    info("Admission No:", current.admissionNo),
                    const Divider(),
                    info("Surname:", current.surname),
                    info("First Name:", current.firstName),
                    info("Other Name:", current.otherName),
                    info("Gender:", current.gender),
                    info("Date of Birth:", current.dob),
                    const Divider(),
                    info("Class:", current.className ?? 'Not Assigned'),
                    info("Arm:", current.armName ?? 'Not Assigned'),
                    const Divider(),
                    info("Address:", current.address),
                    const Divider(),
                    info("Parent Name:", current.parentName),
                    info("Parent Phone:", current.parentPhone),
                    info("Parent Email:", current.parentEmail),
                    info("Parent Address:", current.parentAddress),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            // ACTION BUTTONS SECTION
            const Text(
              "Quick Actions",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 12),

            // BILLING + PAYMENTS + PAYMENT HISTORY
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.receipt_long),
                  label: const Text("Generate Bill"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BillGenerateScreen(
                          studentId: current.id!,
                          studentName:
                              "${current.surname} ${current.firstName}",
                        ),
                      ),
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.payment),
                  label: const Text("Record Payment"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentRecordScreen(
                          studentId: current.id!,
                          studentName:
                              "${current.surname} ${current.firstName}",
                        ),
                      ),
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text("Payment History"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentHistoryScreen(
                          studentId: current.id!,
                          studentName:
                              "${current.surname} ${current.firstName}",
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // EDIT BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text(
                  "Edit Student Information",
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final changed = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentEditScreen(student: current),
                    ),
                  );

                  if (changed == true) {
                    // Reload student with class/arm names
                    _loadStudentWithClassArm();
                  }
                },
              ),
            ),

            const SizedBox(height: 12),

            // REFRESH BUTTON
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text("Refresh Data"),
              onPressed: _loadStudentWithClassArm,
            ),
          ],
        ),
      ),
    );
  }
}