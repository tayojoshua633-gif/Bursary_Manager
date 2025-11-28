// lib/screens/billing/bill_receipt_screen.dart

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

import 'package:bursary_manager/db/database_helper.dart';
import 'package:bursary_manager/models/student.dart';
import 'package:flutter/rendering.dart';

class BillReceiptScreen extends StatefulWidget {
  final int billId;
  final Student student;

  const BillReceiptScreen({
    super.key,
    required this.billId,
    required this.student,
  });

  @override
  State<BillReceiptScreen> createState() => _BillReceiptScreenState();
}

class _BillReceiptScreenState extends State<BillReceiptScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  Map<String, dynamic>? _school;
  Map<String, dynamic>? _billHeader;

  List<Map<String, dynamic>> _breakdown = [];

  double _billTotal = 0;
  double _previousBalance = 0;
  double _grandTotal = 0;

  bool _loading = true;

  final GlobalKey _receiptKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadReceiptData();
  }

  Future<void> _loadReceiptData() async {
    final db = await _db.database;

    // --------- Load School Profile ----------
    final schoolData = await db.query('school_profile', limit: 1);
    if (schoolData.isNotEmpty) _school = schoolData.first;

    // --------- Load Bill Header (term/session/prevBalance/date) ----------
    final header = await db.query(
      'student_bills',
      where: 'id = ?',
      whereArgs: [widget.billId],
      limit: 1,
    );

    if (header.isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    _billHeader = header.first;
    _billTotal = (_billHeader!['totalAmount'] as num).toDouble();
    _previousBalance = (_billHeader!['previousBalance'] as num?)?.toDouble() ?? 0;
    _grandTotal = _billTotal + _previousBalance;

    // --------- Load Breakdown (normal fees + custom fees with labels) ----------
    final rows = await db.rawQuery('''
      SELECT 
        sfb.amount,
        sfb.label,
        fi.name AS feeName
      FROM student_fee_breakdown sfb
      LEFT JOIN fee_items fi ON fi.id = sfb.feeItemId
      WHERE sfb.billId = ?
    ''', [widget.billId]);

    // Resolve name: feeName for normal items, label for custom fees
    _breakdown = rows.map((r) {
      final feeName = r['feeName'];
      final label = r['label'];

      return {
        'name': (feeName != null && feeName.toString().trim().isNotEmpty)
            ? feeName.toString()
            : (label ?? 'Custom Fee'),
        'amount': (r['amount'] as num).toDouble(),
      };
    }).toList();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  // ========================= SHARE AS IMAGE =========================
  Future<void> _shareReceipt() async {
    if (_receiptKey.currentContext == null) return;

    final boundary =
        _receiptKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    await Share.shareXFiles([
      XFile.fromData(
        pngBytes,
        mimeType: 'image/png',
        name: 'receipt.png',
      ),
    ]);
  }

  // ========================= PRINT AS PDF =========================
  Future<void> _printReceipt() async {
    if (_receiptKey.currentContext == null) return;

    final boundary =
        _receiptKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    final png = byteData!.buffer.asUint8List();

    await Printing.layoutPdf(onLayout: (_) async => png);
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final header = _billHeader;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bill Receipt"),
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: _shareReceipt),
          IconButton(icon: const Icon(Icons.print), onPressed: _printReceipt),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: _receiptKey,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // -------------------- SCHOOL HEADER --------------------
                      if (_school != null) ...[
                        if (_school!['logoPath'] != null)
                          Image.file(
                            File(_school!['logoPath']),
                            height: 80,
                          ),
                        const SizedBox(height: 6),
                        Text(
                          _school!['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_school!['motto'] != null)
                          Text(
                            _school!['motto'],
                            style: const TextStyle(
                                fontSize: 14, fontStyle: FontStyle.italic),
                          ),
                        const SizedBox(height: 6),
                        Text(_school!['address'] ?? ''),
                        Text(_school!['phone'] ?? ''),
                        Text(_school!['email'] ?? ''),
                        const SizedBox(height: 20),
                      ],

                      // -------------------- TITLE --------------------
                      const Text(
                        "STUDENT BILL RECEIPT",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),

                      // -------------------- STUDENT DETAILS --------------------
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Name: ${student.surname} ${student.firstName}"),
                            Text("Admission No: ${student.admissionNo}"),
                            Text("Class ID: ${student.classId}"),
                            Text("Term: ${header?['term'] ?? '-'}"),
                            Text("Session: ${header?['session'] ?? '-'}"),
                            const SizedBox(height: 10),
                            Text(
                              "Bill Date: ${header?['billDate']}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 30),

                      // -------------------- BREAKDOWN --------------------
                      Column(
                        children: _breakdown.map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item['name']),
                                Text("₦${item['amount']}"),
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                      const Divider(height: 30),

                      // -------------------- TOTALS --------------------
                      if (_previousBalance != 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Previous Balance:",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text("₦$_previousBalance"),
                          ],
                        ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Total for This Term:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text("₦$_billTotal"),
                        ],
                      ),

                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "GRAND TOTAL:",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "₦$_grandTotal",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),
                      const Text(
                        "Thank you!",
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
