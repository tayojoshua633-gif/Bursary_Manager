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

class ViewTermBillsScreen extends StatefulWidget {
  const ViewTermBillsScreen({super.key});

  @override
  State<ViewTermBillsScreen> createState() => _ViewTermBillsScreenState();
}

class _ViewTermBillsScreenState extends State<ViewTermBillsScreen> {
  static const List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];

  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final GlobalKey _billKey = GlobalKey();

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  List<Map<String, dynamic>> _feeItems = [];
  List<Map<String, dynamic>> _sessions = [];

  String? _activeTerm;
  String? _activeSession;
  int? _selectedClassId;
  int? _selectedArmId;
  String? _selectedClassName;
  String? _selectedArmName;

  double _grandTotal = 0;

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
    _sessions = await _db.getAllSessions();
    _classes = await _db.getClasses();
    _schoolProfile = await _db.getSchoolProfile();

    if (mounted) setState(() => _loading = false);
  }

  void _onTermChanged(String? term) {
    if (term == null) return;
    setState(() => _activeTerm = term);
    if (_selectedClassId != null) _loadBillsForSelection();
  }

  void _onSessionChanged(String? session) {
    if (session == null) return;
    setState(() => _activeSession = session);
    if (_selectedClassId != null) _loadBillsForSelection();
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
      _feeItems = [];
      _grandTotal = 0;
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

    final database = await _db.database;
    final where = StringBuffer('cf.classId = ? AND cf.term = ? AND cf.session = ?');
    final whereArgs = <dynamic>[_selectedClassId, _activeTerm ?? '', _activeSession ?? ''];
    if (_selectedArmId != null) {
      where.write(' AND cf.armId = ?');
      whereArgs.add(_selectedArmId);
    } else {
      where.write(' AND (cf.armId IS NULL OR cf.armId = 0)');
    }

    final rows = await database.rawQuery('''
      SELECT fi.name AS feeItemName, cf.amount
      FROM class_fees cf
      JOIN fee_items fi ON fi.id = cf.feeItemId
      WHERE $where
      ORDER BY fi.name ASC
    ''', whereArgs);

    final feeItems = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    final grandTotal = feeItems.fold<double>(
      0,
      (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
    );

    setState(() {
      _feeItems = feeItems;
      _grandTotal = grandTotal;
      _loading = false;
    });
  }

  /// Fetches every active student in the selected class/arm with their actual
  /// bill totals for the active term (including carried-over previous balance
  /// and payments already made) — used for the per-student bulk SMS send,
  /// since individual bills can differ from the class fee template.
  Future<List<Map<String, dynamic>>> _fetchStudentsForSelection() async {
    if (_selectedClassId == null) return [];

    final database = await _db.database;
    final targetKey = DatabaseHelperWrapper.termSortKey(_activeTerm ?? '', _activeSession ?? '');

    final where = StringBuffer('s.isActive = 1 AND s.classId = ?');
    final whereArgs = <dynamic>[];
    final tailArgs = <dynamic>[_selectedClassId];
    if (_selectedArmId != null) {
      where.write(' AND s.armId = ?');
      tailArgs.add(_selectedArmId);
    }

    whereArgs.addAll([
      targetKey,
      targetKey,
      _activeTerm ?? '',
      _activeSession ?? '',
      _activeTerm ?? '',
      _activeSession ?? '',
      ...tailArgs,
    ]);

    final results = await database.rawQuery('''
      SELECT
        s.id as studentId,
        s.surname,
        s.firstName,
        s.otherName,
        s.parentPhone,
        (COALESCE(b.totalAmount, 0) - COALESCE(b.previousBalance, 0)) as currentTermFee,
        (
          COALESCE((SELECT SUM(b2.totalAmount - b2.previousBalance) FROM student_bills b2
                    WHERE b2.studentId = s.id
                      AND ${DatabaseHelperWrapper.sqlTermKeyExpr('b2')} < ?), 0)
          -
          COALESCE((SELECT SUM(p2.amount) FROM payments p2
                    WHERE p2.studentId = s.id
                      AND ${DatabaseHelperWrapper.sqlTermKeyExpr('p2')} < ?), 0)
        ) as freshPreviousBalance,
        COALESCE(
          (SELECT SUM(amount) FROM payments WHERE studentId = s.id AND term = ? AND session = ?),
          0
        ) as totalPaid
      FROM students s
      LEFT JOIN student_bills b ON s.id = b.studentId AND b.term = ? AND b.session = ?
      WHERE $where
      ORDER BY s.surname, s.firstName
    ''', whereArgs);

    return results.map((row) {
      final currentTermFee = (row['currentTermFee'] as num).toDouble();
      final freshPrev = (row['freshPreviousBalance'] as num).toDouble();
      return Map<String, dynamic>.from(row)..['grandTotal'] = currentTermFee + freshPrev;
    }).toList();
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
        regularFees: _feeItems,
        groupedCategories: const [],
        standaloneItems: const [],
        grandTotal: _grandTotal,
        term: _activeTerm ?? '',
        session: _activeSession ?? '',
        className: _selectedClassName ?? '',
        armName: _selectedArmName,
        schoolProfile: _schoolProfile ?? {},
        title: 'TERM BILL',
        filePrefix: 'TermBill',
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
              const Text('Term Bill PDF has been generated.'),
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
                backgroundColor: Colors.indigo,
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
      RenderRepaintBoundary boundary =
          _billKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final className = _selectedClassName?.replaceAll(' ', '_') ?? 'class';
      final fileName = 'TermBill_${className}_$timestamp.png';

      String filePath;
      if (Platform.isAndroid) {
        filePath = '/storage/emulated/0/Download/$fileName';
      } else if (Platform.isIOS) {
        final directory = await getApplicationDocumentsDirectory();
        filePath = '${directory.path}/$fileName';
      } else {
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
              const Text('Term Bill image has been saved.'),
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
                backgroundColor: Colors.indigo,
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

  String _buildClassSummaryText() {
    final sb = StringBuffer();
    sb.writeln('${_schoolProfile?['name'] ?? 'School'} - TERM BILL');
    sb.writeln('Class: ${_classLabel()}');
    sb.writeln('${_activeTerm ?? ''} | ${_activeSession ?? ''}');
    sb.writeln('');
    for (final item in _feeItems) {
      sb.writeln('${item['feeItemName']}: N${_formatCurrency((item['amount'] as num?)?.toDouble() ?? 0)}');
    }
    sb.writeln('');
    sb.writeln('Grand Total: N${_formatCurrency(_grandTotal)}');
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
      subject: 'Term Bill - ${_classLabel()}',
    );
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
    int sent = 0;
    int failed = 0;
    for (final s in students) {
      final grandTotal = (s['grandTotal'] as num).toDouble();
      final totalPaid = (s['totalPaid'] as num).toDouble();
      final outstanding = grandTotal - totalPaid;
      final studentName = '${s['surname']} ${s['firstName']} ${s['otherName'] ?? ''}'.trim();

      final message = buildBillSummarySms(
        schoolName: _schoolProfile?['name']?.toString() ?? 'the school',
        studentName: studentName,
        grandTotal: grandTotal,
        totalPaid: totalPaid,
        outstanding: outstanding,
        term: _activeTerm ?? '',
        session: _activeSession ?? '',
        bankAccounts: bankAccounts,
      );

      final result = await SmsService.send(
        rawPhone: s['parentPhone'] as String?,
        message: message,
        studentId: s['studentId'] as int,
        context: 'class_bill',
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
        regularFees: _feeItems,
        groupedCategories: const [],
        standaloneItems: const [],
        grandTotal: _grandTotal,
        paperSize: paperSize,
        title: 'TERM BILL',
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

    if (!ThermalPrinterManager.isConnected) {
      await _showPrinterSelectionDialog();
      return;
    }

    setState(() => _exporting = true);

    try {
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
        regularFees: _feeItems,
        groupedCategories: const [],
        standaloneItems: const [],
        grandTotal: _grandTotal,
        paperSize: paperSize,
        title: 'TERM BILL',
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

    showDialog(
      context: context,
      builder: (context) => _TermBillPrinterSelectionDialog(
        onPrinterConnected: () {
          Navigator.pop(context);
          _printThermal();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBillData = _feeItems.isNotEmpty;
    final bankAccounts = _getBankAccounts();

    return Scaffold(
      appBar: AppBar(
        title: const Text("View Term Bills"),
        backgroundColor: Colors.indigo,
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
                    color: Colors.indigo.shade50,
                    border: Border(
                      bottom: BorderSide(color: Colors.indigo.shade200),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _activeSession,
                              decoration: InputDecoration(
                                labelText: 'Session',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.calendar_today, size: 18),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: _sessions
                                  .map((s) => s['sessionName'] as String)
                                  .toSet()
                                  .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                                  .toList(),
                              onChanged: _onSessionChanged,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _activeTerm,
                              decoration: InputDecoration(
                                labelText: 'Term',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.event, size: 18),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: _terms
                                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                  .toList(),
                              onChanged: _onTermChanged,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

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
                                    'Select a class to view its term bill breakdown',
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
                                        'Assign fees first in Fee Items',
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
                                              color: Colors.indigo.shade50,
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
                                                  'TERM BILL',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.indigo,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Chip(
                                                      label: Text(_classLabel()),
                                                      backgroundColor: Colors.indigo.shade100,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Chip(
                                                      label: Text('$_activeTerm | $_activeSession'),
                                                      backgroundColor: Colors.blue.shade100,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Fee Breakdown
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            color: Colors.grey.shade200,
                                            child: Row(
                                              children: [
                                                Icon(Icons.list_alt, size: 18, color: Colors.grey.shade700),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'FEE BREAKDOWN',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  '₦${_formatCurrency(_grandTotal)}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          ..._feeItems.asMap().entries.map((entry) {
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
                                                  '₦${_formatCurrency((fee['amount'] as num?) ?? 0)}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                              ),
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
                                                  '₦${_formatCurrency(_grandTotal)}',
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
class _TermBillPrinterSelectionDialog extends StatefulWidget {
  final VoidCallback onPrinterConnected;

  const _TermBillPrinterSelectionDialog({required this.onPrinterConnected});

  @override
  State<_TermBillPrinterSelectionDialog> createState() => _TermBillPrinterSelectionDialogState();
}

class _TermBillPrinterSelectionDialogState extends State<_TermBillPrinterSelectionDialog> {
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
