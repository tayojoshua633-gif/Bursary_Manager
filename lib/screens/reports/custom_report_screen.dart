import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/thermal_printer_manager.dart';
import '../../utils/usb_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../../utils/custom_report_pdf_generator.dart';
import '../../utils/navigation_helper.dart';
import '../../screens/settings/thermal_printer_screen.dart';
import '../../screens/settings/usb_printer_screen.dart';
import '../../screens/payments/payment_receipt_screen.dart';

class CustomReportScreen extends StatefulWidget {
  const CustomReportScreen({super.key});

  @override
  CustomReportScreenState createState() => CustomReportScreenState();
}

class CustomReportScreenState extends State<CustomReportScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelperWrapper db = DatabaseHelperWrapper();

  // Report view tabs
  static const List<String> _tabLabels = [
    'Full Report',
    'Income & Expenses',
    'Expenses Only',
    'School Fees Only',
    'Fees + Income/Expenses',
    'Stock & Sales Only',
  ];
  late TabController _tabController;
  int _reportTab = 0;

  // Section visibility derived from active tab
  bool get _showIncome    => _reportTab == 0 || _reportTab == 1 || _reportTab == 4;
  bool get _showPayments  => _reportTab == 0 || _reportTab == 3 || _reportTab == 4;
  bool get _showExpenses  => _reportTab == 0 || _reportTab == 1 || _reportTab == 2 || _reportTab == 4;
  bool get _showStockSales => _reportTab == 0 || _reportTab == 5;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _activePreset = 'week';

  double cashTotal = 0;
  double posTotal = 0;
  double transferTotal = 0;
  double totalIncome = 0;

  String? activeTerm;
  String? activeSession;

  bool loading = false;
  List<Map<String, dynamic>> paymentDetails = [];
  Map<String, dynamic>? _school;
  Map<String, dynamic>? _currentUser;
  int _paymentTabIndex = 0;
  int _methodTabIndex = 0;

  // Expense tracking
  double expenseCashTotal = 0;
  double expensePosTotal = 0;
  double expenseTransferTotal = 0;
  double totalExpenses = 0;
  Map<String, double> expenseCategoryTotals = {};
  List<Map<String, dynamic>> expenseDetails = [];

  // Stock & Sales tracking
  List<Map<String, dynamic>> stockSummary = [];
  List<Map<String, dynamic>> salesDetails = [];
  List<Map<String, dynamic>> salesDebtors = [];
  double salesCashTotal = 0;
  double salesPosTotal = 0;
  double salesTransferTotal = 0;
  double totalSales = 0;
  double totalSalesDebt = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _reportTab = _tabController.index);
      }
    });
    _applyPreset('week');
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';

    if (mounted) {
      setState(() {
        _currentUser = {
          'id': userId,
          'userType': userType,
          'username': username,
        };
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------
  // PRESETS
  // -----------------------------------------------------------
  Future<void> _applyPreset(String preset) async {
    final now = DateTime.now();

    if (preset == 'week') {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      _startDate = DateTime(monday.year, monday.month, monday.day);
      _endDate = _startDate.add(const Duration(days: 6));
    } else if (preset == 'month') {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month + 1, 0);
    } else if (preset == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      );
      if (picked == null) return;
      _startDate = picked.start;
      _endDate = picked.end;
    }

    setState(() => _activePreset = preset);
    await _loadCustomReport();
  }

  // -----------------------------------------------------------
  // LOAD CUSTOM REPORT
  // -----------------------------------------------------------
  Future<void> _loadCustomReport() async {
    if (!mounted) return;

    setState(() => loading = true);

    activeTerm = await db.getActiveTerm();
    activeSession = (await db.getActiveSession())?['sessionName'];
    _school = await db.getSchoolProfile();

    final startStr = _formatDate(_startDate);
    final endStr = _formatDate(_endDate);

    final database = await db.database;
    final raw = await database.rawQuery('''
      SELECT
        p.*,
        s.surname,
        s.firstName,
        s.admissionNo,
        c.name as className,
        a.name as armName
      FROM payments p
      INNER JOIN students s ON p.studentId = s.id
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE date(p.paymentDate) BETWEEN ? AND ?
      ORDER BY p.paymentDate DESC
    ''', [startStr, endStr]);

    cashTotal = 0;
    posTotal = 0;
    transferTotal = 0;
    paymentDetails = [];
    _paymentTabIndex = 0;
    _methodTabIndex = 0;

    for (var p in raw) {
      final paymentTerm = p['term']?.toString() ?? '';
      final paymentSession = p['session']?.toString() ?? '';

      if (activeTerm != null && activeSession != null) {
        if (paymentTerm != activeTerm || paymentSession != activeSession) {
          continue;
        }
      }

      final method = (p['method'] ?? '').toString().toUpperCase();
      final amount = (p['amount'] is num)
          ? p['amount'] as num
          : double.tryParse(p['amount'].toString()) ?? 0.0;

      paymentDetails.add({
        'paymentId': p['id'],
        'studentId': p['studentId'],
        'studentName': '${p['surname']} ${p['firstName']}',
        'admissionNo': p['admissionNo'],
        'className': p['className'] ?? 'N/A',
        'armName': p['armName'] ?? 'N/A',
        'method': method,
        'amount': amount,
        'paymentDate': p['paymentDate'],
        'term': p['term'],
        'session': p['session'],
        'paymentFor': p['paymentFor']?.toString() ?? 'School Fees',
      });

      if (method == 'CASH') {
        cashTotal += amount;
      } else if (method == 'POS') {
        posTotal += amount;
      } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
        transferTotal += amount;
      }
    }

    totalIncome = cashTotal + posTotal + transferTotal;

    // Expenses
    expenseCashTotal = 0;
    expensePosTotal = 0;
    expenseTransferTotal = 0;
    expenseDetails = [];
    expenseCategoryTotals = {};

    try {
      final expensesRaw = await database.rawQuery('''
        SELECT * FROM expenses
        WHERE date(expenseDate) BETWEEN ? AND ?
        ORDER BY expenseDate DESC
      ''', [startStr, endStr]);

      for (var e in expensesRaw) {
        final expenseTerm = e['term']?.toString() ?? '';
        final expenseSession = e['session']?.toString() ?? '';

        if (activeTerm != null && activeSession != null) {
          if (expenseTerm != activeTerm || expenseSession != activeSession) {
            continue;
          }
        }

        final method = (e['paymentMethod'] ?? '').toString().toUpperCase();
        final amount = (e['amount'] is num)
            ? (e['amount'] as num).toDouble()
            : double.tryParse(e['amount'].toString()) ?? 0.0;

        final category = (e['category'] ?? 'Uncategorized').toString();
        final customCategory = e['customCategory']?.toString();
        final displayCategory = category == 'Other' && customCategory != null
            ? 'Other: $customCategory'
            : category;

        expenseDetails.add({
          'description': e['description'],
          'category': displayCategory,
          'recipient': e['recipient'],
          'method': method,
          'amount': amount,
          'expenseDate': e['expenseDate'],
        });

        if (method == 'CASH') {
          expenseCashTotal += amount;
        } else if (method == 'POS') {
          expensePosTotal += amount;
        } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
          expenseTransferTotal += amount;
        }

        expenseCategoryTotals[displayCategory] =
            (expenseCategoryTotals[displayCategory] ?? 0) + amount;
      }

      totalExpenses = expenseCashTotal + expensePosTotal + expenseTransferTotal;
    } catch (e) {
      print('Error loading expenses: $e');
      totalExpenses = 0;
    }

    // Stock & Sales
    try {
      salesCashTotal = 0;
      salesPosTotal = 0;
      salesTransferTotal = 0;
      totalSales = 0;
      totalSalesDebt = 0;
      salesDetails = [];
      stockSummary = [];
      salesDebtors = [];

      final salesRaw = await database.rawQuery('''
        SELECT
          s.*,
          COALESCE(si.itemName, s.itemName) as itemName,
          si.costPrice,
          si.currentQuantity as currentStockQuantity
        FROM sales s
        LEFT JOIN stock_items si ON s.stockItemId = si.id AND s.stockItemId > 0
        WHERE date(s.saleDate) BETWEEN ? AND ?
        ORDER BY s.saleDate DESC
      ''', [startStr, endStr]);

      Map<String, Map<String, dynamic>> salesByBuyer = {};
      Map<int, Map<String, dynamic>> stockMovement = {};

      for (var sale in salesRaw) {
        final saleTerm = sale['term']?.toString() ?? '';
        final saleSession = sale['session']?.toString() ?? '';

        if ((activeTerm?.isNotEmpty ?? false) &&
            (activeSession?.isNotEmpty ?? false)) {
          if (saleTerm != activeTerm || saleSession != activeSession) {
            continue;
          }
        }

        final qty = (sale['quantity'] as int);
        if (qty == 0) continue;

        final method = (sale['paymentMethod'] ?? '').toString().toUpperCase();
        final totalAmount = (sale['totalAmount'] as num).toDouble();
        final amountPaid = (sale['amountPaid'] as num).toDouble();
        final paymentStatus = sale['paymentStatus']?.toString() ?? 'Unpaid';
        final stockItemId = sale['stockItemId'] as int;
        final itemName = sale['itemName']?.toString() ?? 'Unknown Item';
        final buyerName = sale['buyerName']?.toString() ?? 'Unknown';
        final buyerType = sale['buyerType']?.toString() ?? '';
        final currentStockQty = (sale['currentStockQuantity'] as int?) ?? 0;

        final isCustomItem = sale['isCustomItem'] == 1 || stockItemId == 0;

        final buyerKey = '$buyerName|$buyerType';
        if (!salesByBuyer.containsKey(buyerKey)) {
          salesByBuyer[buyerKey] = {
            'buyerName': buyerName,
            'buyerType': buyerType,
            'items': <Map<String, dynamic>>[],
            'totalQtySold': 0,
            'totalAmount': 0.0,
            'totalPaid': 0.0,
            'paymentStatus': paymentStatus,
          };
        }

        salesByBuyer[buyerKey]!['items'].add({
          'itemName': itemName,
          'quantity': qty,
          'unitPrice': (sale['unitPrice'] as num).toDouble(),
          'isCustomItem': isCustomItem,
        });
        salesByBuyer[buyerKey]!['totalQtySold'] += qty;
        salesByBuyer[buyerKey]!['totalAmount'] += totalAmount;
        salesByBuyer[buyerKey]!['totalPaid'] += amountPaid;

        if (!isCustomItem && stockItemId > 0) {
          if (!stockMovement.containsKey(stockItemId)) {
            stockMovement[stockItemId] = {
              'itemName': itemName,
              'qtySold': 0,
              'currentQuantity': currentStockQty,
            };
          }
          stockMovement[stockItemId]!['qtySold'] += qty;
        }

        if (method == 'CASH') {
          salesCashTotal += amountPaid;
        } else if (method == 'POS') {
          salesPosTotal += amountPaid;
        } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
          salesTransferTotal += amountPaid;
        }

        totalSales += amountPaid;
      }

      salesDetails = salesByBuyer.values.toList();

      final allStockItems = await database.query('stock_items', orderBy: 'itemName');

      stockSummary = allStockItems.map((stockItem) {
        final stockItemId = stockItem['id'] as int;
        final itemName = stockItem['itemName']?.toString() ?? 'Unknown';
        final currentQty = (stockItem['currentQuantity'] as int?) ?? 0;

        final qtySold = stockMovement.containsKey(stockItemId)
            ? (stockMovement[stockItemId]!['qtySold'] as int)
            : 0;

        final beginningQty = currentQty + qtySold;

        return {
          'itemName': itemName,
          'beginningQuantity': beginningQty,
          'qtySold': qtySold,
          'remainingQuantity': currentQty,
        };
      }).toList();

      final debtorsRaw = await database.rawQuery('''
        SELECT DISTINCT
          sd.buyerName,
          sd.buyerType,
          sd.studentId,
          sd.totalAmount,
          sd.amountPaid,
          sd.outstandingBalance
        FROM sales_debtors sd
        INNER JOIN sales s ON sd.buyerName = s.buyerName AND sd.buyerType = s.buyerType
        WHERE date(s.saleDate) BETWEEN ? AND ? AND s.quantity > 0 AND sd.outstandingBalance > 0
      ''', [startStr, endStr]);

      for (var debtor in debtorsRaw) {
        final buyerName = debtor['buyerName']?.toString() ?? 'Unknown';
        final buyerType = debtor['buyerType']?.toString() ?? '';

        final debtorSalesRaw = await database.rawQuery('''
          SELECT COALESCE(si.itemName, s.itemName) as itemName, s.quantity, s.stockItemId, s.isCustomItem
          FROM sales s
          LEFT JOIN stock_items si ON s.stockItemId = si.id AND s.stockItemId > 0
          WHERE s.buyerName = ? AND s.buyerType = ? AND date(s.saleDate) BETWEEN ? AND ? AND s.quantity > 0
        ''', [buyerName, buyerType, startStr, endStr]);

        final itemsList = debtorSalesRaw.map((item) {
          final itemName = item['itemName']?.toString() ?? '';
          final qty = item['quantity'] as int;
          final isCustomItem = item['isCustomItem'] == 1 || item['stockItemId'] == 0;
          return isCustomItem ? '$itemName [Custom] (x$qty)' : '$itemName (x$qty)';
        }).join(', ');

        salesDebtors.add({
          'buyerName': buyerName,
          'buyerType': buyerType,
          'itemsPurchased': itemsList,
          'totalAmount': (debtor['totalAmount'] as num).toDouble(),
          'totalPaid': (debtor['amountPaid'] as num).toDouble(),
          'outstandingBalance': (debtor['outstandingBalance'] as num).toDouble(),
        });

        totalSalesDebt += (debtor['outstandingBalance'] as num).toDouble();
      }
    } catch (e) {
      print('Error loading stock & sales data: $e');
      salesCashTotal = 0;
      salesPosTotal = 0;
      salesTransferTotal = 0;
      totalSales = 0;
      totalSalesDebt = 0;
      salesDetails = [];
      stockSummary = [];
      salesDebtors = [];
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  List<String> get _paymentCategories {
    final seen = <String>{};
    final cats = <String>['All'];
    for (final p in paymentDetails) {
      final cat = p['paymentFor']?.toString() ?? 'School Fees';
      if (seen.add(cat)) cats.add(cat);
    }
    return cats;
  }

  // Payment method filter tabs: All, Cash, Transfer, POS
  static const List<String> _methodCategories = ['All', 'Cash', 'Transfer', 'POS'];

  List<Map<String, dynamic>> get _filteredPayments {
    final cats = _paymentCategories;
    var result = paymentDetails;
    if (_paymentTabIndex != 0 && _paymentTabIndex < cats.length) {
      final selected = cats[_paymentTabIndex];
      result = result.where((p) => (p['paymentFor'] ?? 'School Fees') == selected).toList();
    }
    if (_methodTabIndex != 0 && _methodTabIndex < _methodCategories.length) {
      final selectedMethod = _methodCategories[_methodTabIndex].toUpperCase();
      result = result.where((p) {
        final method = (p['method'] ?? '').toString().toUpperCase();
        if (selectedMethod == 'TRANSFER') {
          return method == 'TRANSFER' || method == 'BANK TRANSFER';
        }
        return method == selectedMethod;
      }).toList();
    }
    return result;
  }

  String _formatDate(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  String get _rangeLabel {
    return '${DateFormat('MMM d, yyyy').format(_startDate)} - ${DateFormat('MMM d, yyyy').format(_endDate)}';
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

  // -----------------------------------------------------------
  // RECEIPT REPRINT FLOW
  // -----------------------------------------------------------
  Future<void> _showReceiptPrintOptions(Map<String, dynamic> payment) async {
    final paymentId = payment['paymentId'] as int?;
    final studentId = payment['studentId'] as int?;

    if (paymentId != null && studentId != null) {
      await NavigationHelper.pushWithSidebar(
        context,
        page: PaymentReceiptScreen(
          paymentId: paymentId,
          studentId: studentId,
          showExportDialog: true,
        ),
        currentUser: _currentUser ?? {},
        pageId: 'bills_payment/payments',
      );
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-Print Receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              payment['studentName'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Class: ${payment['className']} - ${payment['armName']}'),
            const SizedBox(height: 8),
            Text('Amount: N ${(payment['amount'] as num).toStringAsFixed(2)}'),
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
              _printReceiptThermal(payment);
            },
            icon: const Icon(Icons.bluetooth),
            label: const Text('Bluetooth'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printReceiptViaUsb(payment);
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

  Future<void> _printReceiptThermal(Map<String, dynamic> payment) async {
    if (!ThermalPrinterManager.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to a thermal printer first'),
          duration: Duration(seconds: 2),
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ThermalPrinterScreen()),
      );
      if (!ThermalPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Printer not connected. Receipt printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    try {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final amount = payment['amount'] as num;
      final schoolName = _school?['name'] ?? "School Name";
      final schoolAddress = _school?['address'] ?? "";
      final studentId = payment['studentId'] as int;

      final term = activeTerm ?? await db.getActiveTerm();
      final session = activeSession ?? (await db.getActiveSession())?['sessionName'];

      final bill = await db.getBillForStudent(studentId, term, session);
      final totalBills = bill != null ? (bill['totalAmount'] as num?)?.toDouble() ?? 0.0 : 0.0;

      final payments = await db.getPayments(studentId, term: term, session: session);
      final totalPaid = payments.fold<double>(
        0.0,
        (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0.0),
      );

      final outstanding = totalBills - totalPaid;

      await ThermalPrinterManager.printPaymentReceipt(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        studentName: payment['studentName'],
        studentClass: '${payment['className']} - ${payment['armName']}',
        receiptNo: payment['admissionNo'],
        amountPaid: amount.toDouble(),
        paymentDate: payment['paymentDate'],
        paymentMethod: payment['method'],
        paymentFor: payment['paymentFor']?.toString(),
        totalBills: totalBills,
        totalPaid: totalPaid,
        outstanding: outstanding,
      );

      await PrintCounterHelper.incrementReceiptReprintPrinted();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt printed successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing: $e')),
      );
    }
  }

  Future<void> _printReceiptViaUsb(Map<String, dynamic> payment) async {
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
    try {
      if (!mounted) return;
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

      final amount = payment['amount'] as num;
      final schoolName = _school?['name'] ?? "School Name";
      final schoolAddress = _school?['address'] ?? "";
      final studentId = payment['studentId'] as int;

      final term = activeTerm ?? await db.getActiveTerm();
      final session = activeSession ?? (await db.getActiveSession())?['sessionName'];
      final bill = await db.getBillForStudent(studentId, term, session);
      final totalBills = bill != null ? (bill['totalAmount'] as num?)?.toDouble() ?? 0.0 : 0.0;
      final payments = await db.getPayments(studentId, term: term, session: session);
      final totalPaid = payments.fold<double>(0.0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0.0));
      final outstanding = totalBills - totalPaid;

      final paperSize = await UsbPrinterManager.getPaperSizeEnum();

      await UsbPrinterManager.printPaymentReceipt(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        studentName: payment['studentName'],
        studentClass: '${payment['className']} - ${payment['armName']}',
        receiptNumber: payment['admissionNo'],
        amountPaid: amount.toDouble(),
        paymentDate: payment['paymentDate'],
        paymentMethod: payment['method'],
        paymentFor: payment['paymentFor']?.toString(),
        term: term,
        totalBill: totalBills,
        outstanding: outstanding,
        paperSize: paperSize,
      );
      await PrintCounterHelper.incrementReceiptReprintPrinted();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt printed via USB!')));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('USB print error: $e'), backgroundColor: Colors.red));
    }
  }

  // -----------------------------------------------------------
  // EXPORT PDF
  // -----------------------------------------------------------
  Future<void> _exportCustomReportPDF() async {
    if (paymentDetails.isEmpty &&
        expenseDetails.isEmpty &&
        stockSummary.isEmpty &&
        salesDetails.isEmpty &&
        salesDebtors.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export for this date range')),
      );
      return;
    }

    try {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final filePath = await CustomReportPDFGenerator.generateCustomReportPDF(
        startDate: _startDate,
        endDate: _endDate,
        term: activeTerm,
        session: activeSession,
        schoolProfile: _school ?? {},
        cashTotal: cashTotal,
        posTotal: posTotal,
        transferTotal: transferTotal,
        totalIncome: totalIncome,
        paymentDetails: paymentDetails,
        expenseCashTotal: expenseCashTotal,
        expensePosTotal: expensePosTotal,
        expenseTransferTotal: expenseTransferTotal,
        totalExpenses: totalExpenses,
        expenseDetails: expenseDetails,
        stockSummary: stockSummary,
        salesDetails: salesDetails,
        salesDebtors: salesDebtors,
        salesCashTotal: salesCashTotal,
        salesPosTotal: salesPosTotal,
        salesTransferTotal: salesTransferTotal,
        totalSales: totalSales,
        totalSalesDebt: totalSalesDebt,
        includeIncome: _showIncome,
        includePaymentDetails: _showPayments,
        includeExpenses: _showExpenses,
        includeStockAndSales: _showStockSales,
        reportTabLabel: _tabLabels[_reportTab],
      );

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'Custom Report - $_rangeLabel',
        text: 'Custom financial report for $_rangeLabel',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom report PDF exported successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting PDF: $e')),
      );
    }
  }

  // -----------------------------------------------------------
  // UI
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text("Custom Report - $_rangeLabel"),
        backgroundColor: Colors.teal,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(ds.cardPadding),
                child: Column(
                  children: [
                    // Preset selector row
                    Row(
                      children: [
                        Expanded(child: _presetButton('week', 'This Week', Icons.view_week)),
                        SizedBox(width: ds.cardPadding * 0.5),
                        Expanded(child: _presetButton('month', 'This Month', Icons.calendar_view_month)),
                        SizedBox(width: ds.cardPadding * 0.5),
                        Expanded(child: _presetButton('custom', 'Custom Range', Icons.date_range)),
                      ],
                    ),

                    SizedBox(height: ds.cardPadding * 0.75),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_note, color: Colors.teal.shade700, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Period: $_rangeLabel',
                            style: TextStyle(
                              fontSize: ds.bodyFontSize * 0.9,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: ds.cardPadding * 0.75),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: paymentDetails.isNotEmpty ||
                                   expenseDetails.isNotEmpty ||
                                   stockSummary.isNotEmpty ||
                                   salesDetails.isNotEmpty ||
                                   salesDebtors.isNotEmpty
                            ? _exportCustomReportPDF
                            : null,
                        icon: Icon(Icons.picture_as_pdf, size: ds.iconSize),
                        label: Text(
                          'Export PDF',
                          style: TextStyle(fontSize: ds.bodyFontSize, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: ds.cardPadding),
                          elevation: 3,
                        ),
                      ),
                    ),

                    SizedBox(height: ds.cardPadding * 0.75),

                    // REPORT VIEW TABS
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorColor: Colors.teal.shade700,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.teal.shade700,
                        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        indicator: BoxDecoration(
                          color: Colors.teal.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
                      ),
                    ),

                    SizedBox(height: ds.cardPadding * 1.25),

                    // INCOME SUMMARY
                    if (_showIncome) Card(
                      elevation: 4,
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.attach_money, color: Colors.green.shade700, size: 28),
                                const SizedBox(width: 8),
                                const Text(
                                  'INCOME SUMMARY (SCHOOL FEES & OFFICE SALES)',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            _row("Cash Received (School Fees)", "N ${NumberFormat('#,##0.00').format(cashTotal)}"),
                            const SizedBox(height: 5),
                            _row("Cash Received (Office Sales)", "N ${NumberFormat('#,##0.00').format(salesCashTotal)}"),
                            const SizedBox(height: 10),
                            _row("POS Received (School Fees)", "N ${NumberFormat('#,##0.00').format(posTotal)}"),
                            const SizedBox(height: 5),
                            _row("POS Received (Office Sales)", "N ${NumberFormat('#,##0.00').format(salesPosTotal)}"),
                            const SizedBox(height: 10),
                            _row("Transfer Received (School Fees)", "N ${NumberFormat('#,##0.00').format(transferTotal)}"),
                            const SizedBox(height: 5),
                            _row("Transfer Received (Office Sales)", "N ${NumberFormat('#,##0.00').format(salesTransferTotal)}"),
                            const Divider(height: 25),
                            _row(
                              "TOTAL INCOME",
                              "N ${NumberFormat('#,##0.00').format(totalIncome + totalSales)}",
                              bold: true,
                              color: Colors.green.shade800,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // EXPENSES SUMMARY
                    if (_showExpenses) Card(
                      elevation: 4,
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.receipt_long, color: Colors.orange.shade800, size: 28),
                                const SizedBox(width: 8),
                                const Text(
                                  'EXPENSES SUMMARY',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            _row("Cash Paid", "N ${NumberFormat('#,##0.00').format(expenseCashTotal)}"),
                            const SizedBox(height: 10),
                            _row("POS Paid", "N ${NumberFormat('#,##0.00').format(expensePosTotal)}"),
                            const SizedBox(height: 10),
                            _row("Transfers Paid", "N ${NumberFormat('#,##0.00').format(expenseTransferTotal)}"),
                            const Divider(height: 25),
                            _row(
                              "TOTAL EXPENSES",
                              "N ${NumberFormat('#,##0.00').format(totalExpenses)}",
                              bold: true,
                              color: Colors.red.shade800,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // NET INCOME
                    if (_showIncome && _showExpenses) Card(
                      elevation: 5,
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Builder(
                          builder: (context) {
                            final netCash = (cashTotal + salesCashTotal) - expenseCashTotal;
                            final netPos = (posTotal + salesPosTotal) - expensePosTotal;
                            final netTransfer = (transferTotal + salesTransferTotal) - expenseTransferTotal;
                            final netIncome = (totalIncome + totalSales) - totalExpenses;

                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      netIncome >= 0 ? Icons.trending_up : Icons.trending_down,
                                      color: netIncome >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'NET INCOME',
                                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Breakdown',
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                                      ),
                                      const SizedBox(height: 10),
                                      _netBreakdownRow('Total Cash at Hand', '(Cash Income - Cash Expenses)', netCash),
                                      const SizedBox(height: 10),
                                      _netBreakdownRow('Total POS', '(POS Income - POS Expenses)', netPos),
                                      const SizedBox(height: 10),
                                      _netBreakdownRow('Total Transfer', '(Transfer Income - Transfer Expenses)', netTransfer),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 15),
                                const Divider(height: 1),
                                const SizedBox(height: 15),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('NET INCOME', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    Text(
                                      'N ${NumberFormat('#,##0.00').format(netIncome)}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: netIncome >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                    if (_showPayments) ...[

                    const SizedBox(height: 30),

                    // SCHOOL FEES PAYMENT DETAILS Section Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.people, color: Colors.white, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            "SCHOOL FEES PAYMENT DETAILS (${paymentDetails.length})",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    if (paymentDetails.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                "No payments recorded for this period",
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _paymentCategories.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final cats = _paymentCategories;
                            final label = cats[i];
                            final count = i == 0
                                ? paymentDetails.length
                                : paymentDetails
                                    .where((p) => (p['paymentFor'] ?? 'School Fees') == label)
                                    .length;
                            final selected = _paymentTabIndex == i;
                            return GestureDetector(
                              onTap: () => setState(() => _paymentTabIndex = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected ? Colors.green.shade700 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected ? Colors.green.shade700 : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  '$label ($count)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? Colors.white : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Payment method filter tabs (All, Cash, Transfer, POS)
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _methodCategories.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final label = _methodCategories[i];
                            final selected = _methodTabIndex == i;
                            return GestureDetector(
                              onTap: () => setState(() => _methodTabIndex = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected ? Colors.indigo.shade700 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected ? Colors.indigo.shade700 : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? Colors.white : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 10),

                      ..._filteredPayments.asMap().entries.map((entry) {
                        final index = entry.key;
                        final payment = entry.value;
                        final amount = payment['amount'] as num;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: payment['method'] == 'CASH'
                                  ? Colors.green
                                  : payment['method'] == 'POS'
                                      ? Colors.blue
                                      : Colors.orange,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(
                              payment['studentName'],
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${payment['className']} - ${payment['armName']}'),
                                Row(
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 3, right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.green.shade200),
                                      ),
                                      child: Text(
                                        payment['paymentFor'] ?? 'School Fees',
                                        style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                                      ),
                                    ),
                                    Text(
                                      '${payment['method']} • N ${NumberFormat('#,##0.00').format(amount)}',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.print),
                              tooltip: 'Re-print Receipt',
                              onPressed: () => _showReceiptPrintOptions(payment),
                            ),
                            isThreeLine: true,
                          ),
                        );
                      }),

                      _buildTabPaymentBreakdown(_filteredPayments),
                    ],

                    ], // end _showPayments

                    // SALES SUMMARY
                    if (_showStockSales && salesDetails.isNotEmpty) ...[
                      Card(
                        elevation: 4,
                        color: Colors.teal.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.shopping_cart, color: Colors.teal.shade700, size: 24),
                                  const SizedBox(width: 8),
                                  const Text('SALES SUMMARY', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Divider(height: 20),
                              const SizedBox(height: 10),
                              Table(
                                border: TableBorder.all(color: Colors.teal.shade300, width: 1),
                                columnWidths: const {
                                  0: FlexColumnWidth(1),
                                  1: FlexColumnWidth(3),
                                  2: FlexColumnWidth(1.5),
                                  3: FlexColumnWidth(2),
                                  4: FlexColumnWidth(2),
                                  5: FlexColumnWidth(2.5),
                                },
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(color: Colors.teal.shade200),
                                    children: [
                                      _tableCell('S/N', isHeader: true),
                                      _tableCell('Item(s) Sold', isHeader: true),
                                      _tableCell('Qty', isHeader: true),
                                      _tableCell('Payment Status', isHeader: true),
                                      _tableCell('Amount Paid', isHeader: true),
                                      _tableCell('Buyer Details', isHeader: true),
                                    ],
                                  ),
                                  ...salesDetails.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final sale = entry.value;
                                    final items = sale['items'] as List<Map<String, dynamic>>;
                                    final itemsText = items.map((item) {
                                      final isCustom = item['isCustomItem'] == true;
                                      return isCustom
                                          ? '${item['itemName']} [Custom] (x${item['quantity']})'
                                          : '${item['itemName']} (x${item['quantity']})';
                                    }).join(', ');
                                    final totalPaid = (sale['totalPaid'] as num).toDouble();
                                    final totalAmount = (sale['totalAmount'] as num).toDouble();
                                    final outstanding = totalAmount - totalPaid;

                                    String paymentStatus;
                                    if (outstanding <= 0) {
                                      paymentStatus = 'Paid';
                                    } else if (totalPaid > 0) {
                                      paymentStatus = 'Part Payment';
                                    } else {
                                      paymentStatus = 'Unpaid';
                                    }

                                    return TableRow(
                                      children: [
                                        _tableCell('${index + 1}'),
                                        _tableCell(itemsText),
                                        _tableCell('${sale['totalQtySold']}', align: TextAlign.center),
                                        _tableCell(paymentStatus, align: TextAlign.center),
                                        _tableCell('N ${NumberFormat('#,##0.00').format(totalPaid)}', align: TextAlign.right),
                                        _tableCell('${sale['buyerName']} (${sale['buyerType']})'),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],

                    // EXPENSES DETAILS Section Header
                    if (_showExpenses) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade700,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt, color: Colors.white, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            "EXPENSES DETAILS (${expenseDetails.length})",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    if (expenseDetails.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(Icons.check_circle, size: 48, color: Colors.green.shade400),
                              const SizedBox(height: 8),
                              Text(
                                "No expenses recorded for this period",
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...expenseDetails.asMap().entries.map((entry) {
                        final index = entry.key;
                        final expense = entry.value;
                        final amount = expense['amount'] as num;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: expense['method'] == 'CASH'
                                  ? Colors.red.shade300
                                  : expense['method'] == 'POS'
                                      ? Colors.orange.shade300
                                      : Colors.brown.shade300,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(
                              expense['description'],
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${expense['category']} • ${expense['recipient']}'),
                                Text(
                                  '${expense['method']} • N ${NumberFormat('#,##0.00').format(amount)}',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.red.shade700),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      }),

                    ], // end _showExpenses

                    // STOCK & SALES REPORT SECTION
                    if (_showStockSales) ...[

                    const SizedBox(height: 40),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.brown.shade700, Colors.brown.shade500],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2, color: Colors.white, size: 24),
                          const SizedBox(width: 8),
                          const Text(
                            "STOCK & SALES REPORT",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    if (stockSummary.isNotEmpty) ...[
                      Card(
                        elevation: 4,
                        color: Colors.brown.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.inventory, color: Colors.brown.shade700, size: 24),
                                  const SizedBox(width: 8),
                                  const Text('STOCK SUMMARY', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Divider(height: 20),
                              const SizedBox(height: 10),
                              Table(
                                border: TableBorder.all(color: Colors.brown.shade300, width: 1),
                                columnWidths: const {
                                  0: FlexColumnWidth(1),
                                  1: FlexColumnWidth(3),
                                  2: FlexColumnWidth(2),
                                  3: FlexColumnWidth(2),
                                  4: FlexColumnWidth(2),
                                },
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(color: Colors.brown.shade200),
                                    children: [
                                      _tableCell('S/N', isHeader: true),
                                      _tableCell('Item Name', isHeader: true),
                                      _tableCell('Total in Stock', isHeader: true),
                                      _tableCell('Qty Sold', isHeader: true),
                                      _tableCell('Qty Remain', isHeader: true),
                                    ],
                                  ),
                                  ...stockSummary.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final item = entry.value;
                                    return TableRow(
                                      children: [
                                        _tableCell('${index + 1}'),
                                        _tableCell(item['itemName']),
                                        _tableCell('${item['beginningQuantity']}', align: TextAlign.center),
                                        _tableCell('${item['qtySold']}', align: TextAlign.center),
                                        _tableCell('${item['remainingQuantity']}', align: TextAlign.center),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (salesDebtors.isNotEmpty) ...[
                      Card(
                        elevation: 4,
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.account_balance_wallet, color: Colors.red.shade700, size: 24),
                                  const SizedBox(width: 8),
                                  const Text('SALES DEBTORS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Divider(height: 20),
                              const SizedBox(height: 10),
                              Table(
                                border: TableBorder.all(color: Colors.red.shade300, width: 1),
                                columnWidths: const {
                                  0: FlexColumnWidth(1),
                                  1: FlexColumnWidth(2.5),
                                  2: FlexColumnWidth(3),
                                  3: FlexColumnWidth(2),
                                  4: FlexColumnWidth(2),
                                  5: FlexColumnWidth(2),
                                },
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(color: Colors.red.shade200),
                                    children: [
                                      _tableCell('S/N', isHeader: true),
                                      _tableCell('Name of Debtor', isHeader: true),
                                      _tableCell('Item(s) Purchased', isHeader: true),
                                      _tableCell('Total Amount', isHeader: true),
                                      _tableCell('Total Paid', isHeader: true),
                                      _tableCell('Outstanding', isHeader: true),
                                    ],
                                  ),
                                  ...salesDebtors.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final debtor = entry.value;
                                    return TableRow(
                                      children: [
                                        _tableCell('${index + 1}'),
                                        _tableCell('${debtor['buyerName']} (${debtor['buyerType']})'),
                                        _tableCell(debtor['itemsPurchased']),
                                        _tableCell('N ${NumberFormat('#,##0.00').format(debtor['totalAmount'])}', align: TextAlign.right),
                                        _tableCell('N ${NumberFormat('#,##0.00').format(debtor['totalPaid'])}', align: TextAlign.right),
                                        _tableCell('N ${NumberFormat('#,##0.00').format(debtor['outstandingBalance'])}', align: TextAlign.right),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                              const SizedBox(height: 15),
                              const Divider(height: 25),
                              _row(
                                "TOTAL SALES DEBT",
                                "N ${NumberFormat('#,##0.00').format(totalSalesDebt)}",
                                bold: true,
                                color: Colors.red.shade800,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (stockSummary.isEmpty && salesDetails.isEmpty && salesDebtors.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.inventory_2, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                "No stock or sales data for this period",
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ),

                    ], // end _showStockSales
                  ],
                ),
              ),
            ),
    );
  }

  Widget _presetButton(String preset, String label, IconData icon) {
    final selected = _activePreset == preset;
    return ElevatedButton.icon(
      onPressed: () => _applyPreset(preset),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.teal : Colors.grey.shade200,
        foregroundColor: selected ? Colors.white : Colors.grey.shade800,
        padding: const EdgeInsets.symmetric(vertical: 12),
        elevation: selected ? 3 : 0,
      ),
    );
  }

  Widget _netBreakdownRow(String label, String sublabel, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            Text(sublabel, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        Text(
          'N ${NumberFormat('#,##0.00').format(amount)}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: amount >= 0 ? Colors.green.shade700 : Colors.red.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildTabPaymentBreakdown(List<Map<String, dynamic>> payments) {
    double cash = 0, pos = 0, transfer = 0;
    for (final p in payments) {
      final amount = (p['amount'] as num).toDouble();
      final method = (p['method'] as String).toUpperCase();
      if (method == 'CASH') {
        cash += amount;
      } else if (method == 'POS') {
        pos += amount;
      } else {
        transfer += amount;
      }
    }
    final total = cash + pos + transfer;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.shade700,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: const Text(
              'PAYMENT METHOD BREAKDOWN',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _breakdownChip(Icons.money, 'Cash', cash, Colors.green.shade700),
                const SizedBox(width: 8),
                _breakdownChip(Icons.swap_horiz, 'Transfer', transfer, Colors.orange.shade700),
                const SizedBox(width: 8),
                _breakdownChip(Icons.credit_card, 'POS', pos, Colors.blue.shade700),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('TOTAL', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      'N ${NumberFormat('#,##0.00').format(total)}',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownChip(IconData icon, String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'N ${NumberFormat('#,##0.00').format(amount)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _tableCell(String text, {bool isHeader = false, TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: isHeader ? 13.0 : 12.0,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? Colors.black87 : Colors.black,
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color color = Colors.black}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        Text(
          value,
          style: TextStyle(fontSize: 17, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color),
        ),
      ],
    );
  }
}
