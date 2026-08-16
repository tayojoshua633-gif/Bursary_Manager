import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/new_intake_bills_pdf_generator.dart';
import '../../utils/thermal_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../../utils/usb_printer_manager.dart';
import '../../utils/sms_service.dart';
import '../settings/usb_printer_screen.dart';

class ViewNewIntakeBillsScreen extends StatefulWidget {
  const ViewNewIntakeBillsScreen({super.key});

  @override
  State<ViewNewIntakeBillsScreen> createState() => _ViewNewIntakeBillsScreenState();
}

class _ViewNewIntakeBillsScreenState extends State<ViewNewIntakeBillsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final GlobalKey _billKey = GlobalKey();

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  List<Map<String, dynamic>> _regularFees = [];
  List<Map<String, dynamic>> _specialFees = [];
  List<Map<String, dynamic>> _specialFeeCategories = []; // Categories (have children)
  List<Map<String, dynamic>> _standaloneItems = []; // Standalone items (no parent, no children)
  Map<int, List<Map<String, dynamic>>> _specialFeeChildrenMap = {}; // Children by parent ID

  String? _activeTerm;
  String? _activeSession;
  int? _selectedClassId;
  int? _selectedArmId;
  String? _selectedClassName;
  String? _selectedArmName;

  double _regularTotal = 0;
  double _specialTotal = 0;

  bool _loading = true;
  bool _loadingArms = false;
  bool _exporting = false;

  Map<String, dynamic>? _schoolProfile;

  File? get _schoolLogoFile {
    final path = _schoolProfile?['logoPath']?.toString();
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _activeTerm = await _db.getActiveTerm();
    _activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";
    _classes = await _db.getClasses();
    _schoolProfile = await _db.getSchoolProfile();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onClassChanged(int? classId) async {
    if (classId == null) return;

    final selectedClass = _classes.firstWhere(
      (c) => c['id'] == classId,
      orElse: () => {'name': 'Unknown'},
    );

    setState(() {
      _selectedClassId = classId;
      _selectedClassName = selectedClass['name'] as String?;
      _selectedArmId = null;
      _selectedArmName = null;
      _arms = [];
      _regularFees = [];
      _specialFees = [];
      _specialFeeCategories = [];
      _standaloneItems = [];
      _specialFeeChildrenMap = {};
      _regularTotal = 0;
      _specialTotal = 0;
      _loadingArms = true;
    });

    try {
      final database = await _db.database;
      final armsData = await database.query(
        'arms',
        where: 'classId = ?',
        whereArgs: [classId],
        orderBy: 'name',
      );

      setState(() {
        _arms = armsData;
        _loadingArms = false;
      });

      if (_arms.isEmpty || _arms.length == 1) {
        if (_arms.length == 1) {
          _selectedArmId = _arms.first['id'] as int;
          _selectedArmName = _arms.first['name'] as String?;
        }
        await _loadBillsForSelection();
      }
    } catch (e) {
      debugPrint('Error loading arms: $e');
      setState(() {
        _arms = [];
        _loadingArms = false;
      });
    }
  }

  Future<void> _onArmChanged(int? armId) async {
    if (armId == null) return;

    final selectedArm = _arms.firstWhere(
      (a) => a['id'] == armId,
      orElse: () => {'name': 'Unknown'},
    );

    setState(() {
      _selectedArmId = armId;
      _selectedArmName = selectedArm['name'] as String?;
    });
    await _loadBillsForSelection();
  }

  Future<void> _loadBillsForSelection() async {
    if (_selectedClassId == null) return;

    setState(() => _loading = true);

    final billData = await _db.getNewIntakeBillForClass(
      _selectedClassId!,
      _activeTerm ?? "",
      _activeSession ?? "",
      armId: _selectedArmId,
    );

    // Load categories (items with isCategory = 1)
    _specialFeeCategories = await _db.getSpecialFeeItemCategories(
      term: _activeTerm,
      session: _activeSession,
    );

    // Load standalone items (items with isCategory = 0)
    _standaloneItems = await _db.getSpecialFeeItemStandalone(
      term: _activeTerm,
      session: _activeSession,
    );

    // Load children for each category
    _specialFeeChildrenMap.clear();
    for (var category in _specialFeeCategories) {
      final categoryId = category['id'] as int;
      final children = await _db.getSpecialFeeItemChildren(
        categoryId,
        term: _activeTerm,
        session: _activeSession,
      );
      _specialFeeChildrenMap[categoryId] = children;
    }

    setState(() {
      _regularFees = List<Map<String, dynamic>>.from(billData['regularFees'] ?? []);
      _specialFees = List<Map<String, dynamic>>.from(billData['specialFees'] ?? []);
      _regularTotal = (billData['regularTotal'] as num?)?.toDouble() ?? 0;
      _specialTotal = (billData['specialTotal'] as num?)?.toDouble() ?? 0;
      _loading = false;
    });
  }

  /// Get special fees organized by category for display
  List<Map<String, dynamic>> _getSpecialFeesGroupedByCategory() {
    List<Map<String, dynamic>> groupedFees = [];

    for (var category in _specialFeeCategories) {
      final categoryId = category['id'] as int;
      final categoryName = category['name'] ?? 'Unknown Category';
      final children = _specialFeeChildrenMap[categoryId] ?? [];

      // Get assigned amounts for children in this class
      List<Map<String, dynamic>> categoryItems = [];
      double categoryTotal = 0;

      for (var child in children) {
        final childId = child['id'] as int;

        // Find the fee assignment for this child item
        final feeAssignment = _specialFees.firstWhere(
          (f) => f['specialFeeItemId'] == childId,
          orElse: () => {},
        );

        if (feeAssignment.isNotEmpty) {
          final amount = (feeAssignment['amount'] as num?)?.toDouble() ?? 0;
          if (amount > 0) {
            categoryItems.add({
              'name': child['name'],
              'amount': amount,
            });
            categoryTotal += amount;
          }
        }
      }

      // Only add category if it has items with amounts
      if (categoryItems.isNotEmpty) {
        groupedFees.add({
          'categoryName': categoryName,
          'items': categoryItems,
          'categoryTotal': categoryTotal,
        });
      }
    }

    return groupedFees;
  }

  /// Get standalone items with their amounts for display
  List<Map<String, dynamic>> _getStandaloneItemsWithAmounts() {
    List<Map<String, dynamic>> items = [];

    for (var item in _standaloneItems) {
      final itemId = item['id'] as int;

      // Find the fee assignment for this standalone item
      final feeAssignment = _specialFees.firstWhere(
        (f) => f['specialFeeItemId'] == itemId,
        orElse: () => {},
      );

      if (feeAssignment.isNotEmpty) {
        final amount = (feeAssignment['amount'] as num?)?.toDouble() ?? 0;
        if (amount > 0) {
          items.add({
            'name': item['name'],
            'amount': amount,
          });
        }
      }
    }

    return items;
  }

  List<Map<String, dynamic>> _getBankAccounts() {
    if (_schoolProfile == null) return [];
    final accounts = <Map<String, dynamic>>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = _schoolProfile!['bankName$i']?.toString() ?? '';
      final accNum = _schoolProfile!['accountNumber$i']?.toString() ?? '';
      final accName = _schoolProfile!['accountName$i']?.toString() ?? '';
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add({'bankName': bankName, 'accountNumber': accNum, 'accountName': accName});
      }
    }
    return accounts;
  }

  String _formatCurrency(num amount) {
    final formatter = NumberFormat('#,##0');
    return formatter.format(amount);
  }

  Widget _bankDetailRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  String _classLabel() =>
      '${_selectedClassName ?? ''}${_selectedArmName != null ? ' - $_selectedArmName' : ''}';

  String _buildClassSummaryText() {
    final sb = StringBuffer();
    sb.writeln('${_schoolProfile?['name'] ?? 'School'} - NEW INTAKE BILL');
    sb.writeln('Class: ${_classLabel()}');
    sb.writeln('${_activeTerm ?? ''} | ${_activeSession ?? ''}');
    sb.writeln('');

    final standalone = _getStandaloneItemsWithAmounts();
    if (standalone.isNotEmpty) {
      sb.writeln('REGISTRATION FEES');
      for (final item in standalone) {
        sb.writeln('${item['name']}: N${_formatCurrency((item['amount'] as num?) ?? 0)}');
      }
      sb.writeln('');
    }

    if (_regularFees.isNotEmpty) {
      sb.writeln('CURRENT TERM FEES');
      for (final fee in _regularFees) {
        sb.writeln('${fee['feeItemName']}: N${_formatCurrency((fee['amount'] as num?) ?? 0)}');
      }
      sb.writeln('');
    }

    for (final category in _getSpecialFeesGroupedByCategory()) {
      sb.writeln((category['categoryName'] as String).toUpperCase());
      for (final item in (category['items'] as List<Map<String, dynamic>>)) {
        sb.writeln('${item['name']}: N${_formatCurrency((item['amount'] as num?) ?? 0)}');
      }
      sb.writeln('');
    }

    sb.writeln('Grand Total: N${_formatCurrency(_regularTotal + _specialTotal)}');
    sb.write(formatBankAccountsForSms(_getBankAccounts()));
    return sb.toString();
  }

  Future<void> _showSmsOptionsDialog() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class first')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.sms, color: Colors.teal), SizedBox(width: 8), Text('Send via SMS')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share, color: Colors.blue),
              title: const Text('Share Class Summary'),
              subtitle: const Text('Send one message with the full fee breakdown'),
              onTap: () {
                Navigator.pop(ctx);
                _shareClassSummary();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.groups, color: Colors.deepPurple),
              title: const Text('Send to All Parents'),
              subtitle: const Text('Each parent gets their own bill summary SMS'),
              onTap: () {
                Navigator.pop(ctx);
                _sendToAllParents();
              },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
  }

  Future<void> _shareClassSummary() async {
    await Share.share(
      _buildClassSummaryText(),
      subject: 'New Intake Bill - ${_classLabel()}',
    );
  }

  /// Fetches every active student in the selected class/arm with a parent
  /// phone number. Unlike term bills, the New Intake Bill is a flat
  /// class-level template (no per-student payment tracking), so every
  /// parent gets the same grand total.
  Future<List<Map<String, dynamic>>> _fetchStudentsForSelection() async {
    if (_selectedClassId == null) return [];

    final database = await _db.database;
    final where = StringBuffer('isActive = 1 AND classId = ?');
    final whereArgs = <dynamic>[_selectedClassId];
    if (_selectedArmId != null) {
      where.write(' AND armId = ?');
      whereArgs.add(_selectedArmId);
    }

    final results = await database.query(
      'students',
      columns: ['id as studentId', 'surname', 'firstName', 'otherName', 'parentPhone'],
      where: where.toString(),
      whereArgs: whereArgs,
      orderBy: 'surname, firstName',
    );

    return results.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _sendToAllParents() async {
    setState(() => _exporting = true);
    List<Map<String, dynamic>> students;
    try {
      students = await _fetchStudentsForSelection();
    } catch (e) {
      setState(() => _exporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading students: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    setState(() => _exporting = false);

    if (students.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No students found in this class')),
        );
      }
      return;
    }

    final withPhone = students.where((s) => (s['parentPhone'] as String?)?.trim().isNotEmpty == true).length;

    final provider = await _db.getSetting(SmsService.keyProvider);
    if (provider == SmsService.providerDeviceMessagingApp) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your SMS provider is set to "Device Messaging App", which opens the messaging app for each '
            'message and cannot be used for bulk sending. Switch to Termii or Device SIM in Preferences > '
            'SMS Settings, or use "Share Class Summary" instead.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Bill SMS'),
        content: Text(
          'Send each student\'s bill summary to their parent?\n\n'
          '${_classLabel()}: $withPhone of ${students.length} student(s) have a phone number on file.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _exporting = true);

    final bankAccounts = _getBankAccounts();
    final grandTotal = _regularTotal + _specialTotal;
    int sent = 0;
    int failed = 0;
    for (final s in students) {
      final studentName = '${s['surname']} ${s['firstName']} ${s['otherName'] ?? ''}'.trim();

      final message = buildNewIntakeBillSummarySms(
        schoolName: _schoolProfile?['name']?.toString() ?? 'the school',
        studentName: studentName,
        grandTotal: grandTotal,
        term: _activeTerm ?? '',
        session: _activeSession ?? '',
        bankAccounts: bankAccounts,
      );

      final result = await SmsService.send(
        rawPhone: s['parentPhone'] as String?,
        message: message,
        studentId: s['studentId'] as int,
        context: 'new_intake_bill',
      );

      if (result.success) {
        sent++;
      } else {
        failed++;
      }
    }

    setState(() => _exporting = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('SMS sent: $sent succeeded, $failed failed'),
        backgroundColor: failed == 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _exportToPDF() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class first')),
      );
      return;
    }

    setState(() => _exporting = true);

    try {
      final pdfPath = await NewIntakeBillsPDFGenerator.generateNewIntakeBillPDF(
        regularFees: _regularFees,
        groupedCategories: _getSpecialFeesGroupedByCategory(),
        standaloneItems: _getStandaloneItemsWithAmounts(),
        grandTotal: _regularTotal + _specialTotal,
        term: _activeTerm ?? '',
        session: _activeSession ?? '',
        className: _selectedClassName ?? '',
        armName: _selectedArmName,
        schoolProfile: _schoolProfile ?? {},
      );

      setState(() => _exporting = false);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('PDF Generated'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New Intake Bill PDF has been generated.'),
              const SizedBox(height: 12),
              Text(
                'File: ${pdfPath.split('/').last}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await Printing.sharePdf(
                  bytes: await File(pdfPath).readAsBytes(),
                  filename: pdfPath.split('/').last,
                );
              },
              icon: const Icon(Icons.share),
              label: const Text('Share'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportToJPEG() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class first')),
      );
      return;
    }

    setState(() => _exporting = true);

    try {
      // Capture the bill widget as image
      RenderRepaintBoundary boundary =
          _billKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Save to file in Download folder
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final className = _selectedClassName?.replaceAll(' ', '_') ?? 'class';
      final fileName = 'NewIntakeBill_${className}_$timestamp.png';

      String filePath;
      if (Platform.isAndroid) {
        // For Android, save to Download folder
        filePath = '/storage/emulated/0/Download/$fileName';
      } else if (Platform.isIOS) {
        // For iOS, use documents directory as download folder is not directly accessible
        final directory = await getApplicationDocumentsDirectory();
        filePath = '${directory.path}/$fileName';
      } else {
        // Fallback for other platforms
        final directory = await getApplicationDocumentsDirectory();
        filePath = '${directory.path}/$fileName';
      }

      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      setState(() => _exporting = false);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Image Saved'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New Intake Bill image has been saved.'),
              const SizedBox(height: 12),
              Text(
                'File: ${filePath.split('/').last}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await Printing.sharePdf(
                  bytes: pngBytes,
                  filename: filePath.split('/').last,
                );
              },
              icon: const Icon(Icons.share),
              label: const Text('Share'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showPrintMethodDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.print, color: Colors.green), SizedBox(width: 8), Text('Print Bill')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bluetooth, color: Colors.blue),
              title: const Text('Bluetooth Printer'),
              subtitle: const Text('Wireless thermal printer'),
              onTap: () { Navigator.pop(ctx); _printThermal(); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.usb, color: Colors.deepPurple),
              title: const Text('USB Printer (OTG)'),
              subtitle: const Text('Wired via USB cable'),
              onTap: () { Navigator.pop(ctx); _printViaUsb(); },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
  }

  Future<void> _printViaUsb() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class first')),
      );
      return;
    }
    if (!UsbPrinterManager.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect a USB printer first'), duration: Duration(seconds: 2)),
      );
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const UsbPrinterScreen()));
      if (!UsbPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('USB printer not connected. Cancelled.'), backgroundColor: Colors.orange),
        );
        return;
      }
    }
    setState(() => _exporting = true);
    try {
      final paperSize = await UsbPrinterManager.getPaperSizeEnum();
      await UsbPrinterManager.printNewIntakeBill(
        schoolName: _schoolProfile?['name'] ?? 'School Name',
        schoolAddress: _schoolProfile?['address'] ?? '',
        schoolPhone: _schoolProfile?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        className: _selectedClassName ?? '',
        armName: _selectedArmName,
        term: _activeTerm ?? '',
        session: _activeSession ?? '',
        regularFees: _regularFees,
        groupedCategories: _getSpecialFeesGroupedByCategory(),
        standaloneItems: _getStandaloneItemsWithAmounts(),
        grandTotal: _regularTotal + _specialTotal,
        paperSize: paperSize,
      );
      await PrintCounterHelper.incrementBillsPrinted();
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill printed via USB!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB print error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _printThermal() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class first')),
      );
      return;
    }

    // Check if thermal printer is connected
    if (!ThermalPrinterManager.isConnected) {
      // Show printer selection dialog
      await _showPrinterSelectionDialog();
      return;
    }

    setState(() => _exporting = true);

    try {
      // Get paper size for the connected printer
      final paperSize = await ThermalPrinterManager.getPrinterPaperSizeEnum(
        ThermalPrinterManager.connectedPrinter!.remoteId.toString(),
      );

      await ThermalPrinterManager.printNewIntakeBill(
        schoolName: _schoolProfile?['name'] ?? 'School Name',
        schoolAddress: _schoolProfile?['address'] ?? '',
        schoolPhone: _schoolProfile?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        className: _selectedClassName ?? '',
        armName: _selectedArmName,
        term: _activeTerm ?? '',
        session: _activeSession ?? '',
        regularFees: _regularFees,
        groupedCategories: _getSpecialFeesGroupedByCategory(),
        standaloneItems: _getStandaloneItemsWithAmounts(),
        grandTotal: _regularTotal + _specialTotal,
        paperSize: paperSize,
      );
      await PrintCounterHelper.incrementBillsPrinted();

      setState(() => _exporting = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bill printed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showPrinterSelectionDialog() async {
    // Check Bluetooth permissions
    final hasPermission = await ThermalPrinterManager.requestBluetoothPermissions();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bluetooth permissions required for printing'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if Bluetooth is on
    final isBluetoothOn = await ThermalPrinterManager.isBluetoothOn();
    if (!isBluetoothOn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please turn on Bluetooth'),
          backgroundColor: Colors.orange,
        ),
      );
      try {
        await ThermalPrinterManager.requestBluetoothOn();
      } catch (e) {
        debugPrint('Could not turn on Bluetooth: $e');
      }
      return;
    }

    if (!mounted) return;

    // Show printer selection dialog
    showDialog(
      context: context,
      builder: (context) => _PrinterSelectionDialog(
        onPrinterConnected: () {
          Navigator.pop(context);
          _printThermal(); // Retry printing after connection
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = _regularTotal + _specialTotal;
    final hasBillData = _regularFees.isNotEmpty || _specialFees.isNotEmpty;
    final bankAccounts = _getBankAccounts();

    return Scaffold(
      appBar: AppBar(
        title: const Text("View New Intake Bills"),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _loading && _classes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Selection area
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border(
                      bottom: BorderSide(color: Colors.orange.shade200),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Term/Session info
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Text(
                            '$_activeTerm | $_activeSession',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Class dropdown
                      DropdownButtonFormField<int>(
                        initialValue: _selectedClassId,
                        decoration: InputDecoration(
                          labelText: 'Select Class',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.school),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: _classes
                            .map((c) => DropdownMenuItem<int>(
                                  value: c['id'] as int,
                                  child: Text(c['name'] as String),
                                ))
                            .toList(),
                        onChanged: _onClassChanged,
                      ),

                      // Arm dropdown
                      if (_selectedClassId != null && _arms.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _loadingArms
                            ? const Center(child: CircularProgressIndicator())
                            : DropdownButtonFormField<int>(
                                initialValue: _selectedArmId,
                                decoration: InputDecoration(
                                  labelText: 'Select Arm',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.class_),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                items: _arms
                                    .map((a) => DropdownMenuItem<int>(
                                          value: a['id'] as int,
                                          child: Text(a['name'] as String),
                                        ))
                                    .toList(),
                                onChanged: _onArmChanged,
                              ),
                      ],
                    ],
                  ),
                ),

                // Export buttons
                if (hasBillData)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _exporting ? null : _exportToPDF,
                                icon: const Icon(Icons.picture_as_pdf, size: 18),
                                label: const Text('PDF'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _exporting ? null : _exportToJPEG,
                                icon: const Icon(Icons.image, size: 18),
                                label: const Text('JPEG'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _exporting ? null : _showSmsOptionsDialog,
                                icon: const Icon(Icons.sms, size: 18),
                                label: const Text('SMS'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _exporting ? null : _showPrintMethodDialog,
                                icon: const Icon(Icons.print, size: 18),
                                label: const Text('Print'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Bill content
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _selectedClassId == null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.school, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Select a class to view bills',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : !hasBillData
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No fees assigned to this class',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Assign fees first in Fee Items and Special Bills Items',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: RepaintBoundary(
                                    key: _billKey,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.grey.shade300,
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          // Header
                                          Container(
                                            padding: const EdgeInsets.all(20),
                                            decoration: BoxDecoration(
                                              color: Colors.deepOrange.shade50,
                                              borderRadius: const BorderRadius.only(
                                                topLeft: Radius.circular(12),
                                                topRight: Radius.circular(12),
                                              ),
                                            ),
                                            child: Column(
                                              children: [
                                                if (_schoolLogoFile != null) ...[
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Image.file(
                                                      _schoolLogoFile!,
                                                      width: 60,
                                                      height: 60,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                ],
                                                Text(
                                                  _schoolProfile?['name'] ?? 'School Name',
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 8),
                                                const Text(
                                                  'NEW INTAKE BILL',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.deepOrange,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Chip(
                                                      label: Text('$_selectedClassName${_selectedArmName != null ? ' - $_selectedArmName' : ''}'),
                                                      backgroundColor: Colors.deepOrange.shade100,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Chip(
                                                      label: Text('$_activeTerm | $_activeSession'),
                                                      backgroundColor: Colors.orange.shade100,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Registration Fees Section (standalone items) - shown first
                                          ..._getStandaloneItemsWithAmounts().asMap().entries.map((entry) {
                                            final index = entry.key;
                                            final item = entry.value;
                                            final isFirst = index == 0;

                                            return Column(
                                              children: [
                                                // Header for first standalone item
                                                if (isFirst)
                                                  Container(
                                                    width: double.infinity,
                                                    padding: const EdgeInsets.all(12),
                                                    color: Colors.orange.shade100,
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.receipt_long, size: 18, color: Colors.orange.shade700),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          'REGISTRATION FEES',
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.orange.shade700,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                // Item row
                                                Container(
                                                  decoration: BoxDecoration(
                                                    color: index.isOdd ? Colors.orange.shade50.withValues(alpha: 0.3) : Colors.white,
                                                  ),
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: CircleAvatar(
                                                      radius: 14,
                                                      backgroundColor: Colors.orange.shade100,
                                                      child: Icon(
                                                        Icons.receipt,
                                                        size: 14,
                                                        color: Colors.orange.shade700,
                                                      ),
                                                    ),
                                                    title: Text(
                                                      item['name'] ?? 'Unknown',
                                                      style: const TextStyle(fontSize: 14),
                                                    ),
                                                    trailing: Text(
                                                      '₦${_formatCurrency(item['amount'] ?? 0)}',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w500,
                                                        color: Colors.orange.shade700,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }),

                                          // Current Term Fees Section (regular fees)
                                          if (_regularFees.isNotEmpty) ...[
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              color: Colors.grey.shade200,
                                              child: Row(
                                                children: [
                                                  Icon(Icons.list_alt, size: 18, color: Colors.grey.shade700),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'CURRENT TERM FEES',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    '₦${_formatCurrency(_regularTotal)}',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            ..._regularFees.asMap().entries.map((entry) {
                                              final index = entry.key;
                                              final fee = entry.value;
                                              return Container(
                                                decoration: BoxDecoration(
                                                  color: index.isOdd ? Colors.grey.shade50 : Colors.white,
                                                ),
                                                child: ListTile(
                                                  dense: true,
                                                  leading: CircleAvatar(
                                                    radius: 14,
                                                    backgroundColor: Colors.grey.shade200,
                                                    child: Text(
                                                      '${index + 1}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.grey.shade600,
                                                      ),
                                                    ),
                                                  ),
                                                  title: Text(fee['feeItemName'] ?? 'Unknown'),
                                                  trailing: Text(
                                                    '₦${_formatCurrency(fee['amount'] ?? 0)}',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w500,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }),
                                          ],

                                          // Special Fees Section - Grouped by Category
                                          ..._getSpecialFeesGroupedByCategory().map((categoryData) {
                                            final categoryName = categoryData['categoryName'] as String;
                                            final items = categoryData['items'] as List<Map<String, dynamic>>;
                                            final categoryTotal = categoryData['categoryTotal'] as double;

                                            return Column(
                                              children: [
                                                // Category header
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.all(12),
                                                  color: Colors.deepOrange.shade100,
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.folder, size: 18, color: Colors.deepOrange.shade700),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          categoryName.toUpperCase(),
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.deepOrange.shade700,
                                                          ),
                                                        ),
                                                      ),
                                                      Text(
                                                        '₦${_formatCurrency(categoryTotal)}',
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.deepOrange.shade700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                // Category items
                                                ...items.asMap().entries.map((entry) {
                                                  final index = entry.key;
                                                  final item = entry.value;
                                                  return Container(
                                                    decoration: BoxDecoration(
                                                      color: index.isOdd ? Colors.deepOrange.shade50.withValues(alpha: 0.3) : Colors.white,
                                                    ),
                                                    child: ListTile(
                                                      dense: true,
                                                      leading: Container(
                                                        width: 28,
                                                        height: 28,
                                                        decoration: BoxDecoration(
                                                          color: Colors.deepOrange.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Icon(
                                                          Icons.subdirectory_arrow_right,
                                                          size: 16,
                                                          color: Colors.deepOrange.shade400,
                                                        ),
                                                      ),
                                                      title: Text(
                                                        item['name'] ?? 'Unknown',
                                                        style: const TextStyle(fontSize: 14),
                                                      ),
                                                      trailing: Text(
                                                        '₦${_formatCurrency(item['amount'] ?? 0)}',
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w500,
                                                          color: Colors.deepOrange.shade700,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }),
                                              ],
                                            );
                                          }),

                                          // Grand Total
                                          Container(
                                            padding: const EdgeInsets.all(20),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade50,
                                              borderRadius: bankAccounts.isEmpty
                                                  ? const BorderRadius.only(
                                                      bottomLeft: Radius.circular(12),
                                                      bottomRight: Radius.circular(12),
                                                    )
                                                  : null,
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(Icons.calculate, color: Colors.green.shade700),
                                                    const SizedBox(width: 8),
                                                    const Text(
                                                      'GRAND TOTAL:',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 18,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  '₦${_formatCurrency(grandTotal)}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 22,
                                                    color: Colors.green.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // School Account Details
                                          if (bankAccounts.isNotEmpty)
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(16),
                                              decoration: const BoxDecoration(
                                                color: Color(0xFFE3F2FD),
                                                borderRadius: BorderRadius.only(
                                                  bottomLeft: Radius.circular(12),
                                                  bottomRight: Radius.circular(12),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'SCHOOL ACCOUNT DETAILS',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.blue.shade900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  for (int i = 0; i < bankAccounts.length; i++) ...[
                                                    if (i > 0) const SizedBox(height: 10),
                                                    _bankDetailRow('Name of Bank:', bankAccounts[i]['bankName'] as String),
                                                    _bankDetailRow('Account Number:', bankAccounts[i]['accountNumber'] as String),
                                                    if ((bankAccounts[i]['accountName'] as String).isNotEmpty)
                                                      _bankDetailRow('Account Name:', bankAccounts[i]['accountName'] as String),
                                                  ],
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                ),
              ],
            ),
    );
  }
}

// Printer Selection Dialog
class _PrinterSelectionDialog extends StatefulWidget {
  final VoidCallback onPrinterConnected;

  const _PrinterSelectionDialog({required this.onPrinterConnected});

  @override
  State<_PrinterSelectionDialog> createState() => _PrinterSelectionDialogState();
}

class _PrinterSelectionDialogState extends State<_PrinterSelectionDialog> {
  List<ScanResult> _devices = [];
  List<Map<String, String>> _recentPrinters = [];
  bool _scanning = false;
  String? _connectingDeviceId;

  @override
  void initState() {
    super.initState();
    _loadRecentPrinters();
    _startScan();
  }

  Future<void> _loadRecentPrinters() async {
    final recent = await ThermalPrinterManager.getRecentPrinters();
    if (mounted) {
      setState(() => _recentPrinters = recent);
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _devices = [];
    });

    try {
      final devices = await ThermalPrinterManager.scanForPrinters(
        timeout: const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() {
          _devices = devices;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e')),
        );
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() => _connectingDeviceId = device.remoteId.toString());

    try {
      final success = await ThermalPrinterManager.connect(device);
      if (success) {
        widget.onPrinterConnected();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to printer'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _connectingDeviceId = null);
      }
    }
  }

  Future<void> _connectToRecentPrinter(Map<String, String> printerInfo) async {
    setState(() => _connectingDeviceId = printerInfo['remoteId']);

    try {
      // Try to find the device in scanned devices
      final device = _devices.firstWhere(
        (d) => d.device.remoteId.toString() == printerInfo['remoteId'],
        orElse: () => throw Exception('Device not found. Please scan again.'),
      );

      await _connectToDevice(device.device);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _connectingDeviceId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.print, color: Colors.green),
          const SizedBox(width: 8),
          const Expanded(child: Text('Select Printer')),
          if (_scanning)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
              tooltip: 'Scan again',
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recent printers
            if (_recentPrinters.isNotEmpty) ...[
              const Text(
                'Recent Printers',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ...(_recentPrinters.map((printer) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, color: Colors.blue),
                    title: Text(printer['name'] ?? 'Unknown'),
                    trailing: _connectingDeviceId == printer['remoteId']
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth, size: 18),
                    onTap: _connectingDeviceId == null
                        ? () => _connectToRecentPrinter(printer)
                        : null,
                  ))),
              const Divider(),
            ],

            // Available devices
            const Text(
              'Available Devices',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _scanning && _devices.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Scanning for printers...'),
                        ],
                      ),
                    )
                  : _devices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.bluetooth_disabled,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              const Text('No printers found'),
                              TextButton(
                                onPressed: _startScan,
                                child: const Text('Scan Again'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            final device = _devices[index].device;
                            final name = device.platformName.isNotEmpty
                                ? device.platformName
                                : 'Unknown Device';
                            final isConnecting =
                                _connectingDeviceId == device.remoteId.toString();

                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.print, color: Colors.green),
                              title: Text(name),
                              subtitle: Text(
                                device.remoteId.toString(),
                                style: const TextStyle(fontSize: 10),
                              ),
                              trailing: isConnecting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.chevron_right),
                              onTap: _connectingDeviceId == null
                                  ? () => _connectToDevice(device)
                                  : null,
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
  }
}
