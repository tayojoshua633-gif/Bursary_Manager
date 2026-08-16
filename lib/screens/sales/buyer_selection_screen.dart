// lib/screens/sales/buyer_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';
import 'sale_record_screen.dart';

class BuyerSelectionScreen extends StatefulWidget {
  const BuyerSelectionScreen({super.key});

  @override
  State<BuyerSelectionScreen> createState() => _BuyerSelectionScreenState();
}

class _BuyerSelectionScreenState extends State<BuyerSelectionScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _otherBuyerNameCtrl = TextEditingController();
  final TextEditingController _otherBuyerContactCtrl = TextEditingController();

  String _buyerType = 'Student'; // 'Student' or 'Other'
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _classes = [];
  int? _selectedClassId;
  bool _loading = true;
  Set<String> _siblingPhones = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _otherBuyerNameCtrl.dispose();
    _otherBuyerContactCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final students = await _db.getActiveStudents();
      final classes = await _db.getClasses();

      setState(() {
        _allStudents = students;
        _students = students;
        _classes = classes;
        _siblingPhones = computeSiblingPhones(students);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e')),
      );
    }
  }

  void _applyFilters() {
    final keyword = _searchCtrl.text.trim().toLowerCase();

    setState(() {
      List<Map<String, dynamic>> filtered = _allStudents;

      // Apply class filter
      if (_selectedClassId != null) {
        filtered = filtered
            .where((s) => s['classId'] == _selectedClassId)
            .toList();
      }

      // Apply search keyword
      if (keyword.isNotEmpty) {
        filtered = filtered.where((student) {
          final surname = (student['surname'] ?? '').toString().toLowerCase();
          final firstName = (student['firstName'] ?? '').toString().toLowerCase();
          final admissionNo = (student['admissionNo'] ?? '').toString().toLowerCase();
          return surname.contains(keyword) ||
              firstName.contains(keyword) ||
              admissionNo.contains(keyword);
        }).toList();
      }

      _students = filtered;
    });
  }

  Future<void> _selectStudent(Map<String, dynamic> student) async {
    // Calculate outstanding balance for this student
    final allSales = await _db.getAllSales();
    double outstandingBalance = 0.0;

    for (final sale in allSales) {
      if (sale['studentId'] == student['id']) {
        final balance = (sale['outstandingBalance'] as num?)?.toDouble() ?? 0.0;
        outstandingBalance += balance;
      }
    }

    final buyerInfo = {
      'buyerType': 'Student',
      'buyerName': '${student['surname']} ${student['firstName']}',
      'studentId': student['id'],
      'className': student['className'],
      'armName': student['armName'],
      'existingOutstanding': outstandingBalance,
    };

    if (!mounted) return;

    // Get current user for sidebar
    final prefs = await SharedPreferences.getInstance();
    final currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };

    // Check if we should show sidebar
    if (!mounted) return;
    final screenSize = MediaQuery.of(context).size;
    final showSidebar = screenSize.shortestSide >= 700;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: currentUser,
                currentPageId: 'stock_sales/record_sale',
                child: SaleRecordScreen(buyerInfo: buyerInfo),
              )
            : SaleRecordScreen(buyerInfo: buyerInfo),
      ),
    );
  }

  Future<void> _continueWithOtherBuyer() async {
    if (_otherBuyerNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter buyer name')),
      );
      return;
    }

    final buyerName = _otherBuyerNameCtrl.text.trim();

    // Calculate outstanding balance for this buyer
    final allSales = await _db.getAllSales();
    double outstandingBalance = 0.0;

    for (final sale in allSales) {
      if (sale['buyerName'] == buyerName && sale['buyerType'] == 'Other') {
        final balance = (sale['outstandingBalance'] as num?)?.toDouble() ?? 0.0;
        outstandingBalance += balance;
      }
    }

    final buyerInfo = {
      'buyerType': 'Other',
      'buyerName': buyerName,
      'studentId': null,
      'className': null,
      'armName': null,
      'contact': _otherBuyerContactCtrl.text.trim(),
      'existingOutstanding': outstandingBalance,
    };

    if (!mounted) return;

    // Get current user for sidebar
    final prefs = await SharedPreferences.getInstance();
    final currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };

    // Check if we should show sidebar
    if (!mounted) return;
    final screenSize = MediaQuery.of(context).size;
    final showSidebar = screenSize.shortestSide >= 700;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: currentUser,
                currentPageId: 'stock_sales/record_sale',
                child: SaleRecordScreen(buyerInfo: buyerInfo),
              )
            : SaleRecordScreen(buyerInfo: buyerInfo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Buyer'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Buyer Type Selector
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.teal.shade50,
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'Student',
                        label: Text('Student'),
                        icon: Icon(Icons.school),
                      ),
                      ButtonSegment(
                        value: 'Other',
                        label: Text('Other Buyer'),
                        icon: Icon(Icons.person),
                      ),
                    ],
                    selected: {_buyerType},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() {
                        _buyerType = newSelection.first;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Content based on buyer type
          Expanded(
            child: _buyerType == 'Student'
                ? _buildStudentSelection()
                : _buildOtherBuyerForm(),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSelection() {
    return Column(
      children: [
        // Search and filters
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Search bar
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: 'Search students',
                  hintText: 'Name or admission number',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _applyFilters();
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                onChanged: (_) => _applyFilters(),
              ),

              const SizedBox(height: 12),

              // Class filter
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: _selectedClassId,
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
                      setState(() => _selectedClassId = value);
                      _applyFilters();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Students count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                '${_students.length} students',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Students list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _students.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            _searchCtrl.text.isEmpty
                                ? 'No active students found'
                                : 'No students match your search',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _students.length,
                      itemBuilder: (context, index) {
                        final student = _students[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.teal.shade100,
                              child: Text(
                                student['surname'][0].toUpperCase(),
                                style: TextStyle(
                                  color: Colors.teal.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    '${student['surname']} ${student['firstName']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                SiblingMark(
                                  show: isSiblingPhone(student['parentPhone'] as String?, _siblingPhones),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${student['className']} ${student['armName']} • ${student['admissionNo']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () => _selectStudent(student),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildOtherBuyerForm() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter Buyer Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),

          const SizedBox(height: 20),

          // Buyer Name
          TextField(
            controller: _otherBuyerNameCtrl,
            decoration: InputDecoration(
              labelText: 'Buyer Name *',
              hintText: 'Enter buyer name',
              prefixIcon: const Icon(Icons.person),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            textCapitalization: TextCapitalization.words,
          ),

          const SizedBox(height: 16),

          // Contact (Optional)
          TextField(
            controller: _otherBuyerContactCtrl,
            decoration: InputDecoration(
              labelText: 'Contact (Optional)',
              hintText: 'Phone number or email',
              prefixIcon: const Icon(Icons.contact_phone),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            keyboardType: TextInputType.phone,
          ),

          const SizedBox(height: 24),

          // Continue Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _continueWithOtherBuyer,
              icon: const Icon(Icons.arrow_forward),
              label: const Text(
                'Continue to Sale',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
