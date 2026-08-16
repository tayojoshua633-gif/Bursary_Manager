import 'package:flutter/material.dart';
import 'package:bursary_manager/data/database_helper_wrapper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';

class DeactivateStudentScreen extends StatefulWidget {
  const DeactivateStudentScreen({super.key});

  @override
  State<DeactivateStudentScreen> createState() =>
      _DeactivateStudentScreenState();
}

class _DeactivateStudentScreenState extends State<DeactivateStudentScreen> {
  final db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _reasonCtrl = TextEditingController();

  List<Map<String, dynamic>> results = [];
  List<Map<String, dynamic>> allStudents = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  bool isLoading = false;
  int? _selectedClassFilter;
  int? _selectedArmFilter;
  Set<String> _siblingPhones = {};

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

    // Load classes and arms
    _classes = await db.getClasses();
    _arms = await db.getArms();

    // Load all active students
    allStudents = await db.getActiveStudents();
    _siblingPhones = computeSiblingPhones(allStudents);

    setState(() => isLoading = false);

    // Apply filters
    _applyFilters();
  }

  void _applyFilters() {
    final keyword = _searchCtrl.text.trim();

    setState(() {
      // Start with all students
      List<Map<String, dynamic>> filtered = allStudents;

      // Apply class filter
      if (_selectedClassFilter != null) {
        filtered = filtered.where((s) => s['classId'] == _selectedClassFilter).toList();
      }

      // Apply arm filter
      if (_selectedArmFilter != null) {
        filtered = filtered.where((s) => s['armId'] == _selectedArmFilter).toList();
      }

      // Apply search keyword
      if (keyword.isNotEmpty) {
        final kw = keyword.toLowerCase();
        filtered = filtered.where((student) {
          final surname = (student['surname'] ?? '').toString().toLowerCase();
          final firstName = (student['firstName'] ?? '').toString().toLowerCase();
          final admissionNo = (student['admissionNo'] ?? '').toString().toLowerCase();

          return surname.contains(kw) ||
                 firstName.contains(kw) ||
                 admissionNo.contains(kw);
        }).toList();
      }

      results = filtered;
    });
  }

  Future<void> _search(String kw) async {
    _applyFilters();
  }

  // Get filtered arms based on selected class
  List<Map<String, dynamic>> _getFilteredArms() {
    if (_selectedClassFilter == null) {
      return _arms;
    }
    return _arms.where((arm) => arm['classId'] == _selectedClassFilter).toList();
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
          // CLASS AND ARM FILTER DROPDOWNS
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              children: [
                // CLASS FILTER
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        value: _selectedClassFilter,
                        hint: const Text('Filter by Class'),
                        icon: const Icon(Icons.filter_list, size: 20),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'All Classes',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          ..._classes.map((c) => DropdownMenuItem<int?>(
                                value: c['id'],
                                child: Text(c['name']),
                              )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedClassFilter = value;
                            // Reset arm filter if needed
                            if (_selectedArmFilter != null) {
                              final filteredArms = value == null
                                  ? _arms
                                  : _arms.where((arm) => arm['classId'] == value).toList();
                              final armExists = filteredArms.any((arm) => arm['id'] == _selectedArmFilter);
                              if (!armExists) {
                                _selectedArmFilter = null;
                              }
                            }
                          });
                          _applyFilters();
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // ARM FILTER
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        value: _selectedArmFilter,
                        hint: const Text('Filter by Arm'),
                        icon: const Icon(Icons.filter_list, size: 20),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'All Arms',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          ..._getFilteredArms().map((a) => DropdownMenuItem<int?>(
                                value: a['id'],
                                child: Text(a['name']),
                              )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedArmFilter = value;
                          });
                          _applyFilters();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
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
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    "${s['surname']} ${s['firstName']}",
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                SiblingMark(
                                  show: isSiblingPhone(s['parentPhone'] as String?, _siblingPhones),
                                ),
                              ],
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