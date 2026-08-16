// lib/screens/reports/sales_report_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/sales_report_pdf_generator.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  DateTime _selectedDate = DateTime.now();
  bool _loading = false;

  List<Map<String, dynamic>> _groupedTransactions = [];
  Map<String, dynamic>? _school;
  String? _term;
  String? _session;

  double _totalRevenue = 0;
  double _totalCost = 0;
  double _totalProfit = 0;
  double _cashTotal = 0;
  double _posTotal = 0;
  double _transferTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadDailyReport();
  }

  Future<void> _loadDailyReport() async {
    setState(() => _loading = true);

    try {
      _term = await _db.getActiveTerm();
      _session = (await _db.getActiveSession())?['sessionName'];
      _school = await _db.getSchoolProfile();

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final sales = await _db.getSalesByExactDate(dateStr);

      // Reset totals
      double totalRevenue = 0;
      double totalCost = 0;
      double totalProfit = 0;
      double cashTotal = 0;
      double posTotal = 0;
      double transferTotal = 0;

      // Group sales by transaction (same buyer + same exact timestamp)
      final Map<String, List<Map<String, dynamic>>> transactionGroups = {};

      for (var sale in sales) {
        // Filter by active term/session
        if (sale['term'] != _term || sale['session'] != _session) {
          continue;
        }

        // Create a unique key for this transaction (buyer + exact timestamp)
        final transactionKey = '${sale['buyerName']}_${sale['saleDate']}';

        if (!transactionGroups.containsKey(transactionKey)) {
          transactionGroups[transactionKey] = [];
        }

        transactionGroups[transactionKey]!.add(sale);
      }

      // Process each transaction group
      final List<Map<String, dynamic>> groupedTransactions = [];

      for (final group in transactionGroups.values) {
        if (group.isEmpty) continue;

        final firstSale = group.first;

        // Calculate totals for this transaction
        double transactionTotal = 0;
        double transactionCost = 0;
        double transactionProfit = 0;
        double transactionAmountPaid = 0;
        double transactionOutstanding = 0;

        final List<Map<String, dynamic>> items = [];

        for (var sale in group) {
          final qty = sale['quantity'] as int;
          final unitPrice = (sale['unitPrice'] as num).toDouble();
          final totalAmount = (sale['totalAmount'] as num).toDouble();
          final amountPaid = (sale['amountPaid'] as num?)?.toDouble() ?? 0.0;
          final outstanding = (sale['outstandingBalance'] as num?)?.toDouble() ?? 0.0;

          // Check if this is a custom item (stockItemId = 0 or isCustomItem = 1)
          final isCustomItem = sale['isCustomItem'] == 1 || sale['stockItemId'] == 0;

          // Custom items have no cost price (profit = full selling price)
          final costPrice = isCustomItem ? 0.0 : (sale['costPrice'] as num?)?.toDouble() ?? 0.0;
          final profit = isCustomItem ? totalAmount : (unitPrice - costPrice) * qty;

          transactionTotal += totalAmount;
          transactionCost += costPrice * qty;
          transactionProfit += profit;
          transactionAmountPaid += amountPaid;
          transactionOutstanding += outstanding;

          items.add({
            'itemName': sale['itemName'],
            'quantity': qty,
            'unitPrice': unitPrice,
            'totalAmount': totalAmount,
            'isCustomItem': isCustomItem,
          });
        }

        // Add to summary totals
        totalRevenue += transactionTotal;
        totalCost += transactionCost;
        totalProfit += transactionProfit;

        final method = firstSale['paymentMethod'] as String;
        if (method == 'Cash') {
          cashTotal += transactionAmountPaid;
        } else if (method == 'POS') {
          posTotal += transactionAmountPaid;
        } else if (method == 'Transfer') {
          transferTotal += transactionAmountPaid;
        }

        // Calculate payment status
        String paymentStatus;
        if (transactionAmountPaid == 0) {
          paymentStatus = 'Not Paid';
        } else if (transactionAmountPaid > 0 && transactionAmountPaid < transactionTotal) {
          paymentStatus = 'Part Payment';
        } else {
          paymentStatus = 'Paid';
        }

        groupedTransactions.add({
          'buyerName': firstSale['buyerName'],
          'buyerType': firstSale['buyerType'],
          'paymentMethod': firstSale['paymentMethod'],
          'saleDate': firstSale['saleDate'],
          'items': items,
          'totalAmount': transactionTotal,
          'amountPaid': transactionAmountPaid,
          'outstandingBalance': transactionOutstanding,
          'profit': transactionProfit,
          'paymentStatus': paymentStatus,
          'saleIds': group.map((s) => s['id'] as int).toList(),
        });
      }

      // Sort by date (newest first)
      groupedTransactions.sort((a, b) =>
        DateTime.parse(b['saleDate']).compareTo(DateTime.parse(a['saleDate']))
      );

      setState(() {
        _groupedTransactions = groupedTransactions;
        _totalRevenue = totalRevenue;
        _totalCost = totalCost;
        _totalProfit = totalProfit;
        _cashTotal = cashTotal;
        _posTotal = posTotal;
        _transferTotal = transferTotal;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading report: $e')),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadDailyReport();
    }
  }

  void _editSale(Map<String, dynamic> transaction) {
    // TODO: Implement edit functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit functionality coming soon')),
    );
  }

  Future<void> _deleteSale(Map<String, dynamic> transaction) async {
    // Check if transaction has any custom items
    final items = transaction['items'] as List<Map<String, dynamic>>;
    final hasCustomItems = items.any((item) => item['isCustomItem'] == true);
    final hasStockItems = items.any((item) => item['isCustomItem'] != true);

    String stockNote;
    if (hasCustomItems && hasStockItems) {
      stockNote = 'Stock quantities will be restored for stock items only.\nCustom items will just be removed from records.';
    } else if (hasCustomItems) {
      stockNote = 'This transaction contains only custom items.\nNo stock will be restored.';
    } else {
      stockNote = 'Stock quantities will be restored.';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: Text(
          'Are you sure you want to delete this transaction?\n\n'
          'Buyer: ${transaction['buyerName']}\n'
          'Items: ${transaction['items'].length}${hasCustomItems ? ' (includes custom items)' : ''}\n'
          'Total: ₦${NumberFormat('#,##0.00').format(transaction['totalAmount'])}\n\n'
          '$stockNote',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete all sales in this transaction
      for (final saleId in transaction['saleIds'] as List<int>) {
        await _db.deleteSale(saleId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      _loadDailyReport();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting transaction: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportPDF() async {
    if (_groupedTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sales data to export')),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final summary = {
        'totalRevenue': _totalRevenue,
        'totalCost': _totalCost,
        'totalProfit': _totalProfit,
        'cashTotal': _cashTotal,
        'posTotal': _posTotal,
        'transferTotal': _transferTotal,
      };

      // Flatten grouped transactions for PDF (keeping individual items)
      final List<Map<String, dynamic>> flatSales = [];
      for (final transaction in _groupedTransactions) {
        for (final item in transaction['items'] as List<Map<String, dynamic>>) {
          final isCustom = item['isCustomItem'] == true;
          flatSales.add({
            'buyerName': transaction['buyerName'],
            'itemName': isCustom ? '${item['itemName']} [Custom]' : item['itemName'],
            'quantity': item['quantity'],
            'unitPrice': item['unitPrice'],
            'totalAmount': item['totalAmount'],
            'paymentMethod': transaction['paymentMethod'],
            'saleDate': transaction['saleDate'],
            'isCustomItem': isCustom,
          });
        }
      }

      final pdfPath = await SalesReportPDFGenerator.generateSalesReportPDF(
        sales: flatSales,
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
        schoolProfile: _school ?? {},
        summary: summary,
        term: _term ?? '',
        session: _session ?? '',
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved to: $pdfPath'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () => Share.shareXFiles([XFile(pdfPath)]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Report'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _groupedTransactions.isNotEmpty ? _exportPDF : null,
            tooltip: 'Export PDF',
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Selector
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.deepOrange.shade50,
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.deepOrange.shade700),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.edit_calendar, size: 18),
                  label: const Text('Change Date'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Report Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _groupedTransactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.analytics_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No sales recorded on this date',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDailyReport,
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            // Payment Method Breakdown
                            const Text(
                              'Payment Method Breakdown',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),

                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    _paymentMethodRow(
                                      'Cash',
                                      _cashTotal,
                                      Icons.money,
                                      Colors.green,
                                    ),
                                    const Divider(height: 16),
                                    _paymentMethodRow(
                                      'POS',
                                      _posTotal,
                                      Icons.credit_card,
                                      Colors.blue,
                                    ),
                                    const Divider(height: 16),
                                    _paymentMethodRow(
                                      'Transfer',
                                      _transferTotal,
                                      Icons.account_balance,
                                      Colors.purple,
                                    ),
                                    const Divider(height: 20, thickness: 2),
                                    _paymentMethodRow(
                                      'Total Sale',
                                      _cashTotal + _posTotal + _transferTotal,
                                      Icons.payments,
                                      Colors.deepOrange,
                                      isTotal: true,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Sales Details Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Sales Details',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_groupedTransactions.length} transactions',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Grouped Transaction Cards
                            ..._groupedTransactions.map((transaction) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Header Row
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: Colors.green.shade100,
                                            radius: 20,
                                            child: Icon(
                                              Icons.shopping_cart,
                                              color: Colors.green.shade700,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  transaction['buyerName'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                Text(
                                                  '${transaction['buyerType']} • ${DateFormat('h:mm a').format(DateTime.parse(transaction['saleDate']))}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert, size: 20),
                                            onSelected: (value) {
                                              if (value == 'edit') {
                                                _editSale(transaction);
                                              } else if (value == 'delete') {
                                                _deleteSale(transaction);
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit, size: 18, color: Colors.blue),
                                                    SizedBox(width: 8),
                                                    Text('Edit'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete, size: 18, color: Colors.red),
                                                    SizedBox(width: 8),
                                                    Text('Delete'),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),

                                      const Divider(height: 20),

                                      // Items List
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey.shade200),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.inventory_2,
                                                  size: 16,
                                                  color: Colors.grey.shade700
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Items Purchased',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            ...((transaction['items'] as List<Map<String, dynamic>>).map((item) {
                                              final isCustom = item['isCustomItem'] == true;
                                              return Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 4,
                                                      height: 4,
                                                      decoration: BoxDecoration(
                                                        color: isCustom ? Colors.purple.shade600 : Colors.grey.shade600,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Row(
                                                        children: [
                                                          Flexible(
                                                            child: Text(
                                                              '${item['itemName']} × ${item['quantity']}',
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                color: isCustom ? Colors.purple.shade800 : null,
                                                              ),
                                                            ),
                                                          ),
                                                          if (isCustom) ...[
                                                            const SizedBox(width: 6),
                                                            Container(
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
                                                        ],
                                                      ),
                                                    ),
                                                    Text(
                                                      '₦${formatter.format(item['totalAmount'])}',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                        color: isCustom ? Colors.purple.shade800 : null,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            })),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 12),

                                      // Payment Summary
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue.shade200),
                                        ),
                                        child: Column(
                                          children: [
                                            _transactionDetailRow(
                                              'Total Amount',
                                              '₦${formatter.format(transaction['totalAmount'])}',
                                              isBold: true,
                                            ),
                                            const SizedBox(height: 6),
                                            _transactionDetailRow(
                                              'Amount Paid',
                                              '₦${formatter.format(transaction['amountPaid'])}',
                                              color: Colors.green.shade700,
                                            ),
                                            if (transaction['outstandingBalance'] > 0) ...[
                                              const SizedBox(height: 6),
                                              _transactionDetailRow(
                                                'Outstanding Balance',
                                                '₦${formatter.format(transaction['outstandingBalance'])}',
                                                color: Colors.red.shade700,
                                                isBold: true,
                                              ),
                                            ],
                                            const Divider(height: 16),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: transaction['paymentStatus'] == 'Paid'
                                                        ? Colors.green.shade100
                                                        : transaction['paymentStatus'] == 'Part Payment'
                                                            ? Colors.orange.shade100
                                                            : Colors.red.shade100,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    transaction['paymentStatus'],
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: transaction['paymentStatus'] == 'Paid'
                                                          ? Colors.green.shade900
                                                          : transaction['paymentStatus'] == 'Part Payment'
                                                              ? Colors.orange.shade900
                                                              : Colors.red.shade900,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  transaction['paymentMethod'],
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.blue.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodRow(
    String method,
    double amount,
    IconData icon,
    MaterialColor color, {
    bool isTotal = false,
  }) {
    final formatter = NumberFormat('#,##0.00');

    return Row(
      children: [
        Icon(
          icon,
          size: isTotal ? 24 : 20,
          color: color.shade700,
        ),
        const SizedBox(width: 8),
        Text(
          method,
          style: TextStyle(
            fontSize: isTotal ? 15 : 13,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '₦${formatter.format(amount)}',
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: FontWeight.bold,
            color: color.shade700,
          ),
        ),
      ],
    );
  }

  Widget _transactionDetailRow(String label, String value, {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 14 : 13,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
