// lib/screens/sales/sale_receipt_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/thermal_printer_manager.dart';
import '../../utils/usb_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../settings/thermal_printer_screen.dart';
import '../settings/usb_printer_screen.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class SaleReceiptScreen extends StatefulWidget {
  final List<int> saleIds;

  const SaleReceiptScreen({super.key, required this.saleIds});

  @override
  State<SaleReceiptScreen> createState() => _SaleReceiptScreenState();
}

class _SaleReceiptScreenState extends State<SaleReceiptScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _sales = [];
  Map<String, dynamic>? _school;
  bool _loading = true;

  // Payment summary
  double _totalAmount = 0.0;
  double _totalAmountPaid = 0.0;
  double _totalOutstanding = 0.0;
  String? _buyerName;
  String? _buyerType;
  String? _paymentMethod;
  String? _paymentStatus;
  DateTime? _saleDate;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _loading = true);

    try {
      final List<Map<String, dynamic>> sales = [];

      // Load all sales
      for (final saleId in widget.saleIds) {
        final sale = await _db.getSaleById(saleId);
        if (sale != null) {
          sales.add(sale);
        }
      }

      final school = await _db.getSchoolProfile();

      if (sales.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      // Calculate totals
      double totalAmount = 0.0;
      double totalAmountPaid = 0.0;
      double totalOutstanding = 0.0;

      print('=== RECEIPT LOADING DEBUG ===');
      print('Number of sales loaded: ${sales.length}');

      for (final sale in sales) {
        final saleTotal = (sale['totalAmount'] as num).toDouble();
        final salePaid = (sale['amountPaid'] as num?)?.toDouble() ?? 0.0;
        final saleOutstanding = (sale['outstandingBalance'] as num?)?.toDouble() ?? 0.0;

        print('Sale ID: ${sale['id']}');
        print('  Item: ${sale['itemName']}');
        print('  Total Amount: ₦$saleTotal');
        print('  Amount Paid (from DB): ₦$salePaid');
        print('  Outstanding (from DB): ₦$saleOutstanding');
        print('  Payment Status (from DB): ${sale['paymentStatus']}');

        totalAmount += saleTotal;
        totalAmountPaid += salePaid;
        totalOutstanding += saleOutstanding;
      }

      print('---');
      print('Calculated Totals:');
      print('  Total Amount: ₦$totalAmount');
      print('  Total Amount Paid: ₦$totalAmountPaid');
      print('  Total Outstanding: ₦$totalOutstanding');
      print('=== END RECEIPT DEBUG ===');

      // Get buyer info from first sale (all sales have same buyer)
      final firstSale = sales.first;

      // Calculate payment status based on actual payment amounts
      String calculatedStatus;
      if (totalAmountPaid == 0) {
        calculatedStatus = 'Not Paid';
      } else if (totalAmountPaid > 0 && totalAmountPaid < totalAmount) {
        calculatedStatus = 'Part Payment';
      } else {
        calculatedStatus = 'Paid';
      }

      setState(() {
        _sales = sales;
        _school = school;
        _totalAmount = totalAmount;
        _totalAmountPaid = totalAmountPaid;
        _totalOutstanding = totalOutstanding;
        _buyerName = firstSale['buyerName'];
        _buyerType = firstSale['buyerType'];
        _paymentMethod = firstSale['paymentMethod'];
        _paymentStatus = calculatedStatus;
        _saleDate = DateTime.parse(firstSale['saleDate']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading sales: $e')),
      );
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

  String _getReceiptNumber() {
    if (_sales.isEmpty) return '';
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'SALE-${_sales.first['id']}-$date';
  }

  Future<void> _printReceipt() async {
    if (_sales.isEmpty || _school == null) return;

    // Check if printer is connected
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

    // Show paper size selection dialog
    if (!mounted) return;
    final paperSize = await showDialog<PaperSize>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.print, color: Colors.green),
            const SizedBox(width: 8),
            const Text('Print Receipt'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'CONNECTED',
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 58mm Option
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.orange),
              title: const Text('58mm Paper'),
              subtitle: const Text('Standard thermal receipt'),
              onTap: () => Navigator.pop(context, PaperSize.mm58),
            ),
            const Divider(),
            // 80mm Option
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.green),
              title: const Text('80mm Paper'),
              subtitle: const Text('Wider format (Recommended)'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'RECOMMENDED',
                  style: TextStyle(fontSize: 9, color: Colors.white),
                ),
              ),
              onTap: () => Navigator.pop(context, PaperSize.mm80),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (paperSize == null) return;

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ThermalPrinterManager.printMultiItemSalesReceipt(
        schoolName: _school!['name']?.toString() ?? 'School',
        schoolAddress: _school!['address']?.toString() ?? '',
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        buyerName: _buyerName ?? '',
        buyerType: _buyerType ?? '',
        items: _sales.map((sale) {
          final isCustomItem = sale['isCustomItem'] == 1 || sale['stockItemId'] == 0;
          return {
            'itemName': isCustomItem ? '${sale['itemName']} [Custom]' : sale['itemName'],
            'quantity': sale['quantity'] as int,
            'unitPrice': (sale['unitPrice'] as num).toDouble(),
            'totalAmount': (sale['totalAmount'] as num).toDouble(),
          };
        }).toList(),
        totalAmount: _totalAmount,
        amountPaid: _totalAmountPaid,
        outstandingBalance: _totalOutstanding,
        paymentMethod: _paymentMethod ?? 'N/A',
        paymentStatus: _paymentStatus ?? 'Paid',
        saleDate: DateFormat('MMMM d, yyyy - h:mm a').format(_saleDate ?? DateTime.now()),
        receiptNo: _getReceiptNumber(),
        paperSize: paperSize,
      );

      // Increment print counter
      await PrintCounterHelper.incrementReceiptsPrinted();

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Receipt printed successfully on ${paperSize == PaperSize.mm58 ? "58mm" : "80mm"} paper!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Print error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Print method selection ───────────────────────────────────────────────
  void _showPrintMethodDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.print, color: Colors.green), SizedBox(width: 8), Text('Print Receipt')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bluetooth, color: Colors.blue),
              title: const Text('Bluetooth Printer'),
              subtitle: const Text('Wireless thermal printer'),
              onTap: () { Navigator.pop(ctx); _printReceipt(); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.usb, color: Colors.deepPurple),
              title: const Text('USB Printer (OTG)'),
              subtitle: const Text('Wired via USB cable'),
              onTap: () { Navigator.pop(ctx); _showUsbPrinterSizeDialog(); },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
  }

  Future<void> _showUsbPrinterSizeDialog() async {
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
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.usb, color: Colors.deepPurple),
          const SizedBox(width: 8),
          const Text('USB Print Receipt'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4)),
            child: const Text('CONNECTED', style: TextStyle(fontSize: 10, color: Colors.white)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.orange),
              title: const Text('58mm Paper'),
              subtitle: const Text('Standard thermal receipt'),
              onTap: () { Navigator.pop(ctx); _printViaUsb(PaperSize.mm58); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.green),
              title: const Text('80mm Paper'),
              subtitle: const Text('Wider format (Recommended)'),
              onTap: () { Navigator.pop(ctx); _printViaUsb(PaperSize.mm80); },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
  }

  Future<void> _printViaUsb(PaperSize paperSize) async {
    if (_sales.isEmpty || _school == null) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await UsbPrinterManager.printMultiItemSalesReceipt(
        schoolName: _school!['name']?.toString() ?? 'School',
        schoolAddress: _school!['address']?.toString() ?? '',
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        buyerName: _buyerName ?? '',
        buyerType: _buyerType ?? '',
        items: _sales.map((sale) {
          final isCustomItem = sale['isCustomItem'] == 1 || sale['stockItemId'] == 0;
          return {
            'itemName': isCustomItem ? '${sale['itemName']} [Custom]' : sale['itemName'],
            'quantity': sale['quantity'] as int,
            'unitPrice': (sale['unitPrice'] as num).toDouble(),
            'totalAmount': (sale['totalAmount'] as num).toDouble(),
          };
        }).toList(),
        totalAmount: _totalAmount,
        amountPaid: _totalAmountPaid,
        outstandingBalance: _totalOutstanding,
        paymentMethod: _paymentMethod ?? 'N/A',
        paymentStatus: _paymentStatus ?? 'Paid',
        saleDate: DateFormat('MMMM d, yyyy - h:mm a').format(_saleDate ?? DateTime.now()),
        receiptNo: _getReceiptNumber(),
        paperSize: paperSize,
      );
      await PrintCounterHelper.incrementReceiptsPrinted();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Receipt printed via USB (${paperSize == PaperSize.mm58 ? "58mm" : "80mm"})!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB print error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale Receipt'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (!_loading && _sales.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _showPrintMethodDialog,
              tooltip: 'Print Receipt',
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
              ? const Center(child: Text('No sales found'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // School Info
                      if (_school != null) ...[
                        Text(
                          (_school!['name'] ?? 'School').toString().toUpperCase(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_school!['address'] != null &&
                            _school!['address'].toString().isNotEmpty)
                          Text(
                            _school!['address'],
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        if (_school!['phone'] != null &&
                            _school!['phone'].toString().isNotEmpty)
                          Text(
                            _school!['phone'],
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 10),
                      ],

                      const Divider(thickness: 2),

                      // Receipt Title
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'SALES RECEIPT',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Receipt No: ${_getReceiptNumber()}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                      const Divider(),

                      // Receipt Details
                      _buildDetailRow('Date:', DateFormat('MMMM d, yyyy - h:mm a')
                          .format(_saleDate ?? DateTime.now())),
                      _buildDetailRow('Buyer:', _buyerName ?? ''),
                      _buildDetailRow('Buyer Type:', _buyerType ?? ''),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),

                      // Items List
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'ITEMS PURCHASED',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_sales.length} item${_sales.length > 1 ? "s" : ""}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 12),
                            ..._sales.map((sale) {
                              final isCustomItem = sale['isCustomItem'] == 1 || sale['stockItemId'] == 0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            sale['itemName'],
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: isCustomItem ? Colors.purple.shade800 : null,
                                            ),
                                          ),
                                        ),
                                        if (isCustomItem)
                                          Container(
                                            margin: const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Custom',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.purple.shade900,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${sale['quantity']} × ₦${formatter.format(sale['unitPrice'])}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isCustomItem ? Colors.purple.shade600 : Colors.grey.shade700,
                                          ),
                                        ),
                                        Text(
                                          '₦${formatter.format(sale['totalAmount'])}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isCustomItem ? Colors.purple.shade800 : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (sale != _sales.last)
                                      const Divider(height: 16),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Payment Summary
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue.shade50, Colors.green.shade50],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300, width: 2),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'PAYMENT SUMMARY',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 12),
                            _buildSummaryRow(
                              'Total Amount:',
                              '₦${formatter.format(_totalAmount)}',
                              isBold: true,
                            ),
                            const SizedBox(height: 8),
                            _buildSummaryRow(
                              'Amount Paid:',
                              '₦${formatter.format(_totalAmountPaid)}',
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(height: 8),
                            if (_totalOutstanding > 0) ...[
                              _buildSummaryRow(
                                'Outstanding Balance:',
                                '₦${formatter.format(_totalOutstanding)}',
                                color: Colors.red.shade700,
                                isBold: true,
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Payment Method & Status
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.payment, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  'Payment Method: ${_paymentMethod ?? "N/A"}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _paymentStatus == 'Paid'
                                    ? Colors.green.shade100
                                    : _paymentStatus == 'Part Payment'
                                        ? Colors.orange.shade100
                                        : Colors.red.shade100, // Not Paid or Credit
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Status: ${_paymentStatus ?? "Paid"}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: _paymentStatus == 'Paid'
                                      ? Colors.green.shade900
                                      : _paymentStatus == 'Part Payment'
                                          ? Colors.orange.shade900
                                          : Colors.red.shade900, // Not Paid or Credit
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Footer
                      Text(
                        'Thank you for your purchase!',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Generated: ${DateFormat('MMMM d, yyyy - h:mm a').format(DateTime.now())}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Close Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check_circle),
                          label: const Text(
                            'Close',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
