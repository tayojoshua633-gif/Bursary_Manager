// lib/screens/students/siblings_payment_history_screen.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/thermal_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../../utils/usb_printer_manager.dart';
import '../settings/thermal_printer_screen.dart';
import '../settings/usb_printer_screen.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/permission_helper.dart';
import '../../utils/payment_date_time_formatter.dart';
import '../../utils/sms_service.dart';
import '../../utils/family_payment_receipt_pdf_generator.dart';

class SiblingsPaymentHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> siblingGroup;
  final String activeTerm;
  final String activeSession;
  final Color groupColor;
  final Map<String, dynamic> currentUser;

  const SiblingsPaymentHistoryScreen({
    super.key,
    required this.siblingGroup,
    required this.activeTerm,
    required this.activeSession,
    required this.groupColor,
    required this.currentUser,
  });

  @override
  State<SiblingsPaymentHistoryScreen> createState() =>
      _SiblingsPaymentHistoryScreenState();
}

class _SiblingsPaymentHistoryScreenState
    extends State<SiblingsPaymentHistoryScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final NumberFormat _fmt = NumberFormat('#,##0.00');

  bool _loading = true;
  bool _canEditPayments = false;
  Map<String, dynamic>? _school;

  // Each entry: { student, payments, totalPaid, grandTotal, outstanding, previousBalance, currentTermBill }
  List<Map<String, dynamic>> _siblingData = [];

  // Payments grouped as they were actually paid: one entry per family-split
  // transaction (all siblings paid together) or per standalone/individual
  // payment. Each entry: { paymentDate, method, isFamily, note, items }
  // where items: [{ student, amount }].
  List<Map<String, dynamic>> _paymentGroups = [];
  final Map<int, Map<String, dynamic>> _lastEditByPaymentId = {};

  double _groupTotalBills = 0;
  double _groupTotalPaid = 0;
  double _groupTotalOutstanding = 0;

  @override
  void initState() {
    super.initState();
    _checkEditPermission();
    _loadData();
  }

  Future<void> _checkEditPermission() async {
    final canEdit =
        await PermissionHelper.hasPermission(widget.currentUser, 'payments_edit');
    if (mounted) setState(() => _canEditPayments = canEdit);
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final db = await _db.database;
      _school = await _db.getSchoolProfile();

      final students =
          widget.siblingGroup['students'] as List<Map<String, dynamic>>;
      final List<Map<String, dynamic>> siblingData = [];
      double groupBills = 0, groupPaid = 0, groupOutstanding = 0;

      for (final student in students) {
        final studentId = student['id'] as int;

        final previousBalance = await _db.computeOutstandingBeforeTerm(
          studentId,
          term: widget.activeTerm,
          session: widget.activeSession,
        );

        final bill = await _db.getBillForStudent(
            studentId, widget.activeTerm, widget.activeSession);

        double currentTermBill = 0;
        double grandTotal = previousBalance;

        if (bill != null) {
          final storedTotal =
              (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final storedPrev =
              (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;
          currentTermBill = storedTotal - storedPrev;
          grandTotal = previousBalance + currentTermBill;
        }

        final payRows = await db.query(
          'payments',
          where: 'studentId = ? AND term = ? AND session = ?',
          whereArgs: [
            studentId,
            widget.activeTerm,
            widget.activeSession,
          ],
          orderBy: 'paymentDate ASC',
        );

        final payments =
            payRows.map((r) => Map<String, dynamic>.from(r)).toList();
        final totalPaid = payments.fold<double>(
            0.0,
            (sum, p) =>
                sum + ((p['amount'] as num?)?.toDouble() ?? 0.0));
        final outstanding = grandTotal - totalPaid;

        siblingData.add({
          'student': student,
          'payments': payments,
          'totalPaid': totalPaid,
          'grandTotal': grandTotal,
          'outstanding': outstanding,
          'previousBalance': previousBalance,
          'currentTermBill': currentTermBill,
        });

        groupBills += grandTotal;
        groupPaid += totalPaid;
        groupOutstanding += outstanding;
      }

      final paymentGroups = _buildPaymentGroups(siblingData);

      // Load latest edit (if any) per payment, so an "Edited by ..." badge
      // can be shown inline next to that sibling's amount
      final lastEdits = <int, Map<String, dynamic>>{};
      for (final data in siblingData) {
        final payments = data['payments'] as List<Map<String, dynamic>>;
        for (final p in payments) {
          final paymentId = p['id'] as int?;
          if (paymentId == null) continue;
          final entries =
              await _db.getAuditLog(entityType: 'payment', entityId: paymentId);
          final lastUpdate = entries.firstWhere(
            (e) => e['action'] == 'update',
            orElse: () => const {},
          );
          if (lastUpdate.isNotEmpty) {
            lastEdits[paymentId] = lastUpdate;
          }
        }
      }

      if (mounted) {
        setState(() {
          _siblingData = siblingData;
          _paymentGroups = paymentGroups;
          _groupTotalBills = groupBills;
          _groupTotalPaid = groupPaid;
          _groupTotalOutstanding = groupOutstanding;
          _lastEditByPaymentId
            ..clear()
            ..addAll(lastEdits);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading siblings payment history: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // Regroups the flat per-student payment lists back into the transactions
  // they were actually paid as: every sibling paid together in one family
  // split lands in the same group; a payment made for just one student
  // (outside the split screen) stands alone.
  List<Map<String, dynamic>> _buildPaymentGroups(
      List<Map<String, dynamic>> siblingData) {
    final Map<String, Map<String, dynamic>> groups = {};

    for (final data in siblingData) {
      final student = data['student'] as Map<String, dynamic>;
      final payments = data['payments'] as List<Map<String, dynamic>>;

      for (final p in payments) {
        final rawNote = (p['note'] as String?)?.trim() ?? '';
        final isFamily = rawNote == '[Family Payment]' ||
            rawNote.startsWith('[Family Payment] ');
        final method = p['method'] as String? ?? '';
        final paymentDate = p['paymentDate'] as String? ?? '';
        final displayNote = isFamily
            ? rawNote.replaceFirst('[Family Payment]', '').trim()
            : rawNote;

        // Family-split payments made in the same batch share the exact same
        // paymentDate + method, so that pair is a reliable grouping key.
        // Non-family payments always stand alone, keyed by their own row id.
        final key = isFamily
            ? 'fam|$paymentDate|$method'
            : 'single|${p['id']}';

        final entry = groups.putIfAbsent(key, () => {
              'paymentDate': paymentDate,
              'method': method,
              'isFamily': isFamily,
              'note': displayNote,
              'items': <Map<String, dynamic>>[],
            });
        (entry['items'] as List<Map<String, dynamic>>).add({
          'id': p['id'] as int,
          'student': student,
          'amount': (p['amount'] as num?)?.toDouble() ?? 0.0,
          'method': method,
          'paymentDate': paymentDate,
          'note': rawNote,
        });
      }
    }

    final list = groups.values.toList();
    list.sort((a, b) {
      final da = DateTime.tryParse(a['paymentDate'] as String? ?? '') ??
          DateTime(1970);
      final db = DateTime.tryParse(b['paymentDate'] as String? ?? '') ??
          DateTime(1970);
      return db.compareTo(da); // newest first
    });
    return list;
  }

  void _showAuditDiffDialog(Map<String, dynamic> auditEntry) {
    final changesRaw = auditEntry['changes'] as String?;
    Map<String, dynamic> diff = {};
    if (changesRaw != null && changesRaw.isNotEmpty) {
      try {
        diff = Map<String, dynamic>.from(jsonDecode(changesRaw) as Map);
      } catch (_) {}
    }
    final username = auditEntry['username']?.toString() ?? 'Unknown';
    final timestamp = DateTime.tryParse(auditEntry['timestamp']?.toString() ?? '');
    final formattedWhen = timestamp != null
        ? DateFormat('dd/MM/yyyy, h:mm a').format(timestamp)
        : '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, color: Colors.orange),
            SizedBox(width: 8),
            Text('Edit History'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edited by $username',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (formattedWhen.isNotEmpty)
                Text(formattedWhen,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              ...diff.entries.map((e) {
                final change = e.value as Map;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${e.key}: ${change['old']} → ${change['new']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Deletes every payment row in a transaction group at once — a single
  // payment deletes its one row, a family split deletes every sibling's
  // row together so the whole transaction is removed cleanly.
  Future<void> _showDeleteGroupDialog(Map<String, dynamic> group) async {
    final items = group['items'] as List<Map<String, dynamic>>;
    final isMultiStudent = items.length > 1;
    final total = items.fold<double>(
        0.0, (sum, it) => sum + ((it['amount'] as num?)?.toDouble() ?? 0.0));
    final parsedDate =
        DateTime.tryParse(group['paymentDate'] as String? ?? '') ??
            DateTime.now();
    final formattedDate = DateFormat('dd MMM yyyy').format(parsedDate);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Payment?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isMultiStudent
                ? 'Delete this family payment of ₦${_fmt.format(total)} '
                    '(${items.length} siblings) on $formattedDate?'
                : 'Delete this payment of ₦${_fmt.format(total)} '
                    'on $formattedDate?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This action cannot be undone!',
                      style: TextStyle(
                          color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Delete Payment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      for (final it in items) {
        await _db.deletePayment(it['id'] as int);
      }
      await _loadData();
      if (mounted) _snack('Payment deleted successfully', color: Colors.green);
    } catch (e) {
      if (mounted) _snack('Failed to delete payment: $e');
    }
  }

  // Edits every row in a transaction group at once: shared date/method/note
  // apply to all rows, while each sibling's amount (for family splits)
  // stays individually adjustable.
  Future<void> _showEditGroupDialog(Map<String, dynamic> group) async {
    final items = group['items'] as List<Map<String, dynamic>>;
    const methods = ['Cash', 'Transfer', 'POS'];
    String selectedMethod = group['method'] as String? ?? 'Cash';
    if (!methods.contains(selectedMethod)) selectedMethod = methods.first;
    DateTime selectedDate =
        DateTime.tryParse(group['paymentDate'] as String? ?? '') ??
            DateTime.now();
    final noteController =
        TextEditingController(text: group['note'] as String? ?? '');

    final Map<int, TextEditingController> amountControllers = {
      for (final it in items)
        it['id'] as int: TextEditingController(
          text:
              (it['amount'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00',
        ),
    };

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final total = amountControllers.values.fold<double>(
              0.0, (sum, c) => sum + (double.tryParse(c.text.trim()) ?? 0.0));

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.edit_note, color: Colors.orange),
                SizedBox(width: 8),
                Text('Edit Family Payment'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SHARED DETAILS',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment Method',
                        border: OutlineInputBorder(),
                      ),
                      items: methods
                          .map((m) =>
                              DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => selectedMethod = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Payment Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child:
                            Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Note (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('PER-SIBLING AMOUNT',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    ...items.map((it) {
                      final student = it['student'] as Map<String, dynamic>;
                      final name =
                          '${student['surname']} ${student['firstName']}'
                              .trim();
                      final ctrl = amountControllers[it['id'] as int]!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: name,
                            prefixText: '₦',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      );
                    }),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('₦${_fmt.format(total)}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final Map<int, double> amounts = {};
                  for (final entry in amountControllers.entries) {
                    final val = double.tryParse(entry.value.text.trim()) ?? -1;
                    if (val <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content:
                              Text('Enter a valid amount for every sibling')));
                      return;
                    }
                    amounts[entry.key] = val;
                  }

                  final noteText = noteController.text.trim();
                  final newNote = noteText.isNotEmpty
                      ? '[Family Payment] $noteText'
                      : '[Family Payment]';

                  for (final id in amounts.keys) {
                    await _db.updatePayment(id, {
                      'amount': amounts[id],
                      'method': selectedMethod,
                      'paymentDate': selectedDate.toIso8601String(),
                      'note': newNote,
                    });
                  }

                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  await _loadData();
                  if (mounted) {
                    _snack('Family payment updated successfully',
                        color: Colors.green);
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final students =
        widget.siblingGroup['students'] as List<Map<String, dynamic>>;
    final familySurname = students.isNotEmpty
        ? (students.first['surname'] as String? ?? 'Family')
        : 'Family';
    final parentName =
        widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone =
        widget.siblingGroup['parentPhone'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text('$familySurname Family — History'),
        backgroundColor: widget.groupColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print History',
            onPressed: _showPrintOptions,
          ),
          if (widget.activeTerm.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.activeTerm,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                              backgroundColor: widget.groupColor
                                  .withValues(alpha: 0.15),
                              child: Icon(Icons.family_restroom,
                                  color: widget.groupColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
                            Text(
                              '${widget.activeTerm}\n${widget.activeSession}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Family summary — boxed section, consistent with the
                    // sections below it.
                    _sectionCard(
                      icon: Icons.summarize,
                      title: 'FAMILY SUMMARY',
                      subtitle: '${widget.activeTerm} · ${widget.activeSession}',
                      child: Row(
                        children: [
                          _summaryChip('Total Billed',
                              _groupTotalBills, Colors.purple),
                          _summaryChip(
                              'Total Paid', _groupTotalPaid, Colors.green),
                          _summaryChip(
                            'Outstanding',
                            _groupTotalOutstanding,
                            _groupTotalOutstanding > 0
                                ? Colors.red
                                : Colors.green,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Student Balances — boxed section with its own header
                    // banner so it reads as a distinct block while scrolling.
                    _sectionCard(
                      icon: Icons.people_alt,
                      title: 'STUDENT BALANCES',
                      subtitle:
                          '${_siblingData.length} student${_siblingData.length == 1 ? '' : 's'}',
                      child: Column(
                        children: _siblingData
                            .map((data) => _buildStudentBalanceCard(data))
                            .toList(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Payment History — one boxed section, grouped exactly
                    // as each payment was actually made.
                    _sectionCard(
                      icon: Icons.receipt_long,
                      title: 'PAYMENT HISTORY',
                      subtitle: _paymentGroups.isEmpty
                          ? 'No payments recorded this term'
                          : '${_paymentGroups.length} ${_paymentGroups.length == 1 ? 'entry' : 'entries'} — siblings paid together appear as one entry',
                      child: _paymentGroups.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 16, color: Colors.grey.shade400),
                                  const SizedBox(width: 8),
                                  Text(
                                    'No payments recorded this term',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              children: _paymentGroups
                                  .map((g) => _buildPaymentGroupCard(g))
                                  .toList(),
                            ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  // Boxed section with a solid colored header banner (icon, title,
  // subtitle) so each major block of the page is unmistakable at a glance
  // while scrolling — mirrors the header-strip pattern used on the
  // individual Record Payment screen.
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.groupColor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: widget.groupColor,
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, double amount, Color color) =>
      Expanded(
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              '₦${_fmt.format(amount)}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
          ],
        ),
      );

  // Compact per-student balance card — billed/paid/outstanding only.
  // The actual payment rows now live in the grouped payment history below.
  Widget _buildStudentBalanceCard(Map<String, dynamic> data) {
    final student = data['student'] as Map<String, dynamic>;
    final totalPaid = (data['totalPaid'] as num?)?.toDouble() ?? 0.0;
    final grandTotal = (data['grandTotal'] as num?)?.toDouble() ?? 0.0;
    final outstanding = (data['outstanding'] as num?)?.toDouble() ?? 0.0;
    final previousBalance =
        (data['previousBalance'] as num?)?.toDouble() ?? 0.0;
    final currentTermBill =
        (data['currentTermBill'] as num?)?.toDouble() ?? 0.0;

    final fullName =
        '${student['surname']} ${student['firstName']}'.trim();
    final className = student['className'] ?? 'N/A';
    final armName = student['armName'] ?? '';
    final classDisplay =
        armName.isNotEmpty ? '$className - $armName' : className;
    final gender = student['gender'] ?? 'Male';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: gender == 'Male'
                      ? Colors.blue.shade100
                      : Colors.pink.shade100,
                  child: Icon(
                    gender == 'Male' ? Icons.boy : Icons.girl,
                    size: 16,
                    color: gender == 'Male'
                        ? Colors.blue.shade700
                        : Colors.pink.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fullName,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: widget.groupColor)),
                      Text(classDisplay,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: outstanding > 0
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: outstanding > 0
                            ? Colors.red.shade200
                            : Colors.green.shade200),
                  ),
                  child: Text(
                    outstanding > 0 ? 'OWING' : 'BALANCED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: outstanding > 0
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _miniStat('Billed', grandTotal, Colors.purple),
                _miniStat('Paid', totalPaid, Colors.green),
                _miniStat(
                    'Outstanding',
                    outstanding,
                    outstanding > 0 ? Colors.red : Colors.green),
              ],
            ),
            if (previousBalance > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history,
                        size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Prev. Balance: ₦${_fmt.format(previousBalance)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700),
                      ),
                    ),
                    Text(
                      'Term Fees: ₦${_fmt.format(currentTermBill)}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // One card per actual payment transaction — every sibling paid together
  // in a family split renders as a single card; a payment made for just
  // one student stands on its own.
  Widget _buildPaymentGroupCard(Map<String, dynamic> group) {
    final items = group['items'] as List<Map<String, dynamic>>;
    final isFamily = group['isFamily'] as bool? ?? false;
    final method = group['method'] as String? ?? '';
    final note = group['note'] as String? ?? '';
    final rawDate = group['paymentDate'] as String? ?? '';
    final displayDate = formatPaymentDateOnly(rawDate);
    final displayTime = formatPaymentTimeOnly(rawDate);

    final total = items.fold<double>(
        0.0, (sum, it) => sum + ((it['amount'] as num?)?.toDouble() ?? 0.0));
    final isMultiStudent = items.length > 1;
    final singleStudent =
        items.length == 1 ? items.first['student'] as Map<String, dynamic> : null;
    final title = isFamily
        ? 'Family Payment'
        : (singleStudent != null
            ? '${singleStudent['surname']} ${singleStudent['firstName']}'
                .trim()
            : 'Payment');
    final methodColor = method == 'Cash'
        ? Colors.green
        : method == 'Transfer'
            ? Colors.blue
            : Colors.purple;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.groupColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: widget.groupColor.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(isFamily ? Icons.groups : Icons.person,
                    size: 18, color: widget.groupColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: widget.groupColor)),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(displayDate,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600)),
                          if (displayTime.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade100),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time,
                                      size: 10, color: Colors.green.shade700),
                                  const SizedBox(width: 3),
                                  Text(
                                    displayTime,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: methodColor.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    method,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: methodColor.shade700,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _showReprintOptions(group),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.print,
                        size: 26, color: widget.groupColor),
                  ),
                ),
                if (_canEditPayments) ...[
                  InkWell(
                    onTap: () => _showEditGroupDialog(group),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.edit_note,
                          size: 26, color: Colors.orange.shade700),
                    ),
                  ),
                  InkWell(
                    onTap: () => _showDeleteGroupDialog(group),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.delete_forever,
                          size: 26, color: Colors.red.shade600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                ...items.map((it) {
                  final student = it['student'] as Map<String, dynamic>;
                  final amount = (it['amount'] as num?)?.toDouble() ?? 0.0;
                  final name =
                      '${student['surname']} ${student['firstName']}'.trim();
                  final lastEdit = _lastEditByPaymentId[it['id'] as int?];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isFamily ? name : 'Amount Paid',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade700),
                              ),
                            ),
                            Text(
                              '₦${_fmt.format(amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        if (lastEdit != null)
                          InkWell(
                            onTap: () => _showAuditDiffDialog(lastEdit),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_note,
                                    size: 13, color: Colors.orange.shade700),
                                const SizedBox(width: 3),
                                Text(
                                  'Edited by ${lastEdit['username'] ?? 'Unknown'}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange.shade700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                if (note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        note,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic),
                      ),
                    ),
                  ),
                if (isMultiStudent) ...[
                  Divider(height: 18, color: Colors.grey.shade200),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${items.length} siblings',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                      Text(
                        'Total: ₦${_fmt.format(total)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, double amount, Color color) => Expanded(
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade600)),
            const SizedBox(height: 3),
            Text('₦${_fmt.format(amount)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: color)),
          ],
        ),
      );

  // ── Print options ──────────────────────────────────────────────────────────

  void _showPrintOptions() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.print, color: widget.groupColor),
            const SizedBox(width: 8),
            const Text('Print Payment History'),
          ],
        ),
        content: Text(
          'Print payment history for ${_siblingData.length} siblings — ${widget.activeTerm} ${widget.activeSession}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _printHistoryPDF();
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _printHistoryThermal();
            },
            icon: const Icon(Icons.print),
            label: const Text('Thermal'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _printHistoryUsb();
            },
            icon: const Icon(Icons.usb),
            label: const Text('USB'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _sendFamilySms();
            },
            icon: const Icon(Icons.sms),
            label: const Text('SMS'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // ── Reprint a single payment receipt ────────────────────────────────────────
  // Reuses the exact "Family Payment Receipt" layout shown when the payment
  // was first recorded, so a reprint from history looks identical.

  void _showReprintOptions(Map<String, dynamic> group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: widget.groupColor),
            const SizedBox(width: 8),
            const Text('Reprint Receipt'),
          ],
        ),
        content: const Text(
          'Reprint this payment as it was originally issued.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _reprintReceiptPDF(group);
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _reprintReceiptThermal(group);
            },
            icon: const Icon(Icons.print),
            label: const Text('Thermal'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _reprintReceiptUsb(group);
            },
            icon: const Icon(Icons.usb),
            label: const Text('USB'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // For each sibling in the group, works out totalBill/totalPaid/outstanding
  // as of that payment's date (not today), so a reprint of an older
  // transaction shows the balance that was true at the time.
  List<Map<String, dynamic>> _computeReprintItems(Map<String, dynamic> group) {
    final items = group['items'] as List<Map<String, dynamic>>;
    final groupDate =
        DateTime.tryParse(group['paymentDate'] as String? ?? '') ??
            DateTime.now();

    return items.map((it) {
      final student = it['student'] as Map<String, dynamic>;
      final studentId = student['id'] as int;
      final amount = (it['amount'] as num?)?.toDouble() ?? 0.0;
      final className = student['className'] ?? '';
      final arm = student['armName']?.toString() ?? '';
      final classDisplay = arm.isNotEmpty ? '$className - $arm' : className;

      final siblingEntry = _siblingData.firstWhere(
        (d) => (d['student'] as Map<String, dynamic>)['id'] == studentId,
        orElse: () => <String, dynamic>{},
      );
      final grandTotal = (siblingEntry['grandTotal'] as num?)?.toDouble() ?? 0.0;
      final allPayments =
          (siblingEntry['payments'] as List<Map<String, dynamic>>?) ??
              const <Map<String, dynamic>>[];
      final cumulativePaid = allPayments.fold<double>(0.0, (sum, p) {
        final d = DateTime.tryParse(p['paymentDate'] as String? ?? '');
        if (d == null || d.isAfter(groupDate)) return sum;
        return sum + ((p['amount'] as num?)?.toDouble() ?? 0.0);
      });

      return {
        'name': '${student['surname']} ${student['firstName']}'.trim(),
        'className': classDisplay,
        'amount': amount,
        'totalBill': grandTotal,
        'totalPaid': cumulativePaid,
        'outstanding': grandTotal - cumulativePaid,
      };
    }).toList();
  }

  Future<void> _reprintReceiptPDF(Map<String, dynamic> group) async {
    final parentName = widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone = widget.siblingGroup['parentPhone'] as String? ?? '';
    final schoolName =
        _school?['name']?.toString().toUpperCase() ?? 'SCHOOL NAME';
    final schoolAddress = _school?['address']?.toString() ?? '';
    final students =
        widget.siblingGroup['students'] as List<Map<String, dynamic>>;
    final familySurname = students.isNotEmpty
        ? (students.first['surname'] as String? ?? 'Family')
        : 'Family';

    final items = group['items'] as List<Map<String, dynamic>>;
    final method = group['method'] as String? ?? '';
    final note = group['note'] as String? ?? '';
    final date = DateTime.tryParse(group['paymentDate'] as String? ?? '') ??
        DateTime.now();
    final total = items.fold<double>(
        0.0, (sum, it) => sum + ((it['amount'] as num?)?.toDouble() ?? 0.0));

    try {
      _showLoading();
      final pdf = FamilyPaymentReceiptPdfGenerator.generate(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        parentName: parentName,
        parentPhone: parentPhone,
        term: widget.activeTerm,
        session: widget.activeSession,
        date: date,
        method: method,
        note: note,
        totalAmount: total,
        familyTotalBilled: _groupTotalBills,
        familyTotalPaid: _groupTotalPaid,
        familyOutstanding: _groupTotalOutstanding,
        items: items.map((it) {
          final student = it['student'] as Map<String, dynamic>;
          final name = '${student['surname']} ${student['firstName']}'.trim();
          final className = student['className'] ?? '';
          final arm = student['armName']?.toString() ?? '';
          final classDisplay =
              arm.isNotEmpty ? '$className - $arm' : className;
          final amount = (it['amount'] as num?)?.toDouble() ?? 0.0;
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
          '${dir.path}/family_receipt_reprint_${familySurname}_$dateStr.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      Navigator.pop(context); // close loading

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Family Payment Receipt - $parentName',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Error generating PDF: $e');
    }
  }

  Future<void> _reprintReceiptThermal(Map<String, dynamic> group) async {
    if (!ThermalPrinterManager.isConnected) {
      _snack('Please connect to a thermal printer first');
      await NavigationHelper.pushWithSidebar(
        context,
        page: const ThermalPrinterScreen(),
        currentUser: widget.currentUser,
        pageId: 'student_management/students',
      );
      if (!ThermalPrinterManager.isConnected) {
        _snack('Printer not connected. Printing cancelled.',
            color: Colors.orange);
        return;
      }
    }

    try {
      _showLoading();
      final schoolName = _school?['name']?.toString() ?? 'School Name';
      final schoolAddress = _school?['address']?.toString() ?? '';
      final parentName =
          widget.siblingGroup['parentName'] as String? ?? 'Parent';
      final parentPhone =
          widget.siblingGroup['parentPhone'] as String? ?? '';
      final method = group['method'] as String? ?? '';
      final note = group['note'] as String? ?? '';
      final date = DateTime.tryParse(group['paymentDate'] as String? ?? '') ??
          DateTime.now();
      final items = _computeReprintItems(group);
      final total = items.fold<double>(
          0.0, (sum, it) => sum + ((it['amount'] as num?)?.toDouble() ?? 0.0));

      await ThermalPrinterManager.printFamilyPaymentReceipt(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        parentName: parentName,
        parentPhone: parentPhone,
        term: widget.activeTerm,
        session: widget.activeSession,
        method: method,
        date: DateFormat('dd MMM yyyy').format(date),
        note: note,
        paymentItems: items,
        totalAmount: total,
      );
      await PrintCounterHelper.incrementReceiptsPrinted();

      if (!mounted) return;
      Navigator.pop(context);
      _snack('Receipt printed successfully', color: Colors.green);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Error printing: $e');
    }
  }

  Future<void> _reprintReceiptUsb(Map<String, dynamic> group) async {
    if (!UsbPrinterManager.isConnected) {
      _snack('Connect a USB printer first');
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UsbPrinterScreen()),
      );
      if (!UsbPrinterManager.isConnected) {
        _snack('USB printer not connected. Printing cancelled.',
            color: Colors.orange);
        return;
      }
    }

    try {
      _showLoading();
      final schoolName = _school?['name']?.toString() ?? 'School Name';
      final schoolAddress = _school?['address']?.toString() ?? '';
      final parentName =
          widget.siblingGroup['parentName'] as String? ?? 'Parent';
      final parentPhone =
          widget.siblingGroup['parentPhone'] as String? ?? '';
      final method = group['method'] as String? ?? '';
      final note = group['note'] as String? ?? '';
      final date = DateTime.tryParse(group['paymentDate'] as String? ?? '') ??
          DateTime.now();
      final paperSize = await UsbPrinterManager.getPaperSizeEnum();
      final items = _computeReprintItems(group);
      final total = items.fold<double>(
          0.0, (sum, it) => sum + ((it['amount'] as num?)?.toDouble() ?? 0.0));

      await UsbPrinterManager.printFamilyPaymentReceipt(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        parentName: parentName,
        parentPhone: parentPhone,
        term: widget.activeTerm,
        session: widget.activeSession,
        method: method,
        date: DateFormat('dd MMM yyyy').format(date),
        note: note,
        paymentItems: items,
        totalAmount: total,
        paperSize: paperSize,
      );
      await PrintCounterHelper.incrementReceiptsPrinted();

      if (!mounted) return;
      Navigator.pop(context);
      _snack('Receipt printed via USB', color: Colors.green);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('USB print error: $e');
    }
  }

  // ── Combined family SMS ─────────────────────────────────────────────────────

  Future<void> _sendFamilySms() async {
    final parentName = widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone = widget.siblingGroup['parentPhone'] as String?;
    final schoolName = _school?['name']?.toString() ?? 'the school';

    final children = _siblingData.map((data) {
      final student = data['student'] as Map<String, dynamic>;
      final name = '${student['surname']} ${student['firstName']}'.trim();
      final outstanding = (data['outstanding'] as num?)?.toDouble() ?? 0.0;
      return FamilyChildSummary(studentName: name, outstanding: outstanding);
    }).toList();

    final message = buildFamilySms(
      schoolName: schoolName,
      parentName: parentName,
      children: children,
      totalOutstanding: _groupTotalOutstanding,
      term: widget.activeTerm,
      session: widget.activeSession,
    );

    final result = await SmsService.send(
      rawPhone: parentPhone,
      message: message,
      context: 'family_bill',
    );

    if (mounted) {
      final label = result.success
          ? (result.requiresManualConfirmation ? 'Messaging app opened — tap Send to deliver it' : 'Family SMS sent to parent')
          : (result.errorMessage ?? 'Failed to send SMS');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  // ── PDF ────────────────────────────────────────────────────────────────────

  Future<void> _printHistoryPDF() async {
    final students =
        widget.siblingGroup['students'] as List<Map<String, dynamic>>;
    final familySurname = students.isNotEmpty
        ? (students.first['surname'] as String? ?? 'Family')
        : 'Family';
    final parentName =
        widget.siblingGroup['parentName'] as String? ?? 'Parent';
    final parentPhone =
        widget.siblingGroup['parentPhone'] as String? ?? '';
    final schoolName =
        _school?['name']?.toString().toUpperCase() ?? 'SCHOOL NAME';
    final schoolAddress = _school?['address']?.toString() ?? '';

    try {
      _showLoading();
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context ctx) => [
            // School header
            pw.Center(
              child: pw.Text(schoolName,
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo700)),
            ),
            if (schoolAddress.isNotEmpty)
              pw.Center(
                child: pw.Text(schoolAddress,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700)),
              ),
            pw.SizedBox(height: 14),
            pw.Center(
              child: pw.Text('FAMILY PAYMENT HISTORY',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                  '${widget.activeTerm}  |  ${widget.activeSession}',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
            ),
            pw.SizedBox(height: 16),
            // Parent info
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.cyan300),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Parent: $parentName',
                      style:
                          pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 3),
                  pw.Text('Phone: $parentPhone',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Per-sibling sections
            ..._siblingData.expand((data) {
              final student =
                  data['student'] as Map<String, dynamic>;
              final payments =
                  data['payments'] as List<Map<String, dynamic>>;
              final totalPaid =
                  (data['totalPaid'] as num?)?.toDouble() ?? 0.0;
              final grandTotal =
                  (data['grandTotal'] as num?)?.toDouble() ?? 0.0;
              final outstanding =
                  (data['outstanding'] as num?)?.toDouble() ?? 0.0;
              final fullName =
                  '${student['surname']} ${student['firstName']}'.trim();
              final className = student['className'] ?? '';
              final arm = student['armName'] ?? '';
              final classDisplay =
                  arm.isNotEmpty ? '$className - $arm' : className;

              return [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.cyan100,
                    borderRadius: const pw.BorderRadius.only(
                      topLeft: pw.Radius.circular(5),
                      topRight: pw.Radius.circular(5),
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment:
                        pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment:
                            pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(fullName,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 12)),
                          pw.Text(classDisplay,
                              style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.grey700)),
                        ],
                      ),
                      pw.Text(
                        outstanding <= 0 ? 'BALANCED' : 'OWING',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: outstanding <= 0
                              ? PdfColors.green700
                              : PdfColors.red700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.cyan200),
                    borderRadius: const pw.BorderRadius.only(
                      bottomLeft: pw.Radius.circular(5),
                      bottomRight: pw.Radius.circular(5),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      if (payments.isEmpty)
                        pw.Text('No payments this term',
                            style: const pw.TextStyle(
                                fontSize: 9,
                                color: PdfColors.grey600))
                      else
                        pw.TableHelper.fromTextArray(
                          headerStyle: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 8),
                          cellStyle:
                              const pw.TextStyle(fontSize: 8),
                          data: [
                            ['Date', 'Method', 'Amount'],
                            ...payments.map((p) {
                              final rawDate =
                                  p['paymentDate'] as String? ?? '';
                              String d = rawDate;
                              try {
                                final parsed =
                                    DateTime.tryParse(rawDate);
                                if (parsed != null) {
                                  d = DateFormat('dd/MM/yyyy')
                                      .format(parsed);
                                }
                              } catch (_) {}
                              final amt =
                                  (p['amount'] as num?)?.toDouble() ??
                                      0.0;
                              return [
                                d,
                                p['method'] ?? '',
                                '₦${_fmt.format(amt)}'
                              ];
                            }),
                          ],
                        ),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        mainAxisAlignment:
                            pw.MainAxisAlignment.spaceAround,
                        children: [
                          _pdfStat('Total Billed',
                              '₦${_fmt.format(grandTotal)}',
                              PdfColors.purple700),
                          _pdfStat('Total Paid',
                              '₦${_fmt.format(totalPaid)}',
                              PdfColors.green700),
                          _pdfStat(
                              'Outstanding',
                              '₦${_fmt.format(outstanding)}',
                              outstanding > 0
                                  ? PdfColors.red700
                                  : PdfColors.green700),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 14),
              ];
            }),

            // Family total
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColors.cyan400, width: 2),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Column(
                children: [
                  _pdfTotalRow('Total Family Bills',
                      '₦${_fmt.format(_groupTotalBills)}'),
                  pw.SizedBox(height: 5),
                  _pdfTotalRow('Total Paid This Term',
                      '₦${_fmt.format(_groupTotalPaid)}'),
                  pw.Divider(),
                  _pdfTotalRow(
                    'TOTAL OUTSTANDING',
                    '₦${_fmt.format(_groupTotalOutstanding)}',
                    bold: true,
                    valueColor: _groupTotalOutstanding > 0
                        ? PdfColors.red
                        : PdfColors.green,
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 30),
            pw.Divider(),
            pw.Text(
              'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File(
          '${dir.path}/family_history_${familySurname}_$dateStr.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Family Payment History - $parentName',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Error generating PDF: $e');
    }
  }

  pw.Widget _pdfStat(String label, String value, PdfColor color) =>
      pw.Column(
        children: [
          pw.Text(label,
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 3),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
        ],
      );

  pw.Widget _pdfTotalRow(String label, String value,
          {bool bold = false, PdfColor? valueColor}) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: bold ? 13 : 11,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: bold ? 13 : 11,
                  fontWeight: pw.FontWeight.bold,
                  color: valueColor)),
        ],
      );

  // ── Thermal ────────────────────────────────────────────────────────────────

  Future<void> _printHistoryThermal() async {
    if (!ThermalPrinterManager.isConnected) {
      _snack('Please connect to a thermal printer first');
      await NavigationHelper.pushWithSidebar(
        context,
        page: const ThermalPrinterScreen(),
        currentUser: widget.currentUser,
        pageId: 'student_management/students',
      );
      if (!ThermalPrinterManager.isConnected) {
        _snack('Printer not connected. Printing cancelled.',
            color: Colors.orange);
        return;
      }
    }

    try {
      _showLoading();
      final schoolName = _school?['name']?.toString() ?? 'School Name';
      final schoolAddress = _school?['address']?.toString() ?? '';
      final parentName =
          widget.siblingGroup['parentName'] as String? ?? 'Parent';
      final parentPhone =
          widget.siblingGroup['parentPhone'] as String? ?? '';

      final List<Map<String, dynamic>> siblingItems = _siblingData.map((data) {
        final student = data['student'] as Map<String, dynamic>;
        final payments = data['payments'] as List<Map<String, dynamic>>;
        final totalPaid =
            (data['totalPaid'] as num?)?.toDouble() ?? 0.0;
        final grandTotal =
            (data['grandTotal'] as num?)?.toDouble() ?? 0.0;
        final outstanding =
            (data['outstanding'] as num?)?.toDouble() ?? 0.0;
        final fullName =
            '${student['surname']} ${student['firstName']}'.trim();
        final className = student['className'] ?? '';
        final arm = student['armName'] ?? '';
        return {
          'name': fullName,
          'className': arm.isNotEmpty ? '$className - $arm' : className,
          'totalBill': grandTotal,
          'totalPaid': totalPaid,
          'outstanding': outstanding,
          'payments': payments.map((p) {
            final rawDate = p['paymentDate'] as String? ?? '';
            String d = rawDate;
            try {
              final parsed = DateTime.tryParse(rawDate);
              if (parsed != null) {
                d = DateFormat('dd/MM/yyyy').format(parsed);
              }
            } catch (_) {}
            return {
              'date': d,
              'method': p['method'] ?? '',
              'amount': (p['amount'] as num?)?.toDouble() ?? 0.0,
            };
          }).toList(),
        };
      }).toList();

      await ThermalPrinterManager.printFamilyPaymentHistory(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        parentName: parentName,
        parentPhone: parentPhone,
        term: widget.activeTerm,
        session: widget.activeSession,
        siblingItems: siblingItems,
        groupTotalBills: _groupTotalBills,
        groupTotalPaid: _groupTotalPaid,
        groupTotalOutstanding: _groupTotalOutstanding,
        schoolPhone: _school?['phone']?.toString(),
      );
      await PrintCounterHelper.incrementPaymentHistoryPrinted();

      if (!mounted) return;
      Navigator.pop(context);
      _snack('History printed successfully', color: Colors.green);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Error printing: $e');
    }
  }

  // ── USB ────────────────────────────────────────────────────────────────────

  Future<void> _printHistoryUsb() async {
    if (!UsbPrinterManager.isConnected) {
      _snack('Connect a USB printer first');
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UsbPrinterScreen()),
      );
      if (!UsbPrinterManager.isConnected) {
        _snack('USB printer not connected.', color: Colors.orange);
        return;
      }
    }

    try {
      _showLoading();
      final schoolName = _school?['name']?.toString() ?? 'School Name';
      final schoolAddress = _school?['address']?.toString() ?? '';
      final parentName =
          widget.siblingGroup['parentName'] as String? ?? 'Parent';
      final parentPhone =
          widget.siblingGroup['parentPhone'] as String? ?? '';
      final paperSize = await UsbPrinterManager.getPaperSizeEnum();

      final List<Map<String, dynamic>> siblingItems = _siblingData.map((data) {
        final student = data['student'] as Map<String, dynamic>;
        final payments = data['payments'] as List<Map<String, dynamic>>;
        final totalPaid =
            (data['totalPaid'] as num?)?.toDouble() ?? 0.0;
        final grandTotal =
            (data['grandTotal'] as num?)?.toDouble() ?? 0.0;
        final outstanding =
            (data['outstanding'] as num?)?.toDouble() ?? 0.0;
        final fullName =
            '${student['surname']} ${student['firstName']}'.trim();
        final className = student['className'] ?? '';
        final arm = student['armName'] ?? '';
        return {
          'name': fullName,
          'className': arm.isNotEmpty ? '$className - $arm' : className,
          'totalBill': grandTotal,
          'totalPaid': totalPaid,
          'outstanding': outstanding,
          'payments': payments.map((p) {
            final rawDate = p['paymentDate'] as String? ?? '';
            String d = rawDate;
            try {
              final parsed = DateTime.tryParse(rawDate);
              if (parsed != null) {
                d = DateFormat('dd/MM/yyyy').format(parsed);
              }
            } catch (_) {}
            return {
              'date': d,
              'method': p['method'] ?? '',
              'amount': (p['amount'] as num?)?.toDouble() ?? 0.0,
            };
          }).toList(),
        };
      }).toList();

      await UsbPrinterManager.printFamilyPaymentHistory(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        parentName: parentName,
        parentPhone: parentPhone,
        term: widget.activeTerm,
        session: widget.activeSession,
        siblingItems: siblingItems,
        groupTotalBills: _groupTotalBills,
        groupTotalPaid: _groupTotalPaid,
        groupTotalOutstanding: _groupTotalOutstanding,
        schoolPhone: _school?['phone']?.toString(),
        paperSize: paperSize,
      );
      await PrintCounterHelper.incrementPaymentHistoryPrinted();

      if (!mounted) return;
      Navigator.pop(context);
      _snack('History printed via USB', color: Colors.green);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('USB print error: $e');
    }
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}
