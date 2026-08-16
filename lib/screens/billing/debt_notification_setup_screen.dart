// lib/screens/billing/debt_notification_setup_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Settings returned from the setup page to the hub screen.
class DebtNotificationSettings {
  final String letterType; // 'current'|'last'|'zero'|'pta'|'midterm'
  final int copiesPerPage;
  final DateTime letterDate;
  final String signatoryName;
  final String customOpening;
  final String customClosing;
  final DateTime? paymentDeadline;
  // PTA fields
  final DateTime? ptaMeetingDate;
  final String ptaMeetingTime;
  final String ptaVenue;
  // Mid-term fields
  final DateTime? midTermStartDate;
  final DateTime? midTermReturnDate;

  const DebtNotificationSettings({
    required this.letterType,
    required this.copiesPerPage,
    required this.letterDate,
    required this.signatoryName,
    this.customOpening = '',
    this.customClosing = '',
    this.paymentDeadline,
    this.ptaMeetingDate,
    this.ptaMeetingTime = '',
    this.ptaVenue = '',
    this.midTermStartDate,
    this.midTermReturnDate,
  });

  String get letterTypeLabel {
    if (letterType == 'current') return 'Current Term Debtors';
    if (letterType == 'last') return 'Last Term Debtors';
    if (letterType == 'zero') return 'Zero Payment (Nothing Paid)';
    if (letterType == 'pta') return 'PTA Meeting Notification';
    return 'Mid-Term Holiday Notice';
  }

  String get summary =>
      '$letterTypeLabel  ·  $copiesPerPage per page  ·  '
      '${DateFormat('d MMM yyyy').format(letterDate)}';
}

class DebtNotificationSetupScreen extends StatefulWidget {
  final DebtNotificationSettings initial;

  const DebtNotificationSetupScreen({super.key, required this.initial});

  @override
  State<DebtNotificationSetupScreen> createState() =>
      _DebtNotificationSetupScreenState();
}

class _DebtNotificationSetupScreenState
    extends State<DebtNotificationSetupScreen> {
  late String _letterType;
  late int _copiesPerPage;
  late DateTime _letterDate;
  late final TextEditingController _signatoryController;

  @override
  void initState() {
    super.initState();
    _letterType = widget.initial.letterType;
    _copiesPerPage = widget.initial.copiesPerPage;
    _letterDate = widget.initial.letterDate;
    _signatoryController =
        TextEditingController(text: widget.initial.signatoryName);
  }

  @override
  void dispose() {
    _signatoryController.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.pop(
      context,
      DebtNotificationSettings(
        letterType: _letterType,
        copiesPerPage: _copiesPerPage,
        letterDate: _letterDate,
        signatoryName: _signatoryController.text.trim(),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _letterDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _letterDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Letter Setup'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _apply,
            child: const Text('Apply',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── (a) Letter component ───────────────────────────────
            _sectionCard(
              label: '(a)  Letter Component',
              child: Column(
                children: [
                  _typeOption(
                    value: 'current',
                    title: 'Current Term Debtors',
                    subtitle:
                        'Students with outstanding balance in the active term',
                    icon: Icons.receipt_long_outlined,
                  ),
                  const SizedBox(height: 10),
                  _typeOption(
                    value: 'last',
                    title: 'Last Term Debtors',
                    subtitle:
                        'Students who carried unpaid debt from a previous term',
                    icon: Icons.history_edu_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── (b) Letters per page ───────────────────────────────
            _sectionCard(
              label: '(b)  Letters Per Page',
              child: Row(
                children: [
                  _pageOption(
                    value: 1,
                    label: '1 per page',
                    sublabel: 'Full-size',
                    icon: Icons.article_outlined,
                  ),
                  const SizedBox(width: 8),
                  _pageOption(
                    value: 2,
                    label: '2 per page',
                    sublabel: 'Saves paper',
                    icon: Icons.content_copy,
                    badge: 'RECOMMENDED',
                  ),
                  const SizedBox(width: 8),
                  _pageOption(
                    value: 3,
                    label: '3 per page',
                    sublabel: 'Max saving',
                    icon: Icons.filter_none,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── (c) Letter date ───────────────────────────────────
            _sectionCard(
              label: '(c)  Letter Date',
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  child: Text(
                    DateFormat('d MMMM, yyyy').format(_letterDate),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Signatory (optional) ───────────────────────────────
            _sectionCard(
              label: 'Signatory Name (optional)',
              child: TextField(
                controller: _signatoryController,
                decoration: const InputDecoration(
                  hintText:
                      'e.g. Mr. John Eze  (defaults to school name)',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Apply button ───────────────────────────────────────
            ElevatedButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Apply Settings'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black87),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  Widget _typeOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _letterType == value;
    return GestureDetector(
      onTap: () => setState(() => _letterType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Colors.red.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.red.shade700 : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected
                    ? Colors.red.shade700
                    : Colors.grey.shade500,
                size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: selected
                            ? Colors.red.shade800
                            : Colors.black87,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle,
                  color: Colors.red.shade700, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _pageOption({
    required int value,
    required String label,
    required String sublabel,
    required IconData icon,
    String? badge,
  }) {
    final selected = _copiesPerPage == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _copiesPerPage = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.indigo : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Colors.indigo : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 30,
                  color: selected
                      ? Colors.white
                      : Colors.grey.shade600),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color:
                        selected ? Colors.white : Colors.black87,
                  )),
              Text(sublabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? Colors.white70
                        : Colors.grey.shade500,
                  )),
              if (badge != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white24
                        : Colors.green.shade600,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge,
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
