import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';

class DeactivateStudentScreen extends StatefulWidget {
  const DeactivateStudentScreen({super.key});

  @override
  State<DeactivateStudentScreen> createState() =>
      _DeactivateStudentScreenState();
}

class _DeactivateStudentScreenState extends State<DeactivateStudentScreen> {
  final db = DatabaseHelper();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _reasonCtrl = TextEditingController();

  List<Map<String, dynamic>> results = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    // FIXED: Removed kw parameter - getActiveStudents() has no parameters
    results = await db.getActiveStudents();
    setState(() => isLoading = false);
  }

  Future<void> _search(String kw) async {
    setState(() => isLoading = true);
    
    // FIXED: Search in-memory since getActiveStudents has no keyword parameter
    final allStudents = await db.getActiveStudents();
    
    if (kw.trim().isEmpty) {
      results = allStudents;
    } else {
      final keyword = kw.trim().toLowerCase();
      results = allStudents.where((student) {
        final surname = (student['surname'] ?? '').toString().toLowerCase();
        final firstName = (student['firstName'] ?? '').toString().toLowerCase();
        final admissionNo = (student['admissionNo'] ?? '').toString().toLowerCase();
        
        return surname.contains(keyword) || 
               firstName.contains(keyword) || 
               admissionNo.contains(keyword);
      }).toList();
    }
    
    setState(() => isLoading = false);
  }

  Future<void> _deactivate(int id, String name) async {
    _reasonCtrl.clear();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Deactivate Student"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Are you sure you want to deactivate $name?"),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: "Reason (optional)",
                hintText: "e.g., Transferred, Graduated, Withdrawn",
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Deactivate"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (ok == true) {
      final reason = _reasonCtrl.text.trim();
      final leftDate = DateTime.now().toIso8601String();
      final leftReason = reason.isEmpty ? "Not specified" : reason;
      
      // FIXED: Use positional parameters instead of named
      await db.deactivateStudent(
        id,
        leftDate,
        leftReason,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("$name has been deactivated"),
            backgroundColor: Colors.orange,
          ),
        );
      }
      
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Deactivate Students"),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: "Search student by name or admission no...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Deactivated students can be restored from the Inactive Students screen",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            "No active students found",
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final s = results[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                s['surname']?.toString().substring(0, 1).toUpperCase() ?? 'S',
                                style: TextStyle(
                                  color: Colors.blue.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              "${s['surname']} ${s['firstName']}",
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Admission No: ${s['admissionNo']}"),
                                Text("Class: ${s['className']} - ${s['armName']}"),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.person_off, color: Colors.red),
                              tooltip: "Deactivate",
                              onPressed: () => _deactivate(
                                s['id'],
                                "${s['surname']} ${s['firstName']}",
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}