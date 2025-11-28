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

  @override
  void initState() {
    super.initState();
    current = widget.student;
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
    ImageProvider? photo;
    if (current.photoPath != null &&
        current.photoPath!.isNotEmpty &&
        File(current.photoPath!).existsSync()) {
      photo = FileImage(File(current.photoPath!));
    }

    return Scaffold(
      appBar: AppBar(title: Text("${current.surname} ${current.firstName}")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // PHOTO
            CircleAvatar(
              radius: 65,
              backgroundImage: photo,
              child: photo == null
                  ? const Icon(Icons.person, size: 70)
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
                    info("Surname:", current.surname),
                    info("First Name:", current.firstName),
                    info("Other Name:", current.otherName),
                    info("Gender:", current.gender),
                    info("Date of Birth:", current.dob),
                    info("Class:", current.className),
                    info("Arm:", current.armName),
                    info("Address:", current.address),
                    info("Parent Name:", current.parentName),
                    info("Parent Phone:", current.parentPhone),
                    info("Parent Email:", current.parentEmail),
                    info("Parent Address:", current.parentAddress),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

            // BILLING + PAYMENTS + PAYMENT HISTORY
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.receipt_long),
                  label: const Text("Bill"),
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
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.payment),
                  label: const Text("Pay"),
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
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text("History"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
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
            ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text("Edit Info"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                final changed = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentEditScreen(student: current),
                  ),
                );

                if (changed == true) {
                  final freshMap =
                      await DatabaseHelper().getStudentById(current.id!);

                  if (freshMap != null && mounted) {
                    final freshStudent = Student.fromMap(freshMap);
                    setState(() => current = freshStudent);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
