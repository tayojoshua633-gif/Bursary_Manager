// lib/screens/students/student_list_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';
import 'package:bursary_manager/models/student.dart';

import 'student_form_screen.dart';
import 'student_details_screen.dart';

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  List<Student> _students = [];
  bool _loading = true;
  String _search = "";

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);

    final raw = await _db.getAllStudents();
    final list = raw.map((m) => Student.fromMap(m)).toList();

    if (!mounted) return;

    setState(() {
      _students = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _students.where((s) {
      final name = "${s.surname} ${s.firstName}".toLowerCase();
      final adm = s.admissionNo.toLowerCase();
      final q = _search.toLowerCase();

      return name.contains(q) || adm.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Students"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StudentFormScreen()),
              ).then((value) {
                if (value == true) _loadStudents();
              });
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStudents,
              child: Column(
                children: [
                  // SEARCH BAR
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        hintText: "Search student...",
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),

                  // LIST
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text("No students found."))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final s = filtered[index];
                              final String name =
                                  "${s.surname} ${s.firstName}".trim();

                              ImageProvider? photo;
                              if (s.photoPath != null &&
                                  s.photoPath!.isNotEmpty &&
                                  File(s.photoPath!).existsSync()) {
                                photo = FileImage(File(s.photoPath!));
                              }

                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: photo,
                                    child: photo == null
                                        ? const Icon(Icons.person)
                                        : null,
                                  ),
                                  title: Text(name),
                                  subtitle:
                                      Text("Adm No: ${s.admissionNo}"),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            StudentDetailsScreen(
                                                student: s),
                                      ),
                                    ).then((value) {
                                      if (value == true) _loadStudents();
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
