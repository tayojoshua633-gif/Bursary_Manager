// lib/screens/parents/parent_details_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/parent.dart';
import '../../models/student.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/thermal_printer_manager.dart';
import '../students/student_details_screen.dart';
import '../settings/thermal_printer_screen.dart';
import '../../utils/usb_printer_manager.dart';
import '../settings/usb_printer_screen.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'parent_form_screen.dart';

class ParentDetailsScreen extends StatefulWidget {
  final Parent parent;

  const ParentDetailsScreen({super.key, required this.parent});

  @override
  State<ParentDetailsScreen> createState() => _ParentDetailsScreenState();
}

class _ParentDetailsScreenState extends State<ParentDetailsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  late Parent _parent;
  Map<String, dynamic> _currentUser = {};
  List<Map<String, dynamic>> _children = [];
  bool _loading = true;

  // Term and session for financial calculations
  String _activeTerm = "";
  String _activeSession = "";

  // Summary totals for all children
  double _totalBills = 0;
  double _totalPaid = 0;
  double _totalOutstanding = 0;

  // School profile for printing
  Map<String, dynamic>? _school;

  @override
  void initState() {
    super.initState();
    _parent = widget.parent;
    _loadParentData();
  }

  Future<void> _loadParentData() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    _currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };

    try {
      // Reload parent data in case it was edited
      final raw = await _db.getAllParents();
      final parentData = raw.firstWhere(
        (p) => p['id'] == _parent.id,
        orElse: () => _parent.toMap(),
      );
      _parent = Parent.fromMap(parentData);

      // Load school profile for printing
      _school = await _db.getSchoolProfile();

      // Load children (students with matching parent name or phone)
      await _loadChildren();

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadChildren() async {
    try {
      final db = await _db.database;

      // Get current term and session
      _activeTerm = await _db.getActiveTerm();
      final sessionData = await _db.getActiveSession();
      _activeSession = sessionData?['sessionName'] ?? "";

      // Find students linked to this parent by matching phone number
      // Check both phoneNumber and phoneNumber2 from parent record
      final children = await db.rawQuery('''
        SELECT
          s.id,
          s.surname,
          s.firstName,
          s.otherName,
          s.admissionNo,
          s.gender,
          s.photoPath,
          c.name as className,
          a.name as armName
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        WHERE s.isActive = 1
          AND s.parentPhone IS NOT NULL
          AND s.parentPhone != ''
          AND (s.parentPhone = ? OR s.parentPhone = ?)
        ORDER BY s.surname, s.firstName
      ''', [_parent.phoneNumber, _parent.phoneNumber2 ?? '']);

      // Reset totals
      _totalBills = 0;
      _totalPaid = 0;
      _totalOutstanding = 0;

      // Load financial data for each child
      final List<Map<String, dynamic>> childrenWithFinancials = [];

      for (final child in children) {
        final studentId = child['id'] as int;

        // Calculate previous balance fresh (same as Bill Generate Screen)
        final previousBalance = await _db.computeOutstandingBeforeTerm(
          studentId,
          term: _activeTerm,
          session: _activeSession,
        );

        // Get current term bill
        final bill = await _db.getBillForStudent(studentId, _activeTerm, _activeSession);

        double currentTermBill = 0;
        double grandTotal = previousBalance;
        List<Map<String, dynamic>> billItems = [];

        if (bill != null) {
          final storedTotal = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final storedPrevBalance = (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;
          currentTermBill = storedTotal - storedPrevBalance;
          grandTotal = previousBalance + currentTermBill;

          // Load bill items for this child
          final items = await db.rawQuery('''
            SELECT sfb.id, sfb.billId, sfb.feeItemId, sfb.amount,
                   COALESCE(
                     NULLIF(TRIM(sfb.label), ''),
                     fi.name,
                     'Fee Item'
                   ) as feeName
            FROM student_fee_breakdown sfb
            LEFT JOIN fee_items fi ON sfb.feeItemId = fi.id
            WHERE sfb.billId = ?
            ORDER BY sfb.id ASC
          ''', [bill['id']]);
          billItems = items.map((item) => Map<String, dynamic>.from(item)).toList();
        }

        // Get total payments for current term
        final payments = await db.rawQuery('''
          SELECT COALESCE(SUM(amount), 0) as totalPaid
          FROM payments
          WHERE studentId = ? AND term = ? AND session = ?
        ''', [studentId, _activeTerm, _activeSession]);

        final totalPaid = (payments.first['totalPaid'] as num?)?.toDouble() ?? 0.0;
        final outstanding = grandTotal - totalPaid;

        // Add financial data to child map
        final childWithFinancials = Map<String, dynamic>.from(child);
        childWithFinancials['previousBalance'] = previousBalance;
        childWithFinancials['currentTermBill'] = currentTermBill;
        childWithFinancials['grandTotal'] = grandTotal;
        childWithFinancials['totalPaid'] = totalPaid;
        childWithFinancials['outstanding'] = outstanding;
        childWithFinancials['billItems'] = billItems;

        childrenWithFinancials.add(childWithFinancials);

        // Add to totals
        _totalBills += grandTotal;
        _totalPaid += totalPaid;
        _totalOutstanding += outstanding;
      }

      if (mounted) {
        setState(() {
          _children = childrenWithFinancials;
        });
      }
    } catch (e) {
      debugPrint('Error loading children: $e');
    }
  }

  Future<void> _navigateToEdit() async {
    final result = await NavigationHelper.pushWithSidebar(
      context,
      page: ParentFormScreen(parent: _parent),
      currentUser: _currentUser,
      pageId: 'parents',
    );

    if (result == true) {
      _loadParentData();
    }
  }

  List<Map<String, dynamic>> _getBankAccounts() {
    if (_school == null) return [];
    final accounts = <Map<String, dynamic>>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = _school!['bankName$i']?.toString() ?? '';
      final accNum = _school!['accountNumber$i']?.toString() ?? '';
      final accName = _school!['accountName$i']?.toString() ?? '';
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add({'bankName': bankName, 'accountNumber': accNum, 'accountName': accName});
      }
    }
    return accounts;
  }

  List<pw.Widget> _buildBankDetailsPdf() {
    final bankAccounts = _getBankAccounts();
    if (bankAccounts.isEmpty) return [];
    return [
      pw.SizedBox(height: 15),
      pw.Text('Bank Account Details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 5),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo100),
        cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft},
        data: [
          ['Bank Name', 'Account Number', 'Account Name'],
          ...bankAccounts.map((a) => [
            a['bankName']?.toString() ?? '',
            a['accountNumber']?.toString() ?? '',
            a['accountName']?.toString() ?? '',
          ]),
        ],
      ),
    ];
  }

  // Show dialog to add a student as child
  Future<void> _showAddChildDialog() async {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> allStudents = [];
    List<Map<String, dynamic>> filteredStudents = [];
    bool isLoading = true;

    // Get all active students not already linked to this parent
    final db = await _db.database;
    final students = await db.rawQuery('''
      SELECT
        s.id,
        s.surname,
        s.firstName,
        s.otherName,
        s.admissionNo,
        s.gender,
        s.parentPhone,
        c.name as className,
        a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.isActive = 1
        AND (s.parentPhone IS NULL OR s.parentPhone = '' OR (s.parentPhone != ? AND s.parentPhone != ?))
      ORDER BY s.surname, s.firstName
    ''', [_parent.phoneNumber, _parent.phoneNumber2 ?? '']);

    allStudents = students.map((s) => Map<String, dynamic>.from(s)).toList();
    filteredStudents = List.from(allStudents);
    isLoading = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void filterStudents(String query) {
            if (query.isEmpty) {
              setDialogState(() => filteredStudents = List.from(allStudents));
            } else {
              final lowerQuery = query.toLowerCase();
              setDialogState(() {
                filteredStudents = allStudents.where((s) {
                  final fullName = '${s['surname']} ${s['firstName']} ${s['otherName'] ?? ''}'
                      .toLowerCase()
                      .trim();
                  final admissionNo = (s['admissionNo'] ?? '').toString().toLowerCase();
                  return fullName.contains(lowerQuery) || admissionNo.contains(lowerQuery);
                }).toList();
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.person_add, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Add Child'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    controller: searchController,
                    onChanged: filterStudents,
                    decoration: InputDecoration(
                      hintText: 'Search by name or admission number...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                filterStudents('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Info text
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Select a student to link as this parent\'s child',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Students list
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredStudents.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text(
                                      searchController.text.isNotEmpty
                                          ? 'No students found'
                                          : 'No available students',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredStudents.length,
                                itemBuilder: (context, index) {
                                  final student = filteredStudents[index];
                                  final fullName = '${student['surname']} ${student['firstName']} ${student['otherName'] ?? ''}'.trim();
                                  final className = student['className'] ?? 'N/A';
                                  final armName = student['armName'];
                                  final classDisplay = armName != null && armName.isNotEmpty
                                      ? '$className - $armName'
                                      : className;
                                  final gender = student['gender'] ?? 'Male';
                                  final admissionNo = student['admissionNo'] ?? '';

                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: gender == 'Male'
                                            ? Colors.blue.shade100
                                            : Colors.pink.shade100,
                                        child: Icon(
                                          gender == 'Male' ? Icons.boy : Icons.girl,
                                          color: gender == 'Male'
                                              ? Colors.blue.shade700
                                              : Colors.pink.shade700,
                                        ),
                                      ),
                                      title: Text(
                                        fullName,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(
                                        '$classDisplay${admissionNo.isNotEmpty ? ' • $admissionNo' : ''}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                      trailing: Icon(
                                        Icons.add_circle,
                                        color: Colors.green.shade600,
                                      ),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await _addStudentAsChild(student['id'] as int);
                                      },
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Add a student as child by updating their parent data
  Future<void> _addStudentAsChild(int studentId) async {
    try {
      final db = await _db.database;

      // Update student's parent data with this parent's info
      await db.rawUpdate('''
        UPDATE students SET
          parentPhone = ?,
          parentName = ?,
          parentEmail = ?,
          parentAddress = ?
        WHERE id = ?
      ''', [
        _parent.phoneNumber,
        _parent.parentName,
        _parent.emailAddress ?? '',
        _parent.homeAddress,
        studentId,
      ]);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Student added as child successfully'),
          backgroundColor: Colors.green.shade600,
        ),
      );

      // Reload data to show the new child
      _loadParentData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding child: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Remove a student from this parent's children
  Future<void> _removeChildFromParent(int studentId, String studentName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text('Remove Child'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "$studentName" from this parent\'s children list?\n\nThis will clear the parent data from the student\'s record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final db = await _db.database;

      // Clear parent data from student (use empty strings for NOT NULL fields)
      await db.rawUpdate('''
        UPDATE students SET
          parentPhone = '',
          parentName = '',
          parentEmail = '',
          parentAddress = ''
        WHERE id = ?
      ''', [studentId]);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Child removed from parent'),
          backgroundColor: Colors.orange.shade600,
        ),
      );

      // Reload data
      _loadParentData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error removing child: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Launch phone dialer
  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No phone app found to call $phoneNumber')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch dialer: $e')),
      );
    }
  }

  // Launch email composer
  Future<void> _sendEmail(String email) async {
    final uri = Uri.parse('mailto:$email');
    try {
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No email client found to send to $email')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch email client: $e')),
      );
    }
  }

  // Save parent contact to device
  Future<void> _saveContact() async {
    try {
      // Request permission to access contacts
      if (!await FlutterContacts.requestPermission(readonly: false)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied to access contacts'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Parse the parent name into parts
      final nameParts = _parent.parentName.trim().split(' ');
      String firstName = '';
      String lastName = '';
      String middleName = '';
      const String suffix = 'Parent'; // Suffix to identify as parent in contacts

      if (nameParts.length == 1) {
        firstName = nameParts[0];
      } else if (nameParts.length == 2) {
        firstName = nameParts[0];
        lastName = nameParts[1];
      } else if (nameParts.length >= 3) {
        firstName = nameParts[0];
        middleName = nameParts.sublist(1, nameParts.length - 1).join(' ');
        lastName = nameParts.last;
      }

      // Create the contact with "Parent" suffix for easy identification
      final newContact = Contact(
        name: Name(
          first: firstName,
          middle: middleName,
          last: lastName,
          suffix: suffix,
        ),
        phones: [
          Phone(_parent.phoneNumber, label: PhoneLabel.mobile),
          if (_parent.phoneNumber2 != null && _parent.phoneNumber2!.isNotEmpty)
            Phone(_parent.phoneNumber2!, label: PhoneLabel.work),
        ],
        emails: [
          if (_parent.emailAddress != null && _parent.emailAddress!.isNotEmpty)
            Email(_parent.emailAddress!, label: EmailLabel.home),
        ],
        addresses: [
          if (_parent.homeAddress.isNotEmpty)
            Address(_parent.homeAddress, label: AddressLabel.home),
          if (_parent.officeAddress != null && _parent.officeAddress!.isNotEmpty)
            Address(_parent.officeAddress!, label: AddressLabel.work),
        ],
        organizations: [
          if (_parent.occupation != null && _parent.occupation!.isNotEmpty)
            Organization(title: _parent.occupation!),
        ],
      );

      // Insert the contact
      await newContact.insert();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_parent.parentName} saved to contacts'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save contact: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Show print options dialog for children bills
  Future<void> _showChildrenBillPrintOptions() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.print, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Print Children Bills'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Print bills for ${_children.length} ${_children.length == 1 ? 'child' : 'children'}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Total Outstanding: ₦${NumberFormat('#,##0.00').format(_totalOutstanding)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _totalOutstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printChildrenBillsPDF();
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printChildrenBillsThermal();
            },
            icon: const Icon(Icons.print),
            label: const Text('Thermal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printChildrenBillsViaUsb();
            },
            icon: const Icon(Icons.usb),
            label: const Text('USB'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Print children bills as PDF
  Future<void> _printChildrenBillsPDF() async {
    if (_children.isEmpty) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final pdf = pw.Document();
      final formatter = NumberFormat('#,##0.00');

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return [
              // School Name
              pw.Center(
                child: pw.Text(
                  _school?['name']?.toString().toUpperCase() ?? 'SCHOOL NAME',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo700),
                ),
              ),
              pw.SizedBox(height: 5),
              if (_school?['address'] != null)
                pw.Center(
                  child: pw.Text(
                    _school!['address'].toString(),
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                ),
              pw.SizedBox(height: 15),

              // Title
              pw.Center(
                child: pw.Text(
                  'CHILDREN BILL SUMMARY',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'Term: $_activeTerm | Session: $_activeSession',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                ),
              ),
              pw.SizedBox(height: 20),

              // Parent Info
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.indigo300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Parent: ${_parent.parentName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Phone: ${_parent.phoneNumber}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Individual Child Bills with Breakdown
              ..._children.asMap().entries.expand((entry) {
                final index = entry.key;
                final child = entry.value;
                final fullName = '${child['surname']} ${child['firstName']}'.trim();
                final className = child['className'] ?? 'N/A';
                final armName = child['armName'];
                final classDisplay = armName != null && armName.isNotEmpty ? '$className - $armName' : className;
                final grandTotal = (child['grandTotal'] as num?)?.toDouble() ?? 0.0;
                final paid = (child['totalPaid'] as num?)?.toDouble() ?? 0.0;
                final outstanding = (child['outstanding'] as num?)?.toDouble() ?? 0.0;
                final previousBalance = (child['previousBalance'] as num?)?.toDouble() ?? 0.0;
                final billItems = child['billItems'] as List<Map<String, dynamic>>? ?? [];

                return [
                  // Child header
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.orange100,
                      borderRadius: const pw.BorderRadius.only(
                        topLeft: pw.Radius.circular(5),
                        topRight: pw.Radius.circular(5),
                      ),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Container(
                          width: 24,
                          height: 24,
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.orange700,
                            shape: pw.BoxShape.circle,
                          ),
                          child: pw.Center(
                            child: pw.Text(
                              '${index + 1}',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                fullName,
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                              ),
                              pw.Text(
                                classDisplay,
                                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bill breakdown table
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.orange200),
                      borderRadius: const pw.BorderRadius.only(
                        bottomLeft: pw.Radius.circular(5),
                        bottomRight: pw.Radius.circular(5),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Bill items
                        if (billItems.isNotEmpty) ...[
                          pw.Text(
                            'Bill Breakdown:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey700),
                          ),
                          pw.SizedBox(height: 5),
                          ...billItems.map((item) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 2),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Expanded(
                                  child: pw.Text(
                                    item['feeName']?.toString() ?? 'Fee Item',
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ),
                                pw.Text(
                                  'N${formatter.format((item['amount'] as num?)?.toDouble() ?? 0)}',
                                  style: const pw.TextStyle(fontSize: 9),
                                ),
                              ],
                            ),
                          )),
                          pw.Divider(color: PdfColors.grey300),
                        ],

                        // Previous balance if any
                        if (previousBalance > 0)
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 2),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('Previous Balance:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.orange700)),
                                pw.Text('N${formatter.format(previousBalance)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.orange700)),
                              ],
                            ),
                          ),

                        // Summary row
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 5),
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey100,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                            children: [
                              pw.Column(
                                children: [
                                  pw.Text('Total Bill', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                                  pw.Text('N${formatter.format(grandTotal)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.purple700)),
                                ],
                              ),
                              pw.Column(
                                children: [
                                  pw.Text('Paid', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                                  pw.Text('N${formatter.format(paid)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                                ],
                              ),
                              pw.Column(
                                children: [
                                  pw.Text('Outstanding', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                                  pw.Text('N${formatter.format(outstanding)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: outstanding > 0 ? PdfColors.red700 : PdfColors.green700)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 15),
                ];
              }),

              pw.SizedBox(height: 10),

              // Summary
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.indigo400, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total Bills:', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N${formatter.format(_totalBills)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total Paid:', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N${formatter.format(_totalPaid)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.green)),
                      ],
                    ),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('TOTAL OUTSTANDING:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                        pw.Text('N${formatter.format(_totalOutstanding)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: _totalOutstanding > 0 ? PdfColors.red : PdfColors.green)),
                      ],
                    ),
                  ],
                ),
              ),

              // Bank Account Details
              ..._buildBankDetailsPdf(),

              pw.SizedBox(height: 30),
              pw.Divider(),
              pw.Text(
                'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ];
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${dir.path}/children_bills_${_parent.parentName.replaceAll(' ', '_')}_$dateStr.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Children Bills - ${_parent.parentName}',
        text: 'Bills for ${_children.length} children. Total Outstanding: N${NumberFormat('#,##0.00').format(_totalOutstanding)}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Children bills PDF generated!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  // Print children bills via thermal printer
  Future<void> _printChildrenBillsThermal() async {
    if (_children.isEmpty) return;

    if (!ThermalPrinterManager.isConnected) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to a thermal printer first'),
          duration: Duration(seconds: 2),
        ),
      );

      await NavigationHelper.pushWithSidebar(
        context,
        page: const ThermalPrinterScreen(),
        currentUser: _currentUser,
        pageId: 'parents',
      );

      if (!ThermalPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Printer not connected. Printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final schoolName = _school?['name'] ?? 'School Name';
      final schoolAddress = _school?['address'] ?? '';

      // Build children bill items for thermal print
      final List<Map<String, dynamic>> billItems = [];
      for (final child in _children) {
        final fullName = '${child['surname']} ${child['firstName']}'.trim();
        final outstanding = (child['outstanding'] as num?)?.toDouble() ?? 0.0;
        billItems.add({
          'name': fullName,
          'amount': outstanding,
        });
      }

      await ThermalPrinterManager.printBill(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        studentName: _parent.parentName,
        studentClass: '${_children.length} Children',
        term: '$_activeTerm $_activeSession',
        feeItems: billItems,
        total: _totalOutstanding,
        billDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Children bills printed successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing: $e')),
      );
    }
  }

  Future<void> _printChildrenBillsViaUsb() async {
    if (_children.isEmpty) return;

    if (!UsbPrinterManager.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect a USB printer first'),
          duration: Duration(seconds: 2),
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UsbPrinterScreen()),
      );
      if (!UsbPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No USB printer connected. Printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final schoolName = _school?['name'] ?? 'School Name';
      final schoolAddress = _school?['address'] ?? '';

      final List<Map<String, dynamic>> billItems = [];
      for (final child in _children) {
        final fullName = '${child['surname']} ${child['firstName']}'.trim();
        final outstanding = (child['outstanding'] as num?)?.toDouble() ?? 0.0;
        billItems.add({'name': fullName, 'amount': outstanding});
      }

      final paperSize = await UsbPrinterManager.getPaperSize();

      await UsbPrinterManager.printBill(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        studentName: _parent.parentName,
        studentClass: '${_children.length} Children',
        term: '$_activeTerm $_activeSession',
        feeItems: billItems,
        total: _totalOutstanding,
        billDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        paperSize: paperSize == 'mm58' ? PaperSize.mm58 : PaperSize.mm80,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Children bills printed via USB!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB print error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Details'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade600, Colors.indigo.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _navigateToEdit,
            tooltip: 'Edit Parent',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Parent Avatar
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.indigo.shade50, Colors.purple.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.indigo.shade100,
                          child: Icon(
                            Icons.person,
                            size: 50,
                            color: Colors.indigo.shade700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _parent.parentName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_parent.occupation != null && _parent.occupation!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _parent.occupation!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Contact Information Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.contact_phone, color: Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Contact Information',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),

                          // Phone Number 1
                          _buildContactRow(
                            icon: Icons.phone,
                            label: 'Phone',
                            value: _parent.phoneNumber,
                            onTap: () => _makePhoneCall(_parent.phoneNumber),
                            isClickable: true,
                          ),

                          // Phone Number 2
                          if (_parent.phoneNumber2 != null && _parent.phoneNumber2!.isNotEmpty)
                            _buildContactRow(
                              icon: Icons.phone_android,
                              label: 'Phone 2',
                              value: _parent.phoneNumber2!,
                              onTap: () => _makePhoneCall(_parent.phoneNumber2!),
                              isClickable: true,
                            ),

                          // Email
                          if (_parent.emailAddress != null && _parent.emailAddress!.isNotEmpty)
                            _buildContactRow(
                              icon: Icons.email,
                              label: 'Email',
                              value: _parent.emailAddress!,
                              onTap: () => _sendEmail(_parent.emailAddress!),
                              isClickable: true,
                            ),

                          const SizedBox(height: 12),

                          // Save Contact Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _saveContact,
                              icon: const Icon(Icons.contact_page),
                              label: const Text('Save to Contacts'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.indigo,
                                side: BorderSide(color: Colors.indigo.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Address Information Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Address Information',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),

                          // Home Address
                          _buildInfoRow(
                            icon: Icons.home,
                            label: 'Home Address',
                            value: _parent.homeAddress,
                          ),

                          // Office Address
                          if (_parent.officeAddress != null && _parent.officeAddress!.isNotEmpty)
                            _buildInfoRow(
                              icon: Icons.business,
                              label: 'Office Address',
                              value: _parent.officeAddress!,
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Add Child Search Bar
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: _showAddChildDialog,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search, color: Colors.orange.shade600),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Search and add a student as child...',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_add, size: 16, color: Colors.orange.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Add',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Children Card
                  Card(
                    elevation: 2,
                    color: Colors.orange.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.school, color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Children (${_children.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              // Print button
                              if (_children.isNotEmpty)
                                IconButton(
                                  onPressed: _showChildrenBillPrintOptions,
                                  icon: Icon(Icons.print, color: Colors.orange.shade700),
                                  tooltip: 'Print Children Bills',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              const SizedBox(width: 8),
                              // Term/Session indicator
                              if (_activeTerm.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _activeTerm,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.indigo.shade700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Divider(),

                          if (_children.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.child_care, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No students linked to this parent',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Use the search bar above to add children',
                                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else ...[
                            ..._children.map((child) => _buildChildTile(child)),

                            // Show summary only if more than one child
                            if (_children.length > 1)
                              _buildChildrenSummary(),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Edit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _navigateToEdit,
                      icon: const Icon(Icons.edit),
                      label: const Text(
                        'Edit Parent Information',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    bool isClickable = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                isClickable
                    ? InkWell(
                        onTap: onTap,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      )
                    : Text(
                        value,
                        style: const TextStyle(fontSize: 15),
                      ),
              ],
            ),
          ),
          if (isClickable)
            IconButton(
              icon: Icon(
                icon == Icons.email ? Icons.send : Icons.call,
                color: Colors.indigo,
                size: 20,
              ),
              onPressed: onTap,
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChildTile(Map<String, dynamic> child) {
    final fullName = '${child['surname']} ${child['firstName']} ${child['otherName'] ?? ''}'.trim();
    final className = child['className'] ?? 'N/A';
    final armName = child['armName'];
    final classDisplay = armName != null && armName.isNotEmpty ? '$className - $armName' : className;
    final gender = child['gender'] ?? 'Male';
    final studentId = child['id'] as int;

    // Financial data
    final grandTotal = (child['grandTotal'] as num?)?.toDouble() ?? 0.0;
    final totalPaid = (child['totalPaid'] as num?)?.toDouble() ?? 0.0;
    final outstanding = (child['outstanding'] as num?)?.toDouble() ?? 0.0;

    final formatter = NumberFormat('#,##0.00');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Child info row
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: gender == 'Male' ? Colors.blue.shade100 : Colors.pink.shade100,
                child: Icon(
                  gender == 'Male' ? Icons.boy : Icons.girl,
                  size: 22,
                  color: gender == 'Male' ? Colors.blue.shade700 : Colors.pink.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final db = await _db.database;
                    final result = await db.rawQuery('''
                      SELECT s.*, c.name as className, a.name as armName
                      FROM students s
                      LEFT JOIN classes c ON s.classId = c.id
                      LEFT JOIN arms a ON s.armId = a.id
                      WHERE s.id = ?
                    ''', [studentId]);

                    if (result.isNotEmpty && mounted) {
                      final student = Student.fromMap(result.first);
                      await NavigationHelper.pushWithSidebar(
                        context,
                        page: StudentDetailsScreen(student: student),
                        currentUser: _currentUser,
                        pageId: 'parents',
                      );
                      // Reload data when returning
                      _loadParentData();
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        classDisplay,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Remove button
              IconButton(
                onPressed: () => _removeChildFromParent(studentId, fullName),
                icon: Icon(Icons.person_remove, size: 20, color: Colors.red.shade400),
                tooltip: 'Remove from children',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Financial details
          Row(
            children: [
              // Bills
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Bills',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₦${formatter.format(grandTotal)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              // Paid
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Paid',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₦${formatter.format(totalPaid)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              // Outstanding
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Outstanding',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₦${formatter.format(outstanding)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: outstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Summary widget for multiple children
  Widget _buildChildrenSummary() {
    final formatter = NumberFormat('#,##0.00');

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade50, Colors.purple.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade200, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.summarize, size: 18, color: Colors.indigo.shade700),
              const SizedBox(width: 8),
              Text(
                'Summary (${_children.length} Children)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Total Bills
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Total Bills',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₦${formatter.format(_totalBills)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              // Total Paid
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Total Paid',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₦${formatter.format(_totalPaid)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              // Total Outstanding
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Total Outstanding',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₦${formatter.format(_totalOutstanding)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _totalOutstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
