import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/thermal_printer_manager.dart';
import '../../utils/usb_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../screens/settings/thermal_printer_screen.dart';
import '../../screens/settings/usb_printer_screen.dart';
import '../../screens/payments/payment_receipt_screen.dart';

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  DailyReportScreenState createState() => DailyReportScreenState();
}

class DailyReportScreenState extends State<DailyReportScreen>
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

  DateTime selectedDate = DateTime.now();

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
    _loadCurrentUser();
    _loadDailyReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  // -----------------------------------------------------------
  // LOAD DAILY REPORT
  // -----------------------------------------------------------
  Future<void> _loadDailyReport() async {
    if (!mounted) return;

    setState(() => loading = true);

    // Load active term and session
    activeTerm = await db.getActiveTerm();
    activeSession = (await db.getActiveSession())?['sessionName'];
    _school = await db.getSchoolProfile();

    final dateStr = _formatDate(selectedDate);

    // Get payments with student details using JOIN
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
      WHERE p.paymentDate LIKE ?
      ORDER BY p.paymentDate DESC
    ''', ['%$dateStr%']);

    // Reset totals
    cashTotal = 0;
    posTotal = 0;
    transferTotal = 0;
    paymentDetails = [];
    _paymentTabIndex = 0;
    _methodTabIndex = 0;

    for (var p in raw) {
      // Filter by active term and session
      final paymentTerm = p['term']?.toString() ?? '';
      final paymentSession = p['session']?.toString() ?? '';

      // Only include payments from active term/session
      if (activeTerm != null && activeSession != null) {
        if (paymentTerm != activeTerm || paymentSession != activeSession) {
          continue; // Skip this payment
        }
      }

      final method = (p['method'] ?? '').toString().toUpperCase();
      final amount = (p['amount'] is num)
          ? p['amount'] as num
          : double.tryParse(p['amount'].toString()) ?? 0.0;

      // Add to payment details list
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

    // Load expenses for the same date
    // Reset expense totals first
    expenseCashTotal = 0;
    expensePosTotal = 0;
    expenseTransferTotal = 0;
    expenseDetails = [];
    expenseCategoryTotals = {};

    try {
      final expensesRaw = await database.rawQuery('''
        SELECT * FROM expenses
        WHERE expenseDate LIKE ?
        ORDER BY expenseDate DESC
      ''', ['%$dateStr%']);

      for (var e in expensesRaw) {
      // Filter by active term and session
      final expenseTerm = e['term']?.toString() ?? '';
      final expenseSession = e['session']?.toString() ?? '';

      if (activeTerm != null && activeSession != null) {
        if (expenseTerm != activeTerm || expenseSession != activeSession) {
          continue; // Skip this expense
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

      // Add to expense details list
      expenseDetails.add({
        'description': e['description'],
        'category': displayCategory,
        'recipient': e['recipient'],
        'method': method,
        'amount': amount,
        'expenseDate': e['expenseDate'],
      });

      // Track by payment method
      if (method == 'CASH') {
        expenseCashTotal += amount;
      } else if (method == 'POS') {
        expensePosTotal += amount;
      } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
        expenseTransferTotal += amount;
      }

      // Track by category
      expenseCategoryTotals[displayCategory] =
          (expenseCategoryTotals[displayCategory] ?? 0) + amount;
      }

      totalExpenses = expenseCashTotal + expensePosTotal + expenseTransferTotal;
    } catch (e) {
      // If expenses table doesn't exist yet or there's an error, just continue without expenses
      print('Error loading expenses: $e');
      totalExpenses = 0;
    }

    // Load Stock & Sales data
    try {
      // Reset stock & sales totals
      salesCashTotal = 0;
      salesPosTotal = 0;
      salesTransferTotal = 0;
      totalSales = 0;
      totalSalesDebt = 0;
      salesDetails = [];
      stockSummary = [];
      salesDebtors = [];

      // Get all sales for the selected date
      // Only include ORIGINAL sales (quantity > 0), exclude payment receipts (quantity = 0)
      // Use LEFT JOIN to include custom items (stockItemId = 0)
      final salesRaw = await database.rawQuery('''
        SELECT
          s.*,
          COALESCE(si.itemName, s.itemName) as itemName,
          si.costPrice,
          si.currentQuantity as currentStockQuantity
        FROM sales s
        LEFT JOIN stock_items si ON s.stockItemId = si.id AND s.stockItemId > 0
        WHERE s.saleDate LIKE ?
        ORDER BY s.saleDate DESC
      ''', ['%$dateStr%']);

      // Group sales by buyer for sales summary
      Map<String, Map<String, dynamic>> salesByBuyer = {};
      Map<int, Map<String, dynamic>> stockMovement = {};

      for (var sale in salesRaw) {
        // Filter by active term and session
        final saleTerm = sale['term']?.toString() ?? '';
        final saleSession = sale['session']?.toString() ?? '';

        if ((activeTerm?.isNotEmpty ?? false) &&
            (activeSession?.isNotEmpty ?? false)) {
          if (saleTerm != activeTerm || saleSession != activeSession) {
            continue; // Skip this sale
          }
        }

        final qty = (sale['quantity'] as int);

        // Skip payment receipts (quantity = 0)
        if (qty == 0) continue;

        final method = (sale['paymentMethod'] ?? '').toString().toUpperCase();
        final totalAmount = (sale['totalAmount'] as num).toDouble();
        final amountPaid = (sale['amountPaid'] as num).toDouble();
        final paymentStatus = sale['paymentStatus']?.toString() ?? 'Unpaid';
        final stockItemId = sale['stockItemId'] as int;
        final itemName = sale['itemName']?.toString() ?? 'Unknown Item';
        final buyerName = sale['buyerName']?.toString() ?? 'Unknown';
        final buyerType = sale['buyerType']?.toString() ?? '';
        final costPrice = (sale['costPrice'] as num?)?.toDouble() ?? 0.0;
        final currentStockQty = (sale['currentStockQuantity'] as int?) ?? 0;

        // Check if this is a custom item (stockItemId = 0 or isCustomItem = 1)
        final isCustomItem = sale['isCustomItem'] == 1 || stockItemId == 0;

        // Track sales by buyer for sales summary
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

        // Track stock movement for stock summary (only for non-custom items)
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

        // Calculate sales payment breakdown
        if (method == 'CASH') {
          salesCashTotal += amountPaid;
        } else if (method == 'POS') {
          salesPosTotal += amountPaid;
        } else if (method == 'TRANSFER' || method == 'BANK TRANSFER') {
          salesTransferTotal += amountPaid;
        }

        totalSales += amountPaid;
      }

      // Convert sales by buyer to list
      salesDetails = salesByBuyer.values.toList();

      // Prepare stock summary - SHOW ALL STOCK ITEMS (not just those with sales)
      final allStockItems = await database.query('stock_items', orderBy: 'itemName');

      stockSummary = allStockItems.map((stockItem) {
        final stockItemId = stockItem['id'] as int;
        final itemName = stockItem['itemName']?.toString() ?? 'Unknown';
        final currentQty = (stockItem['currentQuantity'] as int?) ?? 0;

        // Check if this item has sales in the selected period
        final qtySold = stockMovement.containsKey(stockItemId)
            ? (stockMovement[stockItemId]!['qtySold'] as int)
            : 0;

        final beginningQty = currentQty + qtySold; // Current stock + what was sold = beginning stock

        return {
          'itemName': itemName,
          'beginningQuantity': beginningQty,
          'qtySold': qtySold,
          'remainingQuantity': currentQty,
        };
      }).toList();

      // Load sales debtors for the selected date
      // Get all debtors who made purchases on the selected date
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
        WHERE s.saleDate LIKE ? AND s.quantity > 0 AND sd.outstandingBalance > 0
      ''', ['%$dateStr%']);

      // Process debtors data
      for (var debtor in debtorsRaw) {
        final buyerName = debtor['buyerName']?.toString() ?? 'Unknown';
        final buyerType = debtor['buyerType']?.toString() ?? '';

        // Get items purchased by this debtor on the selected date
        // Use LEFT JOIN to include custom items (stockItemId = 0)
        final debtorSalesRaw = await database.rawQuery('''
          SELECT COALESCE(si.itemName, s.itemName) as itemName, s.quantity, s.stockItemId, s.isCustomItem
          FROM sales s
          LEFT JOIN stock_items si ON s.stockItemId = si.id AND s.stockItemId > 0
          WHERE s.buyerName = ? AND s.buyerType = ? AND s.saleDate LIKE ? AND s.quantity > 0
        ''', [buyerName, buyerType, '%$dateStr%']);

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

  // Returns ["All", ...unique paymentFor values in order of appearance]
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

  // -----------------------------------------------------------
  // PICK DATE
  // -----------------------------------------------------------
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
      await _loadDailyReport();
    }
  }

  // -----------------------------------------------------------
  // SHOW RECEIPT EXPORT OPTIONS (PDF / JPEG / Thermal)
  // -----------------------------------------------------------
  Future<void> _showReceiptPrintOptions(Map<String, dynamic> payment) async {
    final paymentId = payment['paymentId'] as int?;
    final studentId = payment['studentId'] as int?;

    // If we have a paymentId + studentId, navigate directly to PaymentReceiptScreen
    // which has full PDF, JPEG, and Thermal export built-in
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

    // Fallback: show simple thermal-only dialog if IDs are missing
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

  List<pw.Widget> _buildPaymentCategoriesPdf() {
    // Group payments by paymentFor, preserving insertion order
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final p in paymentDetails) {
      final cat = p['paymentFor']?.toString() ?? 'School Fees';
      (grouped[cat] ??= []).add(p);
    }

    final widgets = <pw.Widget>[];
    grouped.forEach((category, payments) {
      final categoryTotal = payments.fold<double>(
        0, (sum, p) => sum + ((p['amount'] as num).toDouble()));

      widgets.add(pw.SizedBox(height: 10));
      widgets.add(pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            category.toUpperCase(),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.green800),
          ),
          pw.Text(
            '${payments.length} transaction(s) — Total: N ${NumberFormat('#,##0.00').format(categoryTotal)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerLeft,
          3: pw.Alignment.center,
          4: pw.Alignment.centerRight,
        },
        data: [
          ['Student Name', 'Adm No', 'Class/Arm', 'Method', 'Amount (N)'],
          ...payments.map((p) {
            final amount = p['amount'] as num;
            return [
              p['studentName'],
              p['admissionNo'],
              '${p['className']} - ${p['armName']}',
              p['method'],
              NumberFormat('#,##0.00').format(amount),
            ];
          }),
        ],
      ));

      // Payment method breakdown for this category
      double catCash = 0, catPos = 0, catTransfer = 0;
      for (final p in payments) {
        final amt = (p['amount'] as num).toDouble();
        final m = (p['method'] as String).toUpperCase();
        if (m == 'CASH') {
          catCash += amt;
        } else if (m == 'POS') {
          catPos += amt;
        } else {
          catTransfer += amt;
        }
      }

      widgets.add(pw.SizedBox(height: 6));
      widgets.add(pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.green50,
          border: pw.Border.all(color: PdfColors.green300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _pdfBreakdownCell('Cash', catCash, PdfColors.green800),
            _pdfBreakdownCell('Transfer', catTransfer, PdfColors.orange800),
            _pdfBreakdownCell('POS', catPos, PdfColors.blue800),
            pw.Container(width: 1, height: 30, color: PdfColors.grey400),
            _pdfBreakdownCell('TOTAL', categoryTotal, PdfColors.black, bold: true),
          ],
        ),
      ));
      widgets.add(pw.SizedBox(height: 14));
    });

    return widgets;
  }

  pw.Widget _pdfBreakdownCell(String label, double amount, PdfColor color, {bool bold = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'N ${NumberFormat('#,##0.00').format(amount)}',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
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
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blue100),
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

  // -----------------------------------------------------------
  // PRINT RECEIPT VIA THERMAL PRINTER
  // -----------------------------------------------------------
  Future<void> _printReceiptThermal(Map<String, dynamic> payment) async {
    if (!ThermalPrinterManager.isConnected) {
      if (!mounted) return;

      // Show message and navigate to printer connection screen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to a thermal printer first'),
          duration: Duration(seconds: 2),
        ),
      );

      // Navigate to thermal printer connection screen
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ThermalPrinterScreen()),
      );

      // Check again if printer is connected after returning
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

      // Fetch financial summary
      final term = activeTerm ?? await db.getActiveTerm();
      final session = activeSession ?? (await db.getActiveSession())?['sessionName'];

      // Get student's bill for this term/session
      final bill = await db.getBillForStudent(studentId, term, session);
      final totalBills = bill != null ? (bill['totalAmount'] as num?)?.toDouble() ?? 0.0 : 0.0;

      // Get all payments for this student in this term/session
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

      // Increment receipt reprint counter
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

  // -----------------------------------------------------------
  // PRINT RECEIPT VIA USB PRINTER
  // -----------------------------------------------------------
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
  // EXPORT DAILY REPORT AS PDF
  // -----------------------------------------------------------
  Future<void> _exportDailyReportPDF() async {
    if (paymentDetails.isEmpty &&
        expenseDetails.isEmpty &&
        stockSummary.isEmpty &&
        salesDetails.isEmpty &&
        salesDebtors.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export for this date')),
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

      final pdf = pw.Document();

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
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo700),
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
                  'DAILY FINANCIAL REPORT',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'Date: ${DateFormat('EEEE, MMMM d, yyyy').format(selectedDate)}',
                  style: const pw.TextStyle(fontSize: 14),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Term: $activeTerm | Session: $activeSession',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 20),

              // INCOME Section
              pw.Text(
                'INCOME',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.green700),
              ),
              pw.SizedBox(height: 10),

              // Income Summary Box (School Fees & Office Sales)
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.green400),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('INCOME SUMMARY (SCHOOL FEES & OFFICE SALES)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Cash Received (School Fees):', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N ${NumberFormat('#,##0.00').format(cashTotal)}', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Cash Received (Office Sales):', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N ${NumberFormat('#,##0.00').format(salesCashTotal)}', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('POS Received (School Fees):', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N ${NumberFormat('#,##0.00').format(posTotal)}', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('POS Received (Office Sales):', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N ${NumberFormat('#,##0.00').format(salesPosTotal)}', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Transfer Received (School Fees):', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N ${NumberFormat('#,##0.00').format(transferTotal)}', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Transfer Received (Office Sales):', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('N ${NumberFormat('#,##0.00').format(salesTransferTotal)}', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('TOTAL INCOME:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                        pw.Text('N ${NumberFormat('#,##0.00').format(totalIncome + totalSales)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.green)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // School Fees Payment Details — grouped by Payment For
              pw.Text(
                'SCHOOL FEES PAYMENT DETAILS (${paymentDetails.length} transactions)',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),

              // Build one table per category
              ..._buildPaymentCategoriesPdf(),

              pw.SizedBox(height: 30),

              // SALES SUMMARY (Moved from Stock & Sales Report Section)
              if (salesDetails.isNotEmpty) ...[
                pw.Text(
                  'SALES SUMMARY',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700),
                ),
                pw.SizedBox(height: 10),

                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.teal200),
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.center,
                    3: pw.Alignment.center,
                    4: pw.Alignment.centerRight,
                    5: pw.Alignment.centerLeft,
                  },
                  data: [
                    ['S/N', 'Item(s) Sold', 'Qty', 'Payment Status', 'Amount Paid', 'Buyer Details'],
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

                      return [
                        '${index + 1}',
                        itemsText,
                        '${sale['totalQtySold']}',
                        paymentStatus,
                        'N ${NumberFormat('#,##0.00').format(totalPaid)}',
                        '${sale['buyerName']} (${sale['buyerType']})',
                      ];
                    }),
                  ],
                ),

                pw.SizedBox(height: 30),
              ],

              // EXPENSES Section
              if (expenseDetails.isNotEmpty) ...[
                pw.Text(
                  'EXPENSES',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800),
                ),
                pw.SizedBox(height: 10),

                // Expenses Summary Box
                pw.Container(
                  padding: const pw.EdgeInsets.all(15),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.orange400),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('EXPENSES SUMMARY',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                      pw.SizedBox(height: 10),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Cash Paid:', style: const pw.TextStyle(fontSize: 12)),
                          pw.Text('N ${NumberFormat('#,##0.00').format(expenseCashTotal)}',
                              style: const pw.TextStyle(fontSize: 12)),
                        ],
                      ),
                      pw.SizedBox(height: 5),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('POS Paid:', style: const pw.TextStyle(fontSize: 12)),
                          pw.Text('N ${NumberFormat('#,##0.00').format(expensePosTotal)}',
                              style: const pw.TextStyle(fontSize: 12)),
                        ],
                      ),
                      pw.SizedBox(height: 5),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Transfers Paid:', style: const pw.TextStyle(fontSize: 12)),
                          pw.Text('N ${NumberFormat('#,##0.00').format(expenseTransferTotal)}',
                              style: const pw.TextStyle(fontSize: 12)),
                        ],
                      ),
                      pw.Divider(),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('TOTAL EXPENSES:',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                          pw.Text('N ${NumberFormat('#,##0.00').format(totalExpenses)}',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.red)),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 20),

                // Expenses Details
                pw.Text(
                  'EXPENSES DETAILS (${expenseDetails.length} transactions)',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),

                // Expenses Details Table
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.orange100),
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerLeft,
                    3: pw.Alignment.center,
                    4: pw.Alignment.centerRight,
                  },
                  data: [
                    ['Description', 'Category', 'Recipient', 'Method', 'Amount (N)'],
                    ...expenseDetails.map((e) {
                      final amount = e['amount'] as num;
                      return [
                        e['description'],
                        e['category'],
                        e['recipient'],
                        e['method'],
                        NumberFormat('#,##0.00').format(amount),
                      ];
                    }),
                  ],
                ),

                pw.SizedBox(height: 30),
              ],

              // Net Income
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue400, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('NET INCOME (Income - Expenses):',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                    pw.Text('N ${NumberFormat('#,##0.00').format((totalIncome + totalSales) - totalExpenses)}',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 16,
                            color: ((totalIncome + totalSales) - totalExpenses) >= 0 ? PdfColors.green : PdfColors.red)),
                  ],
                ),
              ),

              pw.SizedBox(height: 40),

              // STOCK & SALES REPORT SECTION
              if (stockSummary.isNotEmpty || salesDetails.isNotEmpty || salesDebtors.isNotEmpty) ...[
                pw.Divider(),
                pw.SizedBox(height: 20),

                // Section Title
                pw.Text(
                  'STOCK & SALES REPORT',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.brown700),
                ),
                pw.SizedBox(height: 20),

                // STOCK SUMMARY
                if (stockSummary.isNotEmpty) ...[
                  pw.Text(
                    'STOCK SUMMARY',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.brown700),
                  ),
                  pw.SizedBox(height: 10),

                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                    cellStyle: const pw.TextStyle(fontSize: 9),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.brown200),
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.center,
                      3: pw.Alignment.center,
                      4: pw.Alignment.center,
                    },
                    data: [
                      ['S/N', 'Item Name', 'Total in Stock', 'Qty Sold', 'Qty Remain'],
                      ...stockSummary.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return [
                          '${index + 1}',
                          item['itemName'],
                          '${item['beginningQuantity']}',
                          '${item['qtySold']}',
                          '${item['remainingQuantity']}',
                        ];
                      }),
                    ],
                  ),

                  pw.SizedBox(height: 20),
                ],

                // SALES DEBTORS
                if (salesDebtors.isNotEmpty) ...[
                  pw.Text(
                    'SALES DEBTORS',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red700),
                  ),
                  pw.SizedBox(height: 10),

                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                    cellStyle: const pw.TextStyle(fontSize: 8),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.red200),
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.centerLeft,
                      3: pw.Alignment.centerRight,
                      4: pw.Alignment.centerRight,
                      5: pw.Alignment.centerRight,
                    },
                    data: [
                      ['S/N', 'Name of Debtor', 'Item(s) Purchased', 'Total Amount', 'Total Paid', 'Outstanding'],
                      ...salesDebtors.asMap().entries.map((entry) {
                        final index = entry.key;
                        final debtor = entry.value;
                        return [
                          '${index + 1}',
                          '${debtor['buyerName']} (${debtor['buyerType']})',
                          debtor['itemsPurchased'],
                          'N ${NumberFormat('#,##0.00').format(debtor['totalAmount'])}',
                          'N ${NumberFormat('#,##0.00').format(debtor['totalPaid'])}',
                          'N ${NumberFormat('#,##0.00').format(debtor['outstandingBalance'])}',
                        ];
                      }),
                    ],
                  ),

                  pw.SizedBox(height: 15),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.red400),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('TOTAL SALES DEBT:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                        pw.Text('N ${NumberFormat('#,##0.00').format(totalSalesDebt)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.red)),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 20),
                ],
              ],

              // Bank Account Details
              ..._buildBankDetailsPdf(),

              // Footer
              pw.SizedBox(height: 30),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text(
                'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ];
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
      final file = File('${dir.path}/daily_report_$dateStr.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      Navigator.pop(context);

      // Build share message
      String shareMessage = 'Daily Financial Report for $dateStr\n';
      shareMessage += '${paymentDetails.length} payment transactions, N ${totalIncome.toStringAsFixed(2)} total income\n';
      if (expenseDetails.isNotEmpty) {
        shareMessage += '${expenseDetails.length} expense transactions, N ${totalExpenses.toStringAsFixed(2)} total expenses\n';
      }
      if (salesDetails.isNotEmpty || stockSummary.isNotEmpty) {
        shareMessage += 'Includes Stock & Sales Report with ${stockSummary.length} items and ${salesDetails.length} sales';
      }

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Daily Financial Report - $dateStr',
        text: shareMessage,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily report PDF exported successfully!')),
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
        title: Text("Daily Report - ${_formatDate(selectedDate)}"),
        backgroundColor: Colors.indigo,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(ds.cardPadding),
                child: Column(
                  children: [
                  // Action Buttons Row
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pickDate,
                          icon: Icon(Icons.calendar_today, size: ds.iconSize),
                          label: Text(
                            'Select Date',
                            style: TextStyle(fontSize: ds.bodyFontSize, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: ds.cardPadding),
                            elevation: 3,
                          ),
                        ),
                      ),
                      SizedBox(width: ds.cardPadding * 0.75),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: paymentDetails.isNotEmpty ||
                                     expenseDetails.isNotEmpty ||
                                     stockSummary.isNotEmpty ||
                                     salesDetails.isNotEmpty ||
                                     salesDebtors.isNotEmpty
                              ? _exportDailyReportPDF
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
                    ],
                  ),

                  SizedBox(height: ds.cardPadding * 0.75),

                  // REPORT VIEW TABS
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorColor: Colors.indigo.shade700,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.indigo.shade700,
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      indicator: BoxDecoration(
                        color: Colors.indigo.shade700,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
                    ),
                  ),

                  SizedBox(height: ds.cardPadding * 1.25),

                  // INCOME SUMMARY (SCHOOL FEES & OFFICE SALES)
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
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          _row("Cash Received (School Fees)", "N ${NumberFormat('#,##0.00').format(cashTotal)}"),
                          const SizedBox(height: 5),
                          _row("Cash Received (Office Sales)", "₦${NumberFormat('#,##0.00').format(salesCashTotal)}"),
                          const SizedBox(height: 10),
                          _row("POS Received (School Fees)", "N ${NumberFormat('#,##0.00').format(posTotal)}"),
                          const SizedBox(height: 5),
                          _row("POS Received (Office Sales)", "₦${NumberFormat('#,##0.00').format(salesPosTotal)}"),
                          const SizedBox(height: 10),
                          _row("Transfer Received (School Fees)", "N ${NumberFormat('#,##0.00').format(transferTotal)}"),
                          const SizedBox(height: 5),
                          _row("Transfer Received (Office Sales)", "₦${NumberFormat('#,##0.00').format(salesTransferTotal)}"),
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
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
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
                          // Calculate net amounts by payment method
                          final netCash = (cashTotal + salesCashTotal) - expenseCashTotal;
                          final netPos = (posTotal + salesPosTotal) - expensePosTotal;
                          final netTransfer = (transferTotal + salesTransferTotal) - expenseTransferTotal;
                          final netIncome = (totalIncome + totalSales) - totalExpenses;

                          return Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    netIncome >= 0
                                        ? Icons.trending_up
                                        : Icons.trending_down,
                                    color: netIncome >= 0
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'NET INCOME',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),

                              // Breakdown Section
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
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // Total Cash at Hand
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Total Cash at Hand',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              '(Cash Income - Cash Expenses)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'N ${NumberFormat('#,##0.00').format(netCash)}',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: netCash >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),

                                    // Total POS
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Total POS',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              '(POS Income - POS Expenses)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'N ${NumberFormat('#,##0.00').format(netPos)}',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: netPos >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),

                                    // Total Transfer
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Total Transfer',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              '(Transfer Income - Transfer Expenses)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'N ${NumberFormat('#,##0.00').format(netTransfer)}',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: netTransfer >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 15),
                              const Divider(height: 1),
                              const SizedBox(height: 15),

                              // NET INCOME Total
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'NET INCOME',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'N ${NumberFormat('#,##0.00').format(netIncome)}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: netIncome >= 0
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
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

                  const SizedBox(height: 30),

                  if (_showPayments) ...[

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
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
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
                              "No payments recorded for this date",
                              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    // Tab selector (scrollable row of chips)
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

                    // Payment list for selected tab
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
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey.shade700,
                                    ),
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

                    // Payment method breakdown for the current tab
                    _buildTabPaymentBreakdown(_filteredPayments),
                  ],

                  ], // end _showPayments

                  const SizedBox(height: 30),

                  // SALES SUMMARY (Moved from Stock & Sales Report Section)
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
                                const Text(
                                  'SALES SUMMARY',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            const SizedBox(height: 10),

                            // Sales Summary Table
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
                                // Header Row
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
                                // Data Rows
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
                                      _tableCell('₦${NumberFormat('#,##0.00').format(totalPaid)}', align: TextAlign.right),
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

                  if (_showExpenses) ...[

                  // EXPENSES DETAILS Section Header
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
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Expense List
                  if (expenseDetails.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.check_circle, size: 48, color: Colors.green.shade400),
                            const SizedBox(height: 8),
                            Text(
                              "No expenses recorded for this date",
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
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }),

                  ], // end _showExpenses

                  const SizedBox(height: 40),

                  // ===============================================
                  // STOCK & SALES REPORT SECTION
                  // ===============================================

                  if (_showStockSales) ...[

                  // Section Title
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // STOCK SUMMARY
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
                                const Text(
                                  'STOCK SUMMARY',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            const SizedBox(height: 10),

                            // Stock Summary Table
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
                                // Header Row
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
                                // Data Rows
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


                  // SALES DEBTORS
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
                                const Text(
                                  'SALES DEBTORS',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            const SizedBox(height: 10),

                            // Sales Debtors Table
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
                                // Header Row
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
                                // Data Rows
                                ...salesDebtors.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final debtor = entry.value;
                                  return TableRow(
                                    children: [
                                      _tableCell('${index + 1}'),
                                      _tableCell('${debtor['buyerName']} (${debtor['buyerType']})'),
                                      _tableCell(debtor['itemsPurchased']),
                                      _tableCell('₦${NumberFormat('#,##0.00').format(debtor['totalAmount'])}', align: TextAlign.right),
                                      _tableCell('₦${NumberFormat('#,##0.00').format(debtor['totalPaid'])}', align: TextAlign.right),
                                      _tableCell('₦${NumberFormat('#,##0.00').format(debtor['outstandingBalance'])}', align: TextAlign.right),
                                    ],
                                  );
                                }),
                              ],
                            ),

                            const SizedBox(height: 15),
                            const Divider(height: 25),
                            _row(
                              "TOTAL SALES DEBT",
                              "₦${NumberFormat('#,##0.00').format(totalSalesDebt)}",
                              bold: true,
                              color: Colors.red.shade800,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Show message if no stock/sales data
                  if (stockSummary.isEmpty && salesDetails.isEmpty && salesDebtors.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.inventory_2, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              "No stock or sales data for this date",
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

  // -----------------------------------------------------------
  // PAYMENT METHOD BREAKDOWN FOR A TAB
  // -----------------------------------------------------------
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
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
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
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
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

  // -----------------------------------------------------------
  // TABLE CELL BUILDER
  // -----------------------------------------------------------
  Widget _tableCell(String text, {bool isHeader = false, TextAlign align = TextAlign.left, DisplaySettings? ds}) {
    final fontSize = ds != null
        ? (isHeader ? ds.subtitleFontSize : ds.subtitleFontSize * 0.9)
        : (isHeader ? 13.0 : 12.0);
    return Padding(
      padding: EdgeInsets.all(ds?.cardPadding ?? 8.0 * 0.5),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? Colors.black87 : Colors.black,
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // ROW BUILDER
  // -----------------------------------------------------------
  Widget _row(
    String label,
    String value, {
    bool bold = false,
    Color color = Colors.black,
    DisplaySettings? ds,
  }) {
    final labelFontSize = ds?.bodyFontSize ?? 16.0;
    final valueFontSize = ds?.titleFontSize ?? 17.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: labelFontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: valueFontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}
