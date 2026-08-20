// lib/screens/students/siblings_payment_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/backup_reminder_helper.dart';
import '../../utils/central_backup_helper.dart';
import '../../utils/thermal_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../../utils/usb_printer_manager.dart';
import '../../utils/write_guard.dart';
import '../settings/thermal_printer_screen.dart';
import '../settings/usb_printer_screen.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/sms_service.dart';
import '../../utils/family_payment_receipt_pdf_generator.dart';

class SiblingsPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> siblingGroup;
  final List<Map<String, dynamic>> studentsWithFinancials;
  final String activeTerm;
  final String activeSession;
  final Map<String, dynamic>? school;
  final Color groupColor;
  final Map<String, dynamic> currentUser;

  const SiblingsPaymentScreen({
    super.key,
    required this.siblingGroup,
    required this.studentsWithFinancials,
    required this.activeTerm,
    required this.activeSession,
    required this.school,
    required this.groupColor,
    required this.currentUser,
  });

  @override
  State<SiblingsPaymentScreen> createState() => _SiblingsPaymentScreenState();
}

class _SiblingsPaymentScreenState extends State<SiblingsPaymentScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String? _selectedMethod;
  DateTime _selectedDate = DateTime.now();
  bool _saving = false;

  // Snapshot of the note field, taken right before this screen's route is
  // removed from the stack (see _savePayment). The receipt sheet and its
  // print/SMS actions outlive this screen, so they read this instead of
  // _noteCtrl.text — the controller gets disposed once the route is gone.
  String _receiptNote = '';

  // Live split preview: studentId -> allocated amount
  Map<int, double> _splits = {};

  // Per-sibling editable split controllers (eligible siblings only)
  final Map<int, TextEditingController> _splitControllers = {};
  bool _updatingSplits = false;
  bool _manualSplitEnabled = false;

  final List<String> _methods = ['Cash', 'Transfer', 'POS'];
  final NumberFormat _fmt = NumberFormat('#,##0.00');

  // Only siblings with outstanding > 0
  List<Map<String, dynamic>> get _eligibleSiblings => widget.studentsWithFinancials
      .where((s) => ((s['outstanding'] as num?)?.toDouble() ?? 0.0) > 0)
      .toList();

  double get _totalEligibleOutstanding =>
      _eligibleSiblings.fold(0.0, (sum, s) => sum + ((s['outstanding'] as num?)?.toDouble() ?? 0.0));

  double get _groupTotalOutstanding => widget.studentsWithFinancials
      .fold(0.0, (sum, s) => sum + ((s['outstanding'] as num?)?.toDouble() ?? 0.0));

  @override
  void initState() {
    super.initState();
    WriteGuard.enforce(context);
    for (final s in _eligibleSiblings) {
      final id = s['id'] as int;
      _splitControllers[id] = TextEditingController();
    }
    _amountCtrl.addListener(_recomputeSplits);
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_recomputeSplits);
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    for (final ctrl in _splitControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onSplitFieldChanged(int studentId) {
    if (_updatingSplits) return;
    final ctrl = _splitControllers[studentId];
    if (ctrl == null) return;

    final newVal = double.tryParse(ctrl.text.trim()) ?? 0.0;
    final student = widget.studentsWithFinancials.firstWhere(
      (s) => (s['id'] as int) == studentId,
      orElse: () => <String, dynamic>{},
    );
    if (student.isEmpty) return;

    final outstanding = (student['outstanding'] as num?)?.toDouble() ?? 0.0;

    if (_manualSplitEnabled) {
      // Manual mode: user controls each amount independently — no
      // redistribution, and no upper cap, so a sibling can be paid more
      // than their own outstanding (an overpayment/credit for that child).
      final manualVal = newVal.clamp(0.0, double.infinity);
      setState(() => _splits[studentId] = manualVal);
      return;
    }

    final clamped = newVal.clamp(0.0, outstanding);
    final totalEntered = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

    if (totalEntered > 0) {
      // Total is fixed → redistribute remainder among the other eligible siblings
      final remaining = (totalEntered - clamped).clamp(0.0, double.infinity);
      final others = _eligibleSiblings
          .where((s) => (s['id'] as int) != studentId)
          .toList();
      final otherOutstandingTotal = others.fold(
          0.0, (sum, s) => sum + ((s['outstanding'] as num?)?.toDouble() ?? 0.0));

      final Map<int, double> newSplits = {studentId: clamped};

      _updatingSplits = true;
      double rem = remaining;
      for (int i = 0; i < others.length; i++) {
        final otherId = others[i]['id'] as int;
        final otherOutstanding =
            (others[i]['outstanding'] as num?)?.toDouble() ?? 0.0;
        double otherAlloc;
        if (i == others.length - 1) {
          otherAlloc = rem;
        } else {
          otherAlloc = otherOutstandingTotal > 0
              ? (otherOutstanding / otherOutstandingTotal) * remaining
              : 0.0;
          otherAlloc = double.parse(otherAlloc.toStringAsFixed(2));
        }
        otherAlloc = otherAlloc.clamp(0.0, otherOutstanding);
        newSplits[otherId] = otherAlloc;
        _splitControllers[otherId]?.text =
            otherAlloc > 0 ? otherAlloc.toStringAsFixed(2) : '';
        rem -= otherAlloc;
      }
      _updatingSplits = false;

      setState(() => _splits = newSplits);
    } else {
      // No total entered → let the sum of splits flow back into the total field
      final newSplits = Map<int, double>.from(_splits);
      newSplits[studentId] = clamped;
      final total = newSplits.values.fold(0.0, (a, b) => a + b);
      _updatingSplits = true;
      _amountCtrl.text = total > 0 ? total.toStringAsFixed(2) : '';
      _updatingSplits = false;
      setState(() => _splits = newSplits);
    }
  }

  // Auto pro-rata splits land on a clean multiple of ₦100 instead of odd
  // kobo/naira amounts. Only used for the automatic split — Manual mode
  // keeps whatever the user types exactly.
  double _roundToNearestHundred(double value) => (value / 100).round() * 100.0;

  void _recomputeSplits() {
    if (_updatingSplits) return;
    if (_manualSplitEnabled) return;
    final total = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    final eligible = _eligibleSiblings;
    final totalOutstanding = _totalEligibleOutstanding;

    final Map<int, double> newSplits = {};

    if (total <= 0 || eligible.isEmpty || totalOutstanding <= 0) {
      _updatingSplits = true;
      for (final ctrl in _splitControllers.values) {
        ctrl.text = '';
      }
      _updatingSplits = false;
      setState(() => _splits = newSplits);
      return;
    }

    double remaining = total;
    for (int i = 0; i < eligible.length; i++) {
      final studentId = eligible[i]['id'] as int;
      final outstanding = (eligible[i]['outstanding'] as num?)?.toDouble() ?? 0.0;

      double allocated;
      if (i == eligible.length - 1) {
        // Give the exact remainder to the last sibling so the split always
        // sums to the entered total. If the entered total exceeds the
        // family's total outstanding, this remainder exceeds this
        // sibling's own outstanding — that's a deliberate overpayment
        // (credit), so it is NOT clamped away here.
        allocated = remaining.clamp(0.0, double.infinity);
      } else {
        allocated = (outstanding / totalOutstanding) * total;
        allocated = _roundToNearestHundred(allocated);
        // Cap non-final siblings at their own outstanding — don't overpay
        // them; any surplus rolls forward into `remaining` for the last
        // sibling to absorb (see above).
        allocated = allocated.clamp(0.0, outstanding);
      }
      newSplits[studentId] = allocated;
      remaining -= allocated;
    }

    _updatingSplits = true;
    for (final entry in newSplits.entries) {
      _splitControllers[entry.key]?.text =
          entry.value > 0 ? entry.value.toStringAsFixed(2) : '';
    }
    _updatingSplits = false;

    setState(() => _splits = newSplits);
  }

  void _enableManualSplit() {
    setState(() => _manualSplitEnabled = true);
  }

  void _cancelManualSplit() {
    _manualSplitEnabled = false;
    _recomputeSplits(); // reverts splits to match current total
  }

  void _confirmManualSplit() {
    final splitSum = _splits.values.fold(0.0, (a, b) => a + b);
    final totalEntered = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

    if (splitSum <= 0) {
      // Nothing entered — just exit manual mode
      setState(() => _manualSplitEnabled = false);
      return;
    }

    if (totalEntered <= 0 || (splitSum - totalEntered).abs() < 0.01) {
      // No total set yet, or it already matches — confirm and update total
      _updatingSplits = true;
      _amountCtrl.text = splitSum.toStringAsFixed(2);
      _updatingSplits = false;
      setState(() => _manualSplitEnabled = false);
    } else {
      _showSplitMismatchDialog(splitSum, totalEntered);
    }
  }

  void _showSplitMismatchDialog(double splitSum, double totalEntered) {
    final isOver = splitSum > totalEntered;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Amount Mismatch'),
        content: Text(
          'The split total (₦${_fmt.format(splitSum)}) is ${isOver ? 'more' : 'less'} than '
          'the entered total (₦${_fmt.format(totalEntered)}).\n\nWhat would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Auto-update total to match split sum
              _updatingSplits = true;
              _amountCtrl.text = splitSum.toStringAsFixed(2);
              _updatingSplits = false;
              setState(() => _manualSplitEnabled = false);
            },
            child: Text('Update Total to ₦${_fmt.format(splitSum)}'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx), // stay in manual mode
            child: const Text('Re-split'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _cancelManualSplit(); // revert to auto-calculated splits
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _selectedDate,
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _savePayment() async {
    final totalAmount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

    if (totalAmount <= 0) {
      _snack('Enter a valid amount');
      return;
    }
    if (_selectedMethod == null) {
      _snack('Select a payment method');
      return;
    }
    if (_eligibleSiblings.isEmpty) {
      _snack('All siblings are already balanced');
      return;
    }

    setState(() => _saving = true);

    try {
      final List<Map<String, dynamic>> savedPayments = [];

      for (final student in _eligibleSiblings) {
        final studentId = student['id'] as int;
        final allocated = _splits[studentId] ?? 0.0;
        if (allocated <= 0) continue;

        final payment = {
          'studentId': studentId,
          'amount': allocated,
          'method': _selectedMethod,
          'note': _noteCtrl.text.trim().isNotEmpty
              ? '[Family Payment] ${_noteCtrl.text.trim()}'
              : '[Family Payment]',
          'paymentDate': _selectedDate.toIso8601String(),
          'term': widget.activeTerm,
          'session': widget.activeSession,
        };

        final paymentId = await _db.insertPayment(payment);
        savedPayments.add({...payment, 'id': paymentId, 'studentData': student});
      }

      await BackupReminderHelper.incrementTransactionCount();
      CentralBackupHelper.triggerAutoUpload();

      if (!mounted) return;
      setState(() => _saving = false);

      _snack('Family payment recorded successfully', color: Colors.green);

      // _noteCtrl gets disposed once this screen's route is removed below,
      // but the receipt sheet's print/SMS actions need the note afterward.
      _receiptNote = _noteCtrl.text.trim();

      // Capture this screen's own route before showing the sheet, then
      // remove it right after — the sheet (a separate route on top) keeps
      // showing undisturbed, but whatever is now revealed underneath it is
      // the Family page, not this payment form. That way dismissing the
      // sheet by any means (X button, drag-down, back gesture) lands
      // straight on the Family page instead of back on a stale form.
      final navigatorState = Navigator.of(context);
      final myRoute = ModalRoute.of(context);
      _showReceiptSheet(savedPayments, totalAmount);
      if (myRoute != null) {
        navigatorState.removeRoute(myRoute);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Error: $e');
    }
  }

  void _snack(String msg, {Color? color, BuildContext? ctx}) {
    final target = ctx ?? context;
    if (!target.mounted) return;
    ScaffoldMessenger.of(target).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
      ),
    );
  }

  // ── Family account totals after this payment ────────────────────────────────
  // Rolls every sibling's pre-payment billed/paid/outstanding forward by
  // whatever was just paid, so the family summary reflects the fresh balance
  // rather than the snapshot taken when this screen was opened.
  ({double billed, double paidAfter, double outstandingAfter})
      _familyTotalsAfter(List<Map<String, dynamic>> savedPayments) {
    double billed = 0;
    double paidAfter = 0;
    double outstandingAfter = 0;
    for (final student in widget.studentsWithFinancials) {
      final studentId = student['id'] as int;
      final grandTotal = (student['grandTotal'] as num?)?.toDouble() ?? 0.0;
      final priorPaid = (student['totalPaid'] as num?)?.toDouble() ?? 0.0;
      final priorOutstanding = (student['outstanding'] as num?)?.toDouble() ?? 0.0;
      final paidNow = savedPayments
          .where((p) =>
              (p['studentData'] as Map<String, dynamic>)['id'] == studentId)
          .fold(0.0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0.0));
      // Not clamped to 0 — a sibling paid more than they owed should show
      // up as a negative (credit) balance rather than disappearing.
      final newOutstanding = priorOutstanding - paidNow;
      billed += grandTotal;
      paidAfter += priorPaid + paidNow;
      outstandingAfter += newOutstanding;
    }
    return (billed: billed, paidAfter: paidAfter, outstandingAfter: outstandingAfter);
  }

  Widget _summaryChip(String label, double amount, Color color) => Expanded(
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              '₦${_fmt.format(amount)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      );

  // ── Receipt bottom sheet ───────────────────────────────────────────────────

  void _showReceiptSheet(List<Map<String, dynamic>> savedPayments, double totalAmount) {
    final parentName = widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final familySurname = (widget.studentsWithFinancials.isNotEmpty
            ? widget.studentsWithFinancials.first['surname']
            : 'Family') as String? ??
        'Family';
    final familyTotals = _familyTotalsAfter(savedPayments);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade700, Colors.green.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Family Payment Receipt',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'The $familySurname Family',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // Parent info
                  _receiptRow('Parent', parentName),
                  _receiptRow('Phone', widget.siblingGroup['parentPhone'] as String? ?? ''),
                  _receiptRow('Term', widget.activeTerm),
                  _receiptRow('Session', widget.activeSession),
                  _receiptRow('Date', DateFormat('dd MMM yyyy').format(_selectedDate)),
                  _receiptRow('Method', _selectedMethod ?? ''),
                  if (_receiptNote.isNotEmpty) _receiptRow('Note', _receiptNote),
                  const Divider(height: 24),

                  // Per-sibling split
                  Text(
                    'Payment Split',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: widget.groupColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...savedPayments.map((p) {
                    final student = p['studentData'] as Map<String, dynamic>;
                    final name =
                        '${student['surname']} ${student['firstName']}'.trim();
                    final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
                    final outstanding =
                        (student['outstanding'] as num?)?.toDouble() ?? 0.0;
                    // Not clamped to 0 — an overpaid sibling should show as
                    // a credit, not disappear into a fake ₦0.00 balance.
                    final newOutstanding = outstanding - amount;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: widget.groupColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: widget.groupColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    children: [
                                      Text(
                                        newOutstanding >= 0
                                            ? 'New Bal: ₦${_fmt.format(newOutstanding)}'
                                            : 'Credit: ₦${_fmt.format(newOutstanding.abs())}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '₦${_fmt.format(outstanding)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₦${_fmt.format(amount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL PAID',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '₦${_fmt.format(totalAmount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Family Account Summary
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: widget.groupColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: widget.groupColor.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.summarize,
                                size: 16, color: widget.groupColor),
                            const SizedBox(width: 6),
                            Text(
                              'FAMILY ACCOUNT SUMMARY',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: widget.groupColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _summaryChip('Total Billed', familyTotals.billed,
                                Colors.purple),
                            _summaryChip('Total Paid', familyTotals.paidAfter,
                                Colors.green),
                            _summaryChip(
                              'Outstanding',
                              familyTotals.outstandingAfter,
                              familyTotals.outstandingAfter > 0
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Print buttons
                  Text(
                    'Print Receipt',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: widget.groupColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _printReceiptPDF(ctx, savedPayments, totalAmount),
                          icon: const Icon(Icons.picture_as_pdf, size: 18),
                          label: const Text('PDF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _printReceiptThermal(
                              ctx, savedPayments, totalAmount),
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('Thermal'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _printReceiptUsb(ctx, savedPayments, totalAmount),
                          icon: const Icon(Icons.usb, size: 18),
                          label: const Text('USB'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _sendFamilySms(ctx, savedPayments, totalAmount),
                      icon: const Icon(Icons.sms, size: 18),
                      label: const Text('Send SMS'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Combined family SMS ─────────────────────────────────────────────────────

  Future<void> _sendFamilySms(BuildContext sheetContext,
      List<Map<String, dynamic>> savedPayments, double totalAmount) async {
    final parentName = widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone = widget.siblingGroup['parentPhone'] as String?;
    final schoolName = widget.school?['name']?.toString() ?? 'the school';

    final children = savedPayments.map((p) {
      final student = p['studentData'] as Map<String, dynamic>;
      final name = '${student['surname']} ${student['firstName']}'.trim();
      final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
      final outstanding = (student['outstanding'] as num?)?.toDouble() ?? 0.0;
      // Not clamped to 0 — an overpaid sibling shows a negative (credit)
      // balance in the SMS rather than a misleading ₦0.00.
      final newOutstanding = outstanding - amount;
      return FamilyChildSummary(studentName: name, outstanding: newOutstanding);
    }).toList();

    final totalOutstanding =
        children.fold<double>(0.0, (sum, c) => sum + c.outstanding);

    final message = buildFamilySms(
      schoolName: schoolName,
      parentName: parentName,
      children: children,
      totalOutstanding: totalOutstanding,
      term: widget.activeTerm,
      session: widget.activeSession,
    );

    final result = await SmsService.send(
      rawPhone: parentPhone,
      message: message,
      context: 'family_bill',
    );

    if (!sheetContext.mounted) return;
    _snack(
      result.success
          ? (result.requiresManualConfirmation ? 'Messaging app opened — tap Send to deliver it' : 'Family SMS sent to parent')
          : (result.errorMessage ?? 'Failed to send SMS'),
      color: result.success ? Colors.green : null,
      ctx: sheetContext,
    );
    // Done — close the receipt sheet (the payment screen's own route was
    // already removed when the sheet was first shown, so this reveals the
    // Family page).
    Navigator.pop(sheetContext);
  }

  Widget _receiptRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );

  // ── PDF receipt ────────────────────────────────────────────────────────────

  Future<void> _printReceiptPDF(BuildContext sheetContext,
      List<Map<String, dynamic>> savedPayments, double totalAmount) async {
    final parentName =
        widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone =
        widget.siblingGroup['parentPhone'] as String? ?? '';
    final schoolName =
        widget.school?['name']?.toString().toUpperCase() ?? 'SCHOOL NAME';
    final schoolAddress = widget.school?['address']?.toString() ?? '';
    final familySurname = (widget.studentsWithFinancials.isNotEmpty
            ? widget.studentsWithFinancials.first['surname']
            : 'Family') as String? ??
        'Family';

    try {
      _showLoading(sheetContext);
      final familyTotals = _familyTotalsAfter(savedPayments);
      final pdf = FamilyPaymentReceiptPdfGenerator.generate(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        parentName: parentName,
        parentPhone: parentPhone,
        term: widget.activeTerm,
        session: widget.activeSession,
        date: _selectedDate,
        method: _selectedMethod ?? '',
        note: _receiptNote,
        totalAmount: totalAmount,
        familyTotalBilled: familyTotals.billed,
        familyTotalPaid: familyTotals.paidAfter,
        familyOutstanding: familyTotals.outstandingAfter,
        items: savedPayments.map((p) {
          final s = p['studentData'] as Map<String, dynamic>;
          final name = '${s['surname']} ${s['firstName']}'.trim();
          final className = s['className'] ?? '';
          final arm = s['armName'] ?? '';
          final classDisplay = arm.isNotEmpty ? '$className - $arm' : className;
          final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
          return FamilyReceiptPaymentItem(
            studentName: name,
            classDisplay: classDisplay,
            amount: amount,
          );
        }).toList(),
      );

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File(
          '${dir.path}/family_receipt_${familySurname}_$dateStr.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext); // close loading

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Family Payment Receipt - $parentName',
      );

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext); // close the receipt sheet
    } catch (e) {
      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);
      _snack('Error generating PDF: $e', ctx: sheetContext);
    }
  }

  // ── Thermal receipt ────────────────────────────────────────────────────────

  Future<void> _printReceiptThermal(BuildContext sheetContext,
      List<Map<String, dynamic>> savedPayments, double totalAmount) async {
    if (!ThermalPrinterManager.isConnected) {
      _snack('Please connect to a thermal printer first', ctx: sheetContext);
      await NavigationHelper.pushWithSidebar(
        sheetContext,
        page: const ThermalPrinterScreen(),
        currentUser: widget.currentUser,
        pageId: 'student_management/students',
      );
      if (!sheetContext.mounted) return;
      if (!ThermalPrinterManager.isConnected) {
        _snack('Printer not connected. Printing cancelled.',
            color: Colors.orange, ctx: sheetContext);
        return;
      }
    }

    try {
      _showLoading(sheetContext);
      final schoolName = widget.school?['name']?.toString() ?? 'School Name';
      final schoolAddress = widget.school?['address']?.toString() ?? '';
      final parentName =
          widget.siblingGroup['parentName'] as String? ?? 'Parent';
      final parentPhone =
          widget.siblingGroup['parentPhone'] as String? ?? '';

      final List<Map<String, dynamic>> items = savedPayments.map((p) {
        final s = p['studentData'] as Map<String, dynamic>;
        final allocated = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final prevPaid = (s['totalPaid'] as num?)?.toDouble() ?? 0.0;
        final prevOutstanding = (s['outstanding'] as num?)?.toDouble() ?? 0.0;
        final armName = s['armName']?.toString() ?? '';
        final cls = s['className']?.toString() ?? '';
        return {
          'name': '${s['surname']} ${s['firstName']}'.trim(),
          'className': armName.isNotEmpty ? '$cls - $armName' : cls,
          'amount': allocated,
          'totalBill': (s['grandTotal'] as num?)?.toDouble() ?? 0.0,
          'totalPaid': prevPaid + allocated,
          'outstanding': prevOutstanding - allocated,
        };
      }).toList();

      await ThermalPrinterManager.printFamilyPaymentReceipt(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        parentName: parentName,
        parentPhone: parentPhone,
        term: widget.activeTerm,
        session: widget.activeSession,
        method: _selectedMethod ?? '',
        date: DateFormat('dd MMM yyyy').format(_selectedDate),
        note: _receiptNote,
        paymentItems: items,
        totalAmount: totalAmount,
      );
      await PrintCounterHelper.incrementReceiptsPrinted();

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext); // close loading
      _snack('Receipt printed successfully', color: Colors.green, ctx: sheetContext);
      if (sheetContext.mounted) Navigator.pop(sheetContext); // close the receipt sheet
    } catch (e) {
      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);
      _snack('Error printing: $e', ctx: sheetContext);
    }
  }

  // ── USB receipt ────────────────────────────────────────────────────────────

  Future<void> _printReceiptUsb(BuildContext sheetContext,
      List<Map<String, dynamic>> savedPayments, double totalAmount) async {
    if (!UsbPrinterManager.isConnected) {
      _snack('Connect a USB printer first', ctx: sheetContext);
      await Navigator.push(
        sheetContext,
        MaterialPageRoute(builder: (_) => const UsbPrinterScreen()),
      );
      if (!sheetContext.mounted) return;
      if (!UsbPrinterManager.isConnected) {
        _snack('USB printer not connected. Printing cancelled.',
            color: Colors.orange, ctx: sheetContext);
        return;
      }
    }

    try {
      _showLoading(sheetContext);
      final schoolName = widget.school?['name']?.toString() ?? 'School Name';
      final schoolAddress = widget.school?['address']?.toString() ?? '';
      final parentName =
          widget.siblingGroup['parentName'] as String? ?? 'Parent';
      final parentPhone =
          widget.siblingGroup['parentPhone'] as String? ?? '';
      final paperSize = await UsbPrinterManager.getPaperSizeEnum();

      final List<Map<String, dynamic>> items = savedPayments.map((p) {
        final s = p['studentData'] as Map<String, dynamic>;
        final allocated = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final prevPaid = (s['totalPaid'] as num?)?.toDouble() ?? 0.0;
        final prevOutstanding = (s['outstanding'] as num?)?.toDouble() ?? 0.0;
        final armName = s['armName']?.toString() ?? '';
        final cls = s['className']?.toString() ?? '';
        return {
          'name': '${s['surname']} ${s['firstName']}'.trim(),
          'className': armName.isNotEmpty ? '$cls - $armName' : cls,
          'amount': allocated,
          'totalBill': (s['grandTotal'] as num?)?.toDouble() ?? 0.0,
          'totalPaid': prevPaid + allocated,
          'outstanding': prevOutstanding - allocated,
        };
      }).toList();

      await UsbPrinterManager.printFamilyPaymentReceipt(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        parentName: parentName,
        parentPhone: parentPhone,
        term: widget.activeTerm,
        session: widget.activeSession,
        method: _selectedMethod ?? '',
        date: DateFormat('dd MMM yyyy').format(_selectedDate),
        note: _receiptNote,
        paymentItems: items,
        totalAmount: totalAmount,
        paperSize: paperSize,
      );
      await PrintCounterHelper.incrementReceiptsPrinted();

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext); // close loading
      _snack('Receipt printed via USB', color: Colors.green, ctx: sheetContext);
      if (sheetContext.mounted) Navigator.pop(sheetContext); // close the receipt sheet
    } catch (e) {
      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);
      _snack('USB print error: $e', ctx: sheetContext);
    }
  }

  void _showLoading(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final parentName =
        widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone =
        widget.siblingGroup['parentPhone'] as String? ?? '';
    final familySurname = (widget.studentsWithFinancials.isNotEmpty
            ? widget.studentsWithFinancials.first['surname']
            : 'Family') as String? ??
        'Family';
    return Scaffold(
      appBar: AppBar(
        title: Text('Pay — $familySurname Family'),
        backgroundColor: widget.groupColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Parent info card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          widget.groupColor.withValues(alpha: 0.15),
                      child: Icon(Icons.family_restroom,
                          color: widget.groupColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(parentName,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: widget.groupColor)),
                          Text(parentPhone,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${widget.studentsWithFinancials.length} children',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                        Text(
                          '${widget.activeTerm} ${widget.activeSession}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Family outstanding summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _groupTotalOutstanding > 0
                    ? Colors.red.shade50
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _groupTotalOutstanding > 0
                        ? Colors.red.shade200
                        : Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    _groupTotalOutstanding > 0
                        ? Icons.warning_rounded
                        : Icons.check_circle,
                    color: _groupTotalOutstanding > 0
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                  ),
                  const SizedBox(width: 10),
                  const Text('Family Outstanding:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    '₦${_fmt.format(_groupTotalOutstanding)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _groupTotalOutstanding > 0
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Payment form
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade50, Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add_card,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('RECORD FAMILY PAYMENT',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.green)),
                          Text('Amount will be split pro-rata',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Amount field
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Total Amount',
                      prefixText: '₦',
                      prefixIcon: const Icon(Icons.money),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.green.shade50,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Method
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Payment Method',
                      prefixIcon: const Icon(Icons.payment),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: _methods
                        .map((m) => DropdownMenuItem<String>(
                            value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedMethod = v),
                  ),
                  const SizedBox(height: 14),

                  // Date
                  TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Payment Date',
                      prefixIcon: const Icon(Icons.calendar_today),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar),
                        onPressed: _pickDate,
                      ),
                    ),
                    controller: TextEditingController(
                      text: DateFormat('EEEE, MMM dd, yyyy')
                          .format(_selectedDate),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Note
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Note (Optional)',
                      prefixIcon: const Icon(Icons.note),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Split preview
            if (_eligibleSiblings.isNotEmpty) ...[
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: widget.groupColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Payment Split Preview',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: widget.groupColor,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _manualSplitEnabled ? null : _enableManualSplit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _manualSplitEnabled
                            ? widget.groupColor
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _manualSplitEnabled
                                ? Icons.edit
                                : Icons.edit_outlined,
                            size: 13,
                            color: _manualSplitEnabled
                                ? Colors.white
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _manualSplitEnabled ? 'Manual ON' : 'Manual',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _manualSplitEnabled
                                  ? Colors.white
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _manualSplitEnabled
                    ? 'Edit each child\'s amount below, then tap OK when done.'
                    : 'Split is calculated pro-rata. Tap Manual to override.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 10),
              ...widget.studentsWithFinancials.map((student) {
                final studentId = student['id'] as int;
                final outstanding =
                    (student['outstanding'] as num?)?.toDouble() ?? 0.0;
                final allocated = _splits[studentId] ?? 0.0;
                // Not clamped to 0 — allocating more than this sibling's
                // outstanding is a deliberate overpayment, which should
                // show as a credit rather than a misleading ₦0.00.
                final newOutstanding = outstanding - allocated;
                final fullName =
                    '${student['surname']} ${student['firstName']}'.trim();
                final hasOutstanding = outstanding > 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: hasOutstanding
                        ? widget.groupColor.withValues(alpha: 0.05)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: hasOutstanding
                            ? widget.groupColor.withValues(alpha: 0.25)
                            : Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: hasOutstanding
                                    ? widget.groupColor
                                    : Colors.grey.shade400,
                              ),
                            ),
                            if (hasOutstanding)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: allocated > 0
                                    ? Row(
                                        children: [
                                          Text(
                                            newOutstanding >= 0
                                                ? '₦${_fmt.format(newOutstanding)}'
                                                : 'Credit ₦${_fmt.format(newOutstanding.abs())}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green.shade700,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '₦${_fmt.format(outstanding)}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade500,
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        'Outstanding: ₦${_fmt.format(outstanding)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                              )
                            else
                              Text(
                                'Balanced ✓',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.green.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (hasOutstanding)
                        SizedBox(
                          width: 160,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_manualSplitEnabled)
                                TextField(
                                  controller: _splitControllers[studentId],
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.right,
                                  onChanged: (_) => _onSplitFieldChanged(studentId),
                                  decoration: InputDecoration(
                                    prefixText: '₦',
                                    prefixStyle: const TextStyle(fontSize: 18),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(
                                          color: widget.groupColor, width: 1.5),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.green.shade700,
                                  ),
                                )
                              else
                                Text(
                                  allocated > 0
                                      ? '₦${_fmt.format(allocated)}'
                                      : '—',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    color: allocated > 0
                                        ? Colors.green.shade700
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              if (allocated > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    '${((allocated / outstanding) * 100).toStringAsFixed(0)}% of bill',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500),
                                  ),
                                ),
                            ],
                          ),
                        )
                      else
                        Text(
                          '₦0.00',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: Colors.grey.shade400,
                          ),
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              if (_splits.values.any((v) => v > 0))
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total to be recorded:',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            '₦${_fmt.format(_splits.values.fold(0.0, (a, b) => a + b))}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Outstanding:',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            '₦${_fmt.format((_groupTotalOutstanding - _splits.values.fold(0.0, (a, b) => a + b)).clamp(0.0, _groupTotalOutstanding))}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_manualSplitEnabled) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _cancelManualSplit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _confirmManualSplit,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('OK — Confirm Split'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.groupColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],

            if (_eligibleSiblings.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'All siblings are fully balanced for this term.',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: (_saving || _eligibleSiblings.isEmpty || _manualSplitEnabled)
                    ? null
                    : _savePayment,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 24),
                label: Text(
                  _saving ? 'Saving...' : 'Save Payment & View Receipt',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
