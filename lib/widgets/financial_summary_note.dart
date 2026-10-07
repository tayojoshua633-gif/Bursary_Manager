import 'package:flutter/material.dart';

/// Small grey "How these figures are calculated" box shown under the
/// financial summaries on the Dashboard, Virtual Ledger and Debtors List,
/// so users understand why the three screens can show different totals.
class FinancialSummaryNote extends StatelessWidget {
  /// (label, explanation) pairs, e.g. ('Outstanding', 'Total still owed…')
  final List<(String, String)> lines;
  final String? footer;
  final double fontSize;

  const FinancialSummaryNote({
    super.key,
    required this.lines,
    this.footer,
    this.fontSize = 11.5,
  });

  // ---- Shared wording (keep the three screens consistent) ----

  static const dashboard = FinancialSummaryNote(
    lines: [
      ('Fees Expected', "This term's fees plus previous balances of all active students, including students not yet billed this term."),
      ('Payments Received', 'All payments recorded this term, including payments from inactive students.'),
      ('Outstanding', 'Total still owed by students who owe. Overpayments are not subtracted; they appear under Total Overpaid.'),
    ],
    footer: 'Matches the Virtual Ledger (All Classes). The Debtors List shows lower Bills and Paid because fully paid students are not listed.',
  );

  static const virtualLedger = FinancialSummaryNote(
    lines: [
      ('Total Bills', "This term's fees plus previous balances of every active student shown."),
      ('Total Paid', 'Payments recorded this term by the students shown.'),
      ('Outstanding', 'Total still owed by students who owe. Overpayments are shown separately, not subtracted.'),
    ],
    footer: 'With All Classes selected, these match the Dashboard. The Dashboard may show slightly more Payments Received if inactive students paid this term.',
  );

  static const debtorsList = FinancialSummaryNote(
    lines: [
      ('Who is listed', 'Only students who still owe. Fully paid and overpaid students are left out.'),
      ('Total Bills / Total Paid', "This term's fees plus previous balances, and this term's payments, of the listed debtors only."),
      ('Outstanding', 'Total still owed by the listed debtors.'),
    ],
    footer: "That's why Total Bills and Total Paid are lower than on the Dashboard and Virtual Ledger. With All Classes and no percentage filter, Outstanding equals the Dashboard's Outstanding.",
  );

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.grey.shade700;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: fontSize * 1.5, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How these figures are calculated',
                  style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 4),
                for (final (label, text) in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(text: text),
                        ],
                      ),
                      style: TextStyle(fontSize: fontSize, color: textColor, height: 1.35),
                    ),
                  ),
                if (footer != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    footer!,
                    style: TextStyle(
                      fontSize: fontSize,
                      color: textColor,
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
