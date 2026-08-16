import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UsbPrinterManager {
  static final FlutterUsbPrinter _printer = FlutterUsbPrinter();
  static Map<String, dynamic>? _connectedDevice;

  static const String _paperSizeKey = 'usb_printer_paper_size';

  // ── State ──────────────────────────────────────────────────────────────────

  static Map<String, dynamic>? get connectedDevice => _connectedDevice;
  static bool get isConnected => _connectedDevice != null;

  // ── Device discovery ───────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getDevices() async {
    try {
      final devices = await FlutterUsbPrinter.getUSBDeviceList();
      return devices ?? [];
    } catch (e) {
      debugPrint('UsbPrinterManager: error listing devices: $e');
      return [];
    }
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  static Future<bool> connect(Map<String, dynamic> device) async {
    try {
      final vendorId = int.tryParse(device['vendorId']?.toString() ?? '') ?? 0;
      final productId = int.tryParse(device['productId']?.toString() ?? '') ?? 0;
      final result = await _printer.connect(vendorId, productId);
      if (result == true) {
        _connectedDevice = device;
        debugPrint('UsbPrinterManager: connected to ${device['productName']}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('UsbPrinterManager: connect error: $e');
      return false;
    }
  }

  static Future<void> disconnect() async {
    try {
      await _printer.close();
    } catch (e) {
      debugPrint('UsbPrinterManager: disconnect error: $e');
    } finally {
      _connectedDevice = null;
    }
  }

  // ── Paper size persistence ─────────────────────────────────────────────────

  static Future<String> getPaperSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_paperSizeKey) ?? 'mm80';
  }

  static Future<void> setPaperSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paperSizeKey, size);
  }

  static Future<PaperSize> getPaperSizeEnum() async {
    final s = await getPaperSize();
    return s == 'mm58' ? PaperSize.mm58 : PaperSize.mm80;
  }

  // ── Raw write ──────────────────────────────────────────────────────────────

  static Future<void> _send(List<int> bytes) async {
    if (_connectedDevice == null) throw Exception('No USB printer connected');
    await _printer.write(Uint8List.fromList(bytes));
  }

  // ── Formatting helpers ─────────────────────────────────────────────────────

  static String _amt(double v) => NumberFormat('#,##0.00').format(v);
  static String _fmtInt(double v) => NumberFormat('#,##0').format(v);

  // Chars per line for the default font, per paper size (see esc_pos_utils Generator._getMaxCharsPerLine)
  static int _charsPerLine(PaperSize paperSize) {
    if (paperSize == PaperSize.mm58) return 32;
    if (paperSize == PaperSize.mm72) return 42;
    return 48;
  }

  // Truncate text to fit a column so long names never wrap and break row alignment
  static String _fitToWidth(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    if (maxChars <= 1) return text.substring(0, maxChars);
    return '${text.substring(0, maxChars - 1)}.';
  }

  static List<int> _phoneLine(Generator g, String? phone) {
    if (phone == null || phone.isEmpty) return [];
    return g.text('Tel: $phone', styles: const PosStyles(align: PosAlign.center));
  }

  static List<int> _bankSection(Generator g, List<Map<String, dynamic>>? accounts) {
    if (accounts == null || accounts.isEmpty) return [];
    final valid = accounts.where((a) {
      final bn = a['bankName']?.toString() ?? '';
      final an = a['accountNumber']?.toString() ?? '';
      return bn.isNotEmpty && an.isNotEmpty;
    }).toList();
    if (valid.isEmpty) return [];

    List<int> b = [];
    b += g.text('BANK DETAILS', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.hr(ch: '-');
    for (final a in valid) {
      b += g.text(a['bankName'].toString(), styles: const PosStyles(bold: true));
      b += g.text('${a['accountNumber']} - ${a['accountName'] ?? ''}');
      b += g.emptyLines(1);
    }
    b += g.hr(ch: '-');
    return b;
  }

  // ── Payment history ────────────────────────────────────────────────────────

  static Future<void> printPaymentHistory({
    required String schoolName,
    required String schoolAddress,
    required String studentName,
    required String studentClass,
    required List<Map<String, dynamic>> payments,
    required double totalPaid,
    double? totalBills,
    double? outstanding,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];

    b += g.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      b += g.text(schoolAddress, styles: const PosStyles(align: PosAlign.center));
    }
    b += _phoneLine(g, schoolPhone);
    b += g.hr();

    b += g.text('PAYMENT HISTORY',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.emptyLines(1);

    b += g.text('Student: $studentName');
    b += g.text('Class: $studentClass');
    b += g.hr();

    b += g.text('PAYMENTS', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.hr();

    for (final payment in payments) {
      final date = payment['date'] ?? '';
      final method = payment['method'] ?? '';
      final amount = 'N${_amt((payment['amount'] as num?)?.toDouble() ?? 0.0)}';
      final paymentFor = payment['paymentFor']?.toString() ?? '';
      b += g.row([
        PosColumn(text: date, width: 6, styles: const PosStyles(align: PosAlign.left)),
        PosColumn(text: method, width: 3, styles: const PosStyles(align: PosAlign.center)),
        PosColumn(text: amount, width: 3, styles: const PosStyles(align: PosAlign.right)),
      ]);
      if (paymentFor.isNotEmpty) {
        b += g.text('  For: $paymentFor');
      }
    }

    b += g.hr();

    b += g.text('FINANCIAL SUMMARY', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.emptyLines(1);

    if (totalBills != null) {
      b += g.text('Total Bills: N ${_amt(totalBills)}');
    }
    b += g.text('Total Paid: N ${_amt(totalPaid)}');
    if (outstanding != null) {
      b += g.text('Outstanding: N ${_amt(outstanding)}',
          styles: const PosStyles(bold: true, align: PosAlign.center));
      b += g.emptyLines(1);
      final isBalanced = outstanding <= 0;
      b += g.text(
        isBalanced ? '** BALANCED **' : '** YET TO BALANCE **',
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          align: PosAlign.center,
        ),
      );
      b += g.text('- Payment Status -',
          styles: const PosStyles(align: PosAlign.center, bold: true));
    }
    b += g.hr();

    b += _bankSection(g, bankAccounts);

    b += g.text('Thank you!', styles: const PosStyles(align: PosAlign.center));
    b += g.cut();

    await _send(b);
  }

  // ── Siblings bills ─────────────────────────────────────────────────────────

  static Future<void> printSiblingsBills({
    required String schoolName,
    required String schoolAddress,
    required String parentName,
    required int siblingCount,
    required String term,
    required List<Map<String, dynamic>> siblingItems,
    required double groupTotalBills,
    required double groupTotalPaid,
    required double groupTotalOutstanding,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];

    b += g.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      b += g.text(schoolAddress, styles: const PosStyles(align: PosAlign.center));
    }
    b += _phoneLine(g, schoolPhone);
    b += g.hr();

    b += g.text('SIBLING BILLS/PAYMENT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.hr();

    b += g.text('Name of Parent: $parentName', styles: const PosStyles(bold: true));
    b += g.text('No. of Sibling: $siblingCount');
    b += g.text('Term: $term');
    b += g.hr();

    b += g.text('FEE BREAKDOWN', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.hr(ch: '-');

    for (int i = 0; i < siblingItems.length; i++) {
      final s = siblingItems[i];
      final name = (s['name'] as String? ?? '').trim();
      final className = (s['className'] as String? ?? '').trim();
      final totalBill = (s['totalBill'] as num?)?.toDouble() ?? 0.0;
      final totalPaid = (s['totalPaid'] as num?)?.toDouble() ?? 0.0;
      final outstanding = (s['outstanding'] as num?)?.toDouble() ?? 0.0;

      b += g.text('$name  ($className)', styles: const PosStyles(bold: true));
      b += g.text(
        'Bill:N${_fmtInt(totalBill)}  Paid:N${_fmtInt(totalPaid)}  Bal:N${_fmtInt(outstanding)}',
      );

      if (i < siblingItems.length - 1) {
        b += g.hr(ch: '-');
      }
    }

    b += g.hr();

    b += g.text('SUMMARY', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.text('Total Bills: N${_fmtInt(groupTotalBills)}',
        styles: const PosStyles(align: PosAlign.center));
    b += g.text('Total Paid: N${_fmtInt(groupTotalPaid)}',
        styles: const PosStyles(align: PosAlign.center));
    b += g.hr(ch: '-');
    b += g.text('Outstanding: N${_fmtInt(groupTotalOutstanding)}',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.hr();

    final bool isBalanced = groupTotalOutstanding <= 0;
    b += g.text(
      isBalanced ? '** BALANCED **' : '** YET TO BALANCE **',
      styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    b += g.hr();

    b += _bankSection(g, bankAccounts);

    b += g.text('Thank you!', styles: const PosStyles(align: PosAlign.center));
    b += g.cut();

    await _send(b);
  }

  // ── Sales receipt ──────────────────────────────────────────────────────────

  static Future<void> printSalesReceipt({
    required String schoolName,
    required String schoolAddress,
    required String buyerName,
    required String buyerType,
    required String itemName,
    required int quantity,
    required double unitPrice,
    required double totalAmount,
    required String paymentMethod,
    required String paymentStatus,
    required String saleDate,
    required String receiptNo,
    String? note,
    double? amountPaid,
    double? outstandingBalance,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];

    b += g.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      b += g.text(schoolAddress, styles: const PosStyles(align: PosAlign.center));
    }
    b += _phoneLine(g, schoolPhone);
    b += g.hr();

    b += g.text('SALES RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.emptyLines(1);

    b += g.text('Receipt No: $receiptNo', styles: const PosStyles(bold: true));
    b += g.text('Buyer: $buyerName');
    b += g.text('Type: $buyerType');
    b += g.text('Date: $saleDate');
    b += g.hr();

    b += g.text('ITEM DETAILS', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.emptyLines(1);
    b += g.text('Item: $itemName');
    b += g.text('Quantity: $quantity');
    b += g.text('Unit Price: N ${_amt(unitPrice)}');

    if (note != null && note.isNotEmpty) {
      b += g.text('Note: $note');
    }

    b += g.hr();

    b += g.text('TOTAL AMOUNT', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.text('N ${_amt(totalAmount)}',
        styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size3, bold: true));
    b += g.hr();

    b += g.text('PAYMENT DETAILS', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.emptyLines(1);
    b += g.text('Method: $paymentMethod');
    b += g.text('Status: $paymentStatus', styles: const PosStyles(bold: true));

    if (paymentStatus != 'Paid') {
      if (amountPaid != null) {
        b += g.text('Amount Paid: N ${_amt(amountPaid)}');
      }
      if (outstandingBalance != null && outstandingBalance > 0) {
        b += g.text('Outstanding: N ${_amt(outstandingBalance)}',
            styles: const PosStyles(bold: true, height: PosTextSize.size2));
      }
    }

    b += g.hr();

    b += _bankSection(g, bankAccounts);

    b += g.text('Thank you for your purchase!', styles: const PosStyles(align: PosAlign.center));
    b += g.cut();

    await _send(b);
  }

  // ── Multi-item sales receipt ───────────────────────────────────────────────

  static Future<void> printMultiItemSalesReceipt({
    required String schoolName,
    required String schoolAddress,
    required String buyerName,
    required String buyerType,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required double amountPaid,
    required double outstandingBalance,
    required String paymentMethod,
    required String paymentStatus,
    required String saleDate,
    required String receiptNo,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];

    b += g.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      b += g.text(schoolAddress, styles: const PosStyles(align: PosAlign.center));
    }
    b += _phoneLine(g, schoolPhone);
    b += g.hr();

    b += g.text('SALES RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.emptyLines(1);

    b += g.text('Receipt No: $receiptNo', styles: const PosStyles(bold: true));
    b += g.text('Buyer: $buyerName');
    b += g.text('Type: $buyerType');
    b += g.text('Date: $saleDate');
    b += g.hr();

    b += g.text('ITEMS PURCHASED (${items.length})',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.emptyLines(1);

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final itemName = item['itemName'] as String;
      final quantity = item['quantity'] as int;
      final unitPrice = (item['unitPrice'] as num).toDouble();
      final itemTotal = (item['totalAmount'] as num).toDouble();

      b += g.text('${i + 1}. $itemName', styles: const PosStyles(bold: true));
      b += g.text('   Qty: $quantity x N ${_amt(unitPrice)}');
      b += g.text('   Total: N ${_amt(itemTotal)}',
          styles: const PosStyles(align: PosAlign.right));

      if (i < items.length - 1) {
        b += g.emptyLines(1);
      }
    }

    b += g.hr();

    b += g.text('PAYMENT SUMMARY', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.emptyLines(1);
    b += g.text('Total Amount: N ${_amt(totalAmount)}', styles: const PosStyles(bold: true));
    b += g.text('Amount Paid: N ${_amt(amountPaid)}');

    if (outstandingBalance > 0) {
      b += g.text('Outstanding: N ${_amt(outstandingBalance)}',
          styles: const PosStyles(bold: true, height: PosTextSize.size2));
    }

    b += g.hr();

    b += g.text('Method: $paymentMethod');
    b += g.text('Status: $paymentStatus', styles: const PosStyles(bold: true));

    b += g.hr();

    b += _bankSection(g, bankAccounts);

    b += g.text('Thank you for your purchase!', styles: const PosStyles(align: PosAlign.center));
    b += g.cut();

    await _send(b);
  }

  // ── New intake bill ────────────────────────────────────────────────────────

  static Future<void> printNewIntakeBill({
    required String schoolName,
    required String schoolAddress,
    required String className,
    String? armName,
    required String term,
    required String session,
    required List<Map<String, dynamic>> regularFees,
    required List<Map<String, dynamic>> groupedCategories,
    required List<Map<String, dynamic>> standaloneItems,
    required double grandTotal,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm80,
    String title = 'NEW INTAKE BILL',
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];

    b += g.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      b += g.text(schoolAddress, styles: const PosStyles(align: PosAlign.center));
    }
    b += _phoneLine(g, schoolPhone);
    b += g.hr();

    b += g.text(title,
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.emptyLines(1);

    final classLabel = armName != null ? '$className - $armName' : className;
    b += g.text('Class: $classLabel',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.text('$term | $session', styles: const PosStyles(align: PosAlign.center));
    b += g.hr();

    int serialNumber = 0;

    // Registration fees (standalone items) — shown first
    if (standaloneItems.isNotEmpty) {
      b += g.text('REGISTRATION FEES',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      b += g.hr(ch: '-');

      double sectionTotal = 0;
      for (var item in standaloneItems) {
        serialNumber++;
        final name = item['name'] ?? 'Unknown';
        final amountValue = (item['amount'] as num?)?.toDouble() ?? 0.0;
        sectionTotal += amountValue;

        b += g.row([
          PosColumn(
            text: '$serialNumber. $name',
            width: 7,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: 'N ${_amt(amountValue)}',
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      b += g.row([
        PosColumn(
          text: 'Subtotal:',
          width: 7,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
        PosColumn(
          text: 'N ${_amt(sectionTotal)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      b += g.hr(ch: '-');
    }

    // Current term fees
    if (regularFees.isNotEmpty) {
      b += g.text('CURRENT TERM FEES',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      b += g.hr(ch: '-');

      double sectionTotal = 0;
      for (var fee in regularFees) {
        serialNumber++;
        final name = fee['feeItemName'] ?? 'Unknown';
        final amountValue = (fee['amount'] as num?)?.toDouble() ?? 0.0;
        sectionTotal += amountValue;

        b += g.row([
          PosColumn(
            text: '$serialNumber. $name',
            width: 7,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: 'N ${_amt(amountValue)}',
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      b += g.row([
        PosColumn(
          text: 'Subtotal:',
          width: 7,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
        PosColumn(
          text: 'N ${_amt(sectionTotal)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      b += g.hr(ch: '-');
    }

    // Category sections
    for (var category in groupedCategories) {
      final categoryName = category['categoryName'] ?? 'Unknown';
      final categoryItems = category['items'] as List<Map<String, dynamic>>? ?? [];
      final categoryTotal = (category['categoryTotal'] as num?)?.toDouble() ?? 0;

      if (categoryItems.isEmpty) continue;

      b += g.text(categoryName.toUpperCase(),
          styles: const PosStyles(align: PosAlign.center, bold: true));
      b += g.hr(ch: '-');

      for (var item in categoryItems) {
        serialNumber++;
        final name = item['name'] ?? 'Unknown';
        final amountValue = (item['amount'] as num?)?.toDouble() ?? 0.0;

        b += g.row([
          PosColumn(
            text: '$serialNumber. $name',
            width: 7,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: 'N ${_amt(amountValue)}',
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      b += g.row([
        PosColumn(
          text: 'Subtotal:',
          width: 7,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
        PosColumn(
          text: 'N ${_amt(categoryTotal)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      b += g.hr(ch: '-');
    }

    b += g.hr();

    b += g.text('GRAND TOTAL', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.text('N ${_amt(grandTotal)}',
        styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size3, bold: true));
    b += g.hr();

    b += _bankSection(g, bankAccounts);

    b += g.text('New Intake Bill', styles: const PosStyles(align: PosAlign.center));
    b += g.text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
        styles: const PosStyles(align: PosAlign.center));
    b += g.cut();

    await _send(b);
  }

  // ── Test print ─────────────────────────────────────────────────────────────

  static Future<void> printTest({PaperSize paperSize = PaperSize.mm80}) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];
    b += g.text('BURSARY MANAGER',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.text('USB Printer Test', styles: const PosStyles(align: PosAlign.center));
    b += g.hr();
    b += g.text('Printer is working correctly!', styles: const PosStyles(align: PosAlign.center));
    b += g.text('Paper: ${paperSize == PaperSize.mm58 ? "58mm" : "80mm"}',
        styles: const PosStyles(align: PosAlign.center));
    b += g.text('Date: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
        styles: const PosStyles(align: PosAlign.center));
    b += g.cut();
    await _send(b);
  }

  // ── Bill receipt ───────────────────────────────────────────────────────────

  static Future<void> printBill({
    required String schoolName,
    required String schoolAddress,
    required String studentName,
    required String studentClass,
    required String term,
    required List<Map<String, dynamic>> feeItems,
    required double total,
    required String billDate,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];

    b += g.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      b += g.text(schoolAddress, styles: const PosStyles(align: PosAlign.center));
    }
    b += _phoneLine(g, schoolPhone);
    b += g.hr();

    b += g.text('FEE BILL',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.emptyLines(1);

    b += g.text('Student: $studentName');
    b += g.text('Class: $studentClass');
    b += g.text('Term: $term');
    b += g.text('Date: $billDate');
    b += g.hr();

    b += g.text('FEE BREAKDOWN', styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.hr();

    for (final item in feeItems) {
      final name = item['name']?.toString() ?? '';
      final amount = 'N ${_amt((item['amount'] as num?)?.toDouble() ?? 0.0)}';
      b += g.row([
        PosColumn(text: name, width: 7, styles: const PosStyles(align: PosAlign.left)),
        PosColumn(text: amount, width: 5, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    b += g.hr();
    b += g.text('TOTAL: N ${_amt(total)}',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.hr();

    b += _bankSection(g, bankAccounts);

    b += g.text('Thank you!', styles: const PosStyles(align: PosAlign.center));
    b += g.cut();

    await _send(b);
  }

  // ── Payment receipt ────────────────────────────────────────────────────────

  static Future<void> printPaymentReceipt({
    required String schoolName,
    required String schoolAddress,
    required String studentName,
    required String studentClass,
    required String term,
    required double amountPaid,
    required double totalBill,
    required double outstanding,
    required String paymentDate,
    required String paymentMethod,
    String? receiptNumber,
    String? note,
    String? paymentFor,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];

    b += g.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      b += g.text(schoolAddress, styles: const PosStyles(align: PosAlign.center));
    }
    b += _phoneLine(g, schoolPhone);
    b += g.hr();

    b += g.text('PAYMENT RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.emptyLines(1);

    if (receiptNumber != null && receiptNumber.isNotEmpty) {
      b += g.text('Receipt No: $receiptNumber', styles: const PosStyles(bold: true));
    }
    b += g.text('Student: $studentName');
    b += g.text('Class: $studentClass');
    b += g.text('Term: $term');

    // Parse date/time the same way Bluetooth does
    try {
      final parsed = DateTime.tryParse(paymentDate);
      if (parsed != null) {
        final dateOnly = DateFormat('dd/MM/yyyy').format(parsed);
        final timeOnly = DateFormat('HH:mm').format(parsed);
        b += g.text('Date/Time: $dateOnly  $timeOnly',
            styles: const PosStyles(bold: true));
      } else {
        b += g.text('Date: $paymentDate');
      }
    } catch (_) {
      b += g.text('Date: $paymentDate');
    }

    b += g.text('Method: $paymentMethod');
    if (paymentFor != null && paymentFor.isNotEmpty) {
      b += g.text('Payment For: $paymentFor');
    }
    if (note != null && note.isNotEmpty) {
      b += g.text('Note: $note');
    }
    b += g.hr();

    // Big AMOUNT PAID display
    b += g.text('AMOUNT PAID',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.text('N ${_amt(amountPaid)}',
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ));
    b += g.hr();

    // Account summary
    b += g.text('ACCOUNT SUMMARY',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.text('Total Bills : N ${_amt(totalBill)}');
    b += g.text('Outstanding : N ${_amt(outstanding > 0 ? outstanding : 0)}',
        styles: const PosStyles(bold: true));

    final isBalanced = outstanding <= 0;
    b += g.hr(ch: '-');
    b += g.text(
      isBalanced ? 'BALANCED' : 'YET TO BALANCE',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    b += g.hr();

    b += _bankSection(g, bankAccounts);

    b += g.text('Thank you for your payment!',
        styles: const PosStyles(align: PosAlign.center));
    b += g.cut();

    await _send(b);
  }

  static Future<void> printFamilyPaymentReceipt({
    required String schoolName,
    required String schoolAddress,
    required String parentName,
    required String parentPhone,
    required String term,
    required String session,
    required String method,
    required String date,
    required String note,
    required List<Map<String, dynamic>> paymentItems,
    required double totalAmount,
    String? schoolPhone,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];

    b += g.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      b += g.text(schoolAddress, styles: const PosStyles(align: PosAlign.center));
    }
    b += _phoneLine(g, schoolPhone);
    b += g.hr();

    b += g.text('FAMILY PAYMENT RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.emptyLines(1);

    b += g.text('Parent: $parentName', styles: const PosStyles(bold: true));
    if (parentPhone.isNotEmpty) {
      b += g.text('Phone : $parentPhone');
    }
    b += g.text('Term  : $term  $session');
    b += g.text('Date  : $date');
    b += g.text('Method: $method');
    if (note.isNotEmpty) {
      b += g.text('Note  : $note');
    }
    b += g.hr();

    // Total amount paid — shown prominently before the split
    b += g.text('AMOUNT PAID',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.text('N ${_amt(totalAmount)}',
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ));
    b += g.hr();

    b += g.text('PAYMENT SPLIT',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.emptyLines(1);

    final splitNameChars = (_charsPerLine(paperSize) * 7 / 12).floor();
    for (final item in paymentItems) {
      final name = item['name']?.toString() ?? '';
      final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
      b += g.row([
        PosColumn(
          text: _fitToWidth(name, splitNameChars),
          width: 7,
          styles: const PosStyles(align: PosAlign.left),
        ),
        PosColumn(
          text: 'N ${_amt(amount)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
    }

    b += g.hr();

    // Account summary per sibling (if financial data was provided)
    final hasAccountData = paymentItems.isNotEmpty &&
        paymentItems.first.containsKey('totalBill');
    if (hasAccountData) {
      b += g.text('ACCOUNT SUMMARY',
          styles: const PosStyles(align: PosAlign.center, bold: true));

      for (final item in paymentItems) {
        final name = item['name']?.toString() ?? '';
        final className = item['className']?.toString() ?? '';
        final totalBill = (item['totalBill'] as num?)?.toDouble() ?? 0.0;
        final totalPaid = (item['totalPaid'] as num?)?.toDouble() ?? 0.0;
        final outstanding = (item['outstanding'] as num?)?.toDouble() ?? 0.0;
        final isBalanced = outstanding <= 0;

        b += g.hr(ch: '-');
        final label = className.isNotEmpty ? '$name  ($className)' : name;
        b += g.text(label, styles: const PosStyles(bold: true));
        b += g.text('Total Bills : N ${_amt(totalBill)}');
        b += g.text('Total Paid  : N ${_amt(totalPaid)}');
        b += g.text('Outstanding : N ${_amt(outstanding)}',
            styles: const PosStyles(bold: true));
        b += g.text(
          isBalanced ? 'BALANCED' : 'YET TO BALANCE',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        );
      }
      b += g.hr();

      // Family summary totals
      final familyTotalBills = paymentItems.fold(
          0.0, (sum, i) => sum + ((i['totalBill'] as num?)?.toDouble() ?? 0.0));
      final familyTotalPaid = paymentItems.fold(
          0.0, (sum, i) => sum + ((i['totalPaid'] as num?)?.toDouble() ?? 0.0));
      final familyOutstanding = paymentItems.fold(
          0.0, (sum, i) => sum + ((i['outstanding'] as num?)?.toDouble() ?? 0.0));
      final familyBalanced = familyOutstanding <= 0;

      b += g.text('FAMILY SUMMARY',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      b += g.text('Total Bills : N ${_amt(familyTotalBills)}');
      b += g.text('Total Paid  : N ${_amt(familyTotalPaid)}');
      b += g.text('Outstanding : N ${_amt(familyOutstanding)}',
          styles: const PosStyles(bold: true));
      b += g.hr(ch: '-');
      b += g.text(
        familyBalanced ? '** BALANCED **' : '** YET TO BALANCE **',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      b += g.hr();
    }

    b += g.text('Thank you for your payment!',
        styles: const PosStyles(align: PosAlign.center));
    b += g.cut();

    await _send(b);
  }

  // siblingItems: list of { name, className, totalBill, totalPaid, outstanding, payments: [{date, method, amount}] }
  static Future<void> printFamilyPaymentHistory({
    required String schoolName,
    required String schoolAddress,
    required String parentName,
    required String parentPhone,
    required String term,
    required String session,
    required List<Map<String, dynamic>> siblingItems,
    required double groupTotalBills,
    required double groupTotalPaid,
    required double groupTotalOutstanding,
    String? schoolPhone,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    List<int> b = [];

    b += g.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      b += g.text(schoolAddress, styles: const PosStyles(align: PosAlign.center));
    }
    b += _phoneLine(g, schoolPhone);
    b += g.hr();

    b += g.text('FAMILY PAYMENT HISTORY',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    b += g.emptyLines(1);

    b += g.text('Parent: $parentName', styles: const PosStyles(bold: true));
    if (parentPhone.isNotEmpty) {
      b += g.text('Phone : $parentPhone');
    }
    b += g.text('Term  : $term  $session');
    b += g.hr();

    for (final sibling in siblingItems) {
      final name = sibling['name']?.toString() ?? '';
      final className = sibling['className']?.toString() ?? '';
      final totalBill = (sibling['totalBill'] as num?)?.toDouble() ?? 0.0;
      final totalPaid = (sibling['totalPaid'] as num?)?.toDouble() ?? 0.0;
      final outstanding = (sibling['outstanding'] as num?)?.toDouble() ?? 0.0;
      final payments = sibling['payments'] as List? ?? [];

      b += g.text(name, styles: const PosStyles(bold: true));
      if (className.isNotEmpty) {
        b += g.text(className);
      }
      b += g.hr(ch: '-');

      if (payments.isEmpty) {
        b += g.text('No payments this term',
            styles: const PosStyles(align: PosAlign.center));
      } else {
        for (final p in payments) {
          final date = p['date']?.toString() ?? '';
          final method = p['method']?.toString() ?? '';
          final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          b += g.row([
            PosColumn(text: date, width: 6, styles: const PosStyles(align: PosAlign.left)),
            PosColumn(text: method, width: 3, styles: const PosStyles(align: PosAlign.center)),
            PosColumn(
              text: 'N${_amt(amt)}',
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
      }

      b += g.row([
        PosColumn(text: 'Bill:', width: 4),
        PosColumn(text: 'N${_amt(totalBill)}', width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
        PosColumn(text: '', width: 4),
      ]);
      b += g.row([
        PosColumn(text: 'Paid:', width: 4),
        PosColumn(text: 'N${_amt(totalPaid)}', width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
        PosColumn(
          text: outstanding > 0 ? 'OWING' : 'OK',
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      b += g.hr();
    }

    b += g.text('FAMILY TOTALS',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += g.text('Total Bills  : N ${_amt(groupTotalBills)}');
    b += g.text('Total Paid   : N ${_amt(groupTotalPaid)}',
        styles: const PosStyles(bold: true));
    b += g.text('Outstanding  : N ${_amt(groupTotalOutstanding)}',
        styles: const PosStyles(bold: true));
    b += g.hr(ch: '-');
    b += g.text(
      groupTotalOutstanding <= 0 ? '** BALANCED **' : '** YET TO BALANCE **',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    b += g.hr();
    b += g.text('Thank you!', styles: const PosStyles(align: PosAlign.center));
    b += g.cut();

    await _send(b);
  }
}
