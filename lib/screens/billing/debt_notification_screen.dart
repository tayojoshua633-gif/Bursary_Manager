// lib/screens/billing/debt_notification_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/debt_notification_pdf_generator.dart';

class DebtNotificationScreen extends StatefulWidget {
  final Map<String, dynamic> schoolProfile;
  final String studentName;
  final String admissionNo;
  final String className;
  final String term;
  final String session;
  final double totalBills;
  final double totalPaid;
  final double outstanding;
  final String initialOpening;
  final String initialClosing;
  final DateTime? initialDate;
  final String initialSignatory;
  final DateTime? initialDeadline;
  final bool isLastTerm;
  final bool isZeroPayment;
  final bool isPta;
  final bool isMidTerm;
  final DateTime? ptaMeetingDate;
  final String ptaMeetingTime;
  final String ptaVenue;
  final DateTime? midTermStartDate;
  final DateTime? midTermReturnDate;

  const DebtNotificationScreen({
    super.key,
    required this.schoolProfile,
    required this.studentName,
    required this.admissionNo,
    required this.className,
    required this.term,
    required this.session,
    required this.totalBills,
    required this.totalPaid,
    required this.outstanding,
    this.initialOpening = '',
    this.initialClosing = '',
    this.initialDate,
    this.initialSignatory = '',
    this.initialDeadline,
    this.isLastTerm = false,
    this.isZeroPayment = false,
    this.isPta = false,
    this.isMidTerm = false,
    this.ptaMeetingDate,
    this.ptaMeetingTime = '',
    this.ptaVenue = '',
    this.midTermStartDate,
    this.midTermReturnDate,
  });

  @override
  State<DebtNotificationScreen> createState() =>
      _DebtNotificationScreenState();
}

class _DebtNotificationScreenState extends State<DebtNotificationScreen> {
  final _currency = NumberFormat('#,##0.00');

  late DateTime _letterDate;
  DateTime? _deadline;
  late final TextEditingController _signatoryController;
  late final TextEditingController _openingController;
  late final TextEditingController _closingController;

  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _letterDate = widget.initialDate ?? DateTime.now();
    _deadline = widget.initialDeadline;
    _signatoryController =
        TextEditingController(text: widget.initialSignatory);
    _openingController =
        TextEditingController(text: widget.initialOpening);
    _closingController =
        TextEditingController(text: widget.initialClosing);
  }

  @override
  void dispose() {
    _signatoryController.dispose();
    _openingController.dispose();
    _closingController.dispose();
    super.dispose();
  }

  // ── Date pickers ───────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _letterDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _letterDate = picked);
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _deadline = picked);
  }

  // ── Generate PDF ───────────────────────────────────────────────────────────

  Future<({Uint8List bytes, String? filePath})> _generatePdf(
      {required bool saveToFile}) {
    return DebtNotificationPdfGenerator.generate(
      schoolProfile: widget.schoolProfile,
      studentName: widget.studentName,
      admissionNo: widget.admissionNo,
      className: widget.className,
      term: widget.term,
      session: widget.session,
      totalBills: widget.totalBills,
      totalPaid: widget.totalPaid,
      outstanding: widget.outstanding,
      letterDate: _letterDate,
      signatoryName: _signatoryController.text,
      customOpening: _openingController.text,
      customClosing: _closingController.text,
      paymentDeadline: _deadline,
      saveToFile: saveToFile,
      isLastTerm: widget.isLastTerm,
      isZeroPayment: widget.isZeroPayment,
      isPta: widget.isPta,
      isMidTerm: widget.isMidTerm,
      ptaMeetingDate: widget.ptaMeetingDate,
      ptaMeetingTime: widget.ptaMeetingTime,
      ptaVenue: widget.ptaVenue,
      midTermStartDate: widget.midTermStartDate,
      midTermReturnDate: widget.midTermReturnDate,
    );
  }

  // ── Export & share ─────────────────────────────────────────────────────────

  Future<void> _exportAndShare() async {
    setState(() => _generating = true);
    try {
      final result = await _generatePdf(saveToFile: true);
      if (!mounted) return;
      if (result.filePath != null) {
        await Share.shareXFiles(
          [XFile(result.filePath!)],
          subject: 'Debt Notification — ${widget.studentName}',
          text:
              'Kindly find attached the debt notification letter for ${widget.studentName}.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ── Preview ────────────────────────────────────────────────────────────────

  Future<void> _previewPdf() async {
    setState(() => _generating = true);
    try {
      final result = await _generatePdf(saveToFile: false);
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => result.bytes,
        name: 'DebtNotification_${widget.studentName}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preview failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debt Notification Letter'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (!_generating)
            IconButton(
              icon: const Icon(Icons.visibility),
              tooltip: 'Preview PDF',
              onPressed: _previewPdf,
            ),
        ],
      ),
      body: _generating
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating letter…'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Summary card ───────────────────────────────────────
                  _summaryCard(),
                  const SizedBox(height: 20),

                  // ── Letter date ────────────────────────────────────────
                  _sectionLabel('Letter Date'),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                      child: Text(
                        DateFormat('d MMMM, yyyy').format(_letterDate),
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Payment deadline ───────────────────────────────────
                  _sectionLabel('Payment Deadline (optional)'),
                  const SizedBox(height: 4),
                  Text(
                    'If set, the letter will say "on or before [date]".',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickDeadline,
                          borderRadius: BorderRadius.circular(8),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              suffixIcon:
                                  Icon(Icons.event, size: 18),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                            ),
                            child: Text(
                              _deadline != null
                                  ? DateFormat('d MMMM, yyyy')
                                      .format(_deadline!)
                                  : 'No deadline set',
                              style: TextStyle(
                                fontSize: 15,
                                color: _deadline != null
                                    ? Colors.black87
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_deadline != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Remove deadline',
                          onPressed: () =>
                              setState(() => _deadline = null),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Signatory name ─────────────────────────────────────
                  _sectionLabel('Signatory Name (optional)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _signatoryController,
                    decoration: const InputDecoration(
                      hintText:
                          'e.g. Mr. John Eze (defaults to school name)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Custom opening paragraph ───────────────────────────
                  _sectionLabel('Opening Paragraph (optional)'),
                  const SizedBox(height: 4),
                  Text(
                    'Leave blank to use the default text.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _openingController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Custom opening paragraph…',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Custom closing paragraph ───────────────────────────
                  _sectionLabel('Closing Paragraph (optional)'),
                  const SizedBox(height: 4),
                  Text(
                    'Leave blank to use the default text.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _closingController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Custom closing paragraph…',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Action buttons ─────────────────────────────────────
                  ElevatedButton.icon(
                    onPressed: _previewPdf,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Preview Letter'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _exportAndShare,
                    icon: const Icon(Icons.share),
                    label: const Text('Export & Share PDF'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.red.shade700),
              const SizedBox(width: 8),
              Text(
                'Outstanding Balance',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryRow('Student', widget.studentName),
          _summaryRow('Admission No.', widget.admissionNo),
          _summaryRow('Class', widget.className),
          _summaryRow(
              'Term / Session', '${widget.term}  •  ${widget.session}'),
          const Divider(height: 20),
          _summaryRow(
              'Total Bills', 'N${_currency.format(widget.totalBills)}'),
          _summaryRow(
              'Amount Paid', 'N${_currency.format(widget.totalPaid)}'),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Outstanding',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.red.shade800,
                ),
              ),
              Text(
                'N${_currency.format(widget.outstanding)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.red.shade800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
