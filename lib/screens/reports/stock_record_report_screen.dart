// lib/screens/reports/stock_record_report_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/stock_record_pdf_generator.dart';

class StockRecordReportScreen extends StatefulWidget {
  const StockRecordReportScreen({super.key});

  @override
  State<StockRecordReportScreen> createState() => _StockRecordReportScreenState();
}

class _StockRecordReportScreenState extends State<StockRecordReportScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _stockRecords = [];
  Map<String, dynamic>? _school;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStockRecords();
  }

  Future<void> _loadStockRecords() async {
    setState(() => _loading = true);

    try {
      _school = await _db.getSchoolProfile();
      final stockItems = await _db.getStockItems();
      final allSales = await _db.getAllSales();

      // Build comprehensive stock records
      final List<Map<String, dynamic>> records = [];

      for (final item in stockItems) {
        final stockItemId = item['id'];
        final itemName = item['itemName'];
        final supplierName = item['supplierName'];
        final costPrice = (item['costPrice'] as num).toDouble();
        final sellingPrice = (item['sellingPrice'] as num).toDouble();
        final currentQuantity = item['currentQuantity'] as int;

        // Calculate total supplied (we don't track this separately, so use current + sold)
        final qtySold = allSales
            .where((sale) => sale['stockItemId'] == stockItemId)
            .fold<int>(0, (sum, sale) => sum + (sale['quantity'] as int));

        final qtySupplied = currentQuantity + qtySold;
        final qtyRemaining = currentQuantity;

        // Calculate values
        final totalCostValue = qtySupplied * costPrice;
        final totalSellingValue = qtySupplied * sellingPrice;
        final soldValue = qtySold * sellingPrice;
        final remainingValue = qtyRemaining * sellingPrice;

        records.add({
          'itemName': itemName,
          'supplierName': supplierName,
          'qtySupplied': qtySupplied,
          'qtySold': qtySold,
          'qtyRemaining': qtyRemaining,
          'costPrice': costPrice,
          'sellingPrice': sellingPrice,
          'totalCostValue': totalCostValue,
          'totalSellingValue': totalSellingValue,
          'soldValue': soldValue,
          'remainingValue': remainingValue,
        });
      }

      setState(() {
        _stockRecords = records;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading stock records: $e')),
      );
    }
  }

  Future<void> _exportPDF() async {
    if (_stockRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stock records to export')),
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
      final pdfPath = await StockRecordPDFGenerator.generateStockRecordPDF(
        stockRecords: _stockRecords,
        schoolProfile: _school ?? {},
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      // Share PDF
      await Share.shareXFiles(
        [XFile(pdfPath)],
        subject: 'Stock Record Report - ${DateFormat('MMMM d, yyyy').format(DateTime.now())}',
        text: 'Stock Record Report',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Record Report'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _stockRecords.isNotEmpty ? _exportPDF : null,
            tooltip: 'Export PDF',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStockRecords,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stockRecords.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No stock records found',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.brown.shade50, Colors.orange.shade50],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border(
                          bottom: BorderSide(color: Colors.brown.shade200),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.summarize_outlined, color: Colors.brown.shade700),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stock Movement Report',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.brown.shade900,
                                ),
                              ),
                              Text(
                                '${_stockRecords.length} items',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Table
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(Colors.brown.shade100),
                            border: TableBorder.all(color: Colors.grey.shade300),
                            columns: const [
                              DataColumn(label: Text('Item Name', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Supplier', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Qty Supplied', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Qty Sold', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Qty Remain', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Cost Price', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Selling Price', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Stock Value', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: _stockRecords.map((record) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(record['itemName'])),
                                  DataCell(Text(record['supplierName'])),
                                  DataCell(Text('${record['qtySupplied']}')),
                                  DataCell(Text('${record['qtySold']}')),
                                  DataCell(Text(
                                    '${record['qtyRemaining']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: record['qtyRemaining'] > 0 ? Colors.green : Colors.red,
                                    ),
                                  )),
                                  DataCell(Text('₦${formatter.format(record['costPrice'])}')),
                                  DataCell(Text('₦${formatter.format(record['sellingPrice'])}')),
                                  DataCell(Text(
                                    '₦${formatter.format(record['remainingValue'])}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  )),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
