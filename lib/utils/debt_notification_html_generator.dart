import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';

/// HTML mirror of DebtNotificationPdfGenerator, rendered via Android's
/// native WebView print pipeline (see custom_report_pdf_generator.dart).
///
/// Bulk generation (a debt letter per student, potentially for a whole
/// school) is exactly the kind of large multi-page document that risked
/// OOM under the pure-Dart `pdf` package — this sidesteps that entirely by
/// letting the WebView/browser engine paginate.
class DebtNotificationHtmlGenerator {
  static final _currency = NumberFormat('#,##0.00');

  static Future<String> buildSingle({
    required Map<String, dynamic> schoolProfile,
    required String studentName,
    required String admissionNo,
    required String className,
    required String term,
    required String session,
    required double totalBills,
    required double totalPaid,
    required double outstanding,
    required DateTime letterDate,
    String? signatoryName,
    String? customOpening,
    String? customClosing,
    DateTime? paymentDeadline,
    int copiesPerPage = 1,
    bool isLastTerm = false,
    bool isZeroPayment = false,
    bool isPta = false,
    bool isMidTerm = false,
    DateTime? ptaMeetingDate,
    String ptaMeetingTime = '',
    String ptaVenue = '',
    DateTime? midTermStartDate,
    DateTime? midTermReturnDate,
  }) async {
    final letter = await _buildLetterArgs(
      schoolProfile: schoolProfile,
      studentName: studentName,
      admissionNo: admissionNo,
      className: className,
      term: term,
      session: session,
      totalBills: totalBills,
      totalPaid: totalPaid,
      outstanding: outstanding,
      letterDate: letterDate,
      signatoryName: signatoryName,
      customOpening: customOpening,
      customClosing: customClosing,
      paymentDeadline: paymentDeadline,
      isLastTerm: isLastTerm,
      isZeroPayment: isZeroPayment,
      isPta: isPta,
      isMidTerm: isMidTerm,
      ptaMeetingDate: ptaMeetingDate,
      ptaMeetingTime: ptaMeetingTime,
      ptaVenue: ptaVenue,
      midTermStartDate: midTermStartDate,
      midTermReturnDate: midTermReturnDate,
    );
    return _wrap([letter], copiesPerPage);
  }

  static Future<String> buildBulk({
    required Map<String, dynamic> schoolProfile,
    required List<Map<String, dynamic>> students,
    required String term,
    required String session,
    required DateTime letterDate,
    String? signatoryName,
    String? customOpening,
    String? customClosing,
    DateTime? paymentDeadline,
    int copiesPerPage = 1,
    bool isLastTerm = false,
    bool isZeroPayment = false,
    bool isPta = false,
    bool isMidTerm = false,
    DateTime? ptaMeetingDate,
    String ptaMeetingTime = '',
    String ptaVenue = '',
    DateTime? midTermStartDate,
    DateTime? midTermReturnDate,
  }) async {
    String? logoDataUri = await _loadLogo(schoolProfile);
    final letters = <_Letter>[];
    for (final s in students) {
      letters.add(_buildLetterHtmlFromArgs(
        schoolProfile: schoolProfile,
        logoDataUri: logoDataUri,
        studentName: (s['studentName'] ?? '').toString(),
        admissionNo: (s['admissionNo'] ?? '').toString(),
        className: (s['className'] ?? '').toString(),
        term: term,
        session: session,
        totalBills: (s['totalBills'] as num).toDouble(),
        totalPaid: (s['totalPaid'] as num).toDouble(),
        outstanding: (s['outstanding'] as num).toDouble(),
        letterDate: letterDate,
        signatoryName: signatoryName,
        customOpening: customOpening,
        customClosing: customClosing,
        paymentDeadline: paymentDeadline,
        isLastTerm: isLastTerm,
        isZeroPayment: isZeroPayment,
        isPta: isPta,
        isMidTerm: isMidTerm,
        ptaMeetingDate: ptaMeetingDate,
        ptaMeetingTime: ptaMeetingTime,
        ptaVenue: ptaVenue,
        midTermStartDate: midTermStartDate,
        midTermReturnDate: midTermReturnDate,
      ));
    }
    return _wrap(letters, copiesPerPage);
  }

  static Future<String?> _loadLogo(Map<String, dynamic> schoolProfile) async {
    final logoPath = (schoolProfile['logoPath'] ?? '').toString();
    if (logoPath.isEmpty) return null;
    final logoFile = File(logoPath);
    if (!await logoFile.exists()) return null;
    final bytes = await logoFile.readAsBytes();
    final ext = logoPath.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    return 'data:image/$ext;base64,${base64Encode(bytes)}';
  }

  static Future<_Letter> _buildLetterArgs({
    required Map<String, dynamic> schoolProfile,
    required String studentName,
    required String admissionNo,
    required String className,
    required String term,
    required String session,
    required double totalBills,
    required double totalPaid,
    required double outstanding,
    required DateTime letterDate,
    String? signatoryName,
    String? customOpening,
    String? customClosing,
    DateTime? paymentDeadline,
    bool isLastTerm = false,
    bool isZeroPayment = false,
    bool isPta = false,
    bool isMidTerm = false,
    DateTime? ptaMeetingDate,
    String ptaMeetingTime = '',
    String ptaVenue = '',
    DateTime? midTermStartDate,
    DateTime? midTermReturnDate,
  }) async {
    final logoDataUri = await _loadLogo(schoolProfile);
    return _buildLetterHtmlFromArgs(
      schoolProfile: schoolProfile,
      logoDataUri: logoDataUri,
      studentName: studentName,
      admissionNo: admissionNo,
      className: className,
      term: term,
      session: session,
      totalBills: totalBills,
      totalPaid: totalPaid,
      outstanding: outstanding,
      letterDate: letterDate,
      signatoryName: signatoryName,
      customOpening: customOpening,
      customClosing: customClosing,
      paymentDeadline: paymentDeadline,
      isLastTerm: isLastTerm,
      isZeroPayment: isZeroPayment,
      isPta: isPta,
      isMidTerm: isMidTerm,
      ptaMeetingDate: ptaMeetingDate,
      ptaMeetingTime: ptaMeetingTime,
      ptaVenue: ptaVenue,
      midTermStartDate: midTermStartDate,
      midTermReturnDate: midTermReturnDate,
    );
  }

  static _Letter _buildLetterHtmlFromArgs({
    required Map<String, dynamic> schoolProfile,
    required String? logoDataUri,
    required String studentName,
    required String admissionNo,
    required String className,
    required String term,
    required String session,
    required double totalBills,
    required double totalPaid,
    required double outstanding,
    required DateTime letterDate,
    String? signatoryName,
    String? customOpening,
    String? customClosing,
    DateTime? paymentDeadline,
    bool isLastTerm = false,
    bool isZeroPayment = false,
    bool isPta = false,
    bool isMidTerm = false,
    DateTime? ptaMeetingDate,
    String ptaMeetingTime = '',
    String ptaVenue = '',
    DateTime? midTermStartDate,
    DateTime? midTermReturnDate,
  }) {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final schoolAddress = (schoolProfile['address'] ?? '').toString();
    final schoolPhone = (schoolProfile['phone'] ?? '').toString();
    final schoolEmail = (schoolProfile['email'] ?? '').toString();
    final signatory = signatoryName?.trim().isNotEmpty == true ? signatoryName!.trim() : schoolName;
    final formattedDate = DateFormat('d MMMM, yyyy').format(letterDate);
    final contactLine = [
      if (schoolPhone.isNotEmpty) 'Tel: $schoolPhone',
      if (schoolEmail.isNotEmpty) schoolEmail,
    ].join('  |  ');

    final ptaMeetingDateStr = ptaMeetingDate != null ? DateFormat('EEEE, d MMMM yyyy').format(ptaMeetingDate) : '';
    final midTermStartStr = midTermStartDate != null ? DateFormat('d MMMM, yyyy').format(midTermStartDate) : '';
    final midTermReturnStr = midTermReturnDate != null ? DateFormat('d MMMM, yyyy').format(midTermReturnDate) : '';

    final opening = customOpening?.trim().isNotEmpty == true
        ? customOpening!.trim()
        : isPta
            ? 'We are pleased to formally invite you to our Parent-Teacher Association (PTA) meeting scheduled as follows:<br><br>'
                'Date:&nbsp;&nbsp;&nbsp;${ptaMeetingDateStr.isNotEmpty ? _esc(ptaMeetingDateStr) : "To be announced"}<br>'
                'Time:&nbsp;&nbsp;&nbsp;${ptaMeetingTime.isNotEmpty ? _esc(ptaMeetingTime) : "To be announced"}<br>'
                'Venue: ${ptaVenue.isNotEmpty ? _esc(ptaVenue) : _esc(schoolName)}<br><br>'
                'Your presence at this meeting is of utmost importance as we shall be discussing matters relating to '
                'the academic progress and welfare of all students for the ${_esc(term)} term of the ${_esc(session)} academic session.'
            : isMidTerm
                ? 'We write to inform you that the school will be proceeding on a mid-term break'
                    '${midTermStartStr.isNotEmpty ? " from ${_esc(midTermStartStr)}" : ""}. '
                    'Students are expected to resume school'
                    '${midTermReturnStr.isNotEmpty ? " on ${_esc(midTermReturnStr)}" : " after the break"}.<br><br>'
                    'We also wish to bring to your urgent attention that your child/ward, ${_esc(studentName)} '
                    '(Admission No: ${_esc(admissionNo)}), currently in ${_esc(className)}, has an outstanding school fee '
                    'balance of N${_currency.format(outstanding)} for the ${_esc(term)} term of the ${_esc(session)} academic session.'
                : isZeroPayment
                    ? 'We write to bring to your urgent attention that your child/ward, ${_esc(studentName)} '
                        '(Admission No: ${_esc(admissionNo)}), currently in ${_esc(className)}, has NOT made any payment '
                        'whatsoever towards the school fees for the ${_esc(term)} term of the ${_esc(session)} academic session. '
                        'The total school fees billed for this term amount to N${_currency.format(totalBills)}, and as of the '
                        'date of this letter, no payment has been received from your ward\'s account.'
                    : isLastTerm
                        ? 'We write to bring to your notice that your child/ward, ${_esc(studentName)} '
                            '(Admission No: ${_esc(admissionNo)}), currently in ${_esc(className)}, has an uncleared fee balance '
                            'carried over from the ${_esc(term)} term of the ${_esc(session)} academic session. The total school '
                            'fees billed for that term amounted to N${_currency.format(totalBills)}, out of which '
                            'N${_currency.format(totalPaid)} was paid, leaving an outstanding balance of '
                            'N${_currency.format(outstanding)} which remains unpaid to date.'
                        : 'We write to bring to your notice that your child/ward, ${_esc(studentName)} '
                            '(Admission No: ${_esc(admissionNo)}), currently in ${_esc(className)}, has an outstanding fee '
                            'balance for the ${_esc(term)} term of the ${_esc(session)} academic session. The total school fees '
                            'billed for this term amount to N${_currency.format(totalBills)}, out of which '
                            'N${_currency.format(totalPaid)} has been paid, leaving an outstanding balance of '
                            'N${_currency.format(outstanding)}.';

    final deadlinePhrase = paymentDeadline != null
        ? 'on or before ${_esc(DateFormat('d MMMM, yyyy').format(paymentDeadline))}'
        : 'as soon as possible';

    final closing = customClosing?.trim().isNotEmpty == true
        ? customClosing!.trim()
        : isPta
            ? 'We strongly urge all parents and guardians to make every effort to attend this meeting. Your active '
                'participation helps us build a strong partnership between the school and parents, which is essential for '
                'the academic success and holistic development of our students.<br><br>'
                'Please ensure you make the necessary arrangements to be present. We look forward to seeing you.<br><br>'
                'Thank you for your continued support and cooperation.'
            : isMidTerm
                ? 'Kindly ensure that your child/ward returns to school after the mid-term break with a payment of '
                    'N${_currency.format(outstanding)} or as much as possible towards the outstanding balance'
                    '${midTermReturnStr.isNotEmpty ? " on ${_esc(midTermReturnStr)}" : ""}.<br><br>'
                    'Please be informed that students with outstanding fee balances will NOT be permitted to remain on the '
                    'school premises after the mid-term break without evidence of payment. We strongly encourage you to use '
                    'this break period to make the necessary arrangements.<br><br>'
                    'For payment enquiries or to discuss a payment plan, please contact the school bursar\'s office'
                    '${contactLine.isNotEmpty ? " at ${_esc(contactLine)}" : ""}.<br><br>'
                    'Thank you for your understanding and cooperation.'
                : isZeroPayment
                    ? 'We strongly urge you to make full payment of N${_currency.format(outstanding)} $deadlinePhrase. '
                        'Please be advised that your child/ward will NOT be permitted to continue attending classes until full '
                        'payment of the school fees is made. This is a matter that requires your immediate attention and action.<br><br>'
                        'Should you wish to discuss a payment arrangement, please contact the school bursar\'s office without delay'
                        '${contactLine.isNotEmpty ? " at ${_esc(contactLine)}" : ""}.<br><br>'
                        'We trust you will treat this matter with the urgency it deserves.'
                    : 'Kindly ensure that payment of the outstanding amount of N${_currency.format(outstanding)} is made '
                        '$deadlinePhrase. Please be informed that failure to settle this balance by the due date will result in '
                        'your child/ward not being permitted to remain in school until full payment is made.<br><br>'
                        'Should you require further clarification or wish to discuss a payment arrangement, please do not '
                        'hesitate to contact the school bursar\'s office'
                        '${contactLine.isNotEmpty ? " at ${_esc(contactLine)}" : ""}.<br><br>'
                        'Thank you for your continued cooperation and support.';

    final subject = isPta
        ? 'RE: PTA MEETING NOTIFICATION - ${term.toUpperCase()}, $session'
        : isMidTerm
            ? 'RE: MID-TERM HOLIDAY NOTICE &amp; FEE REMINDER - ${term.toUpperCase()}, $session'
            : isZeroPayment
                ? 'RE: NO PAYMENT RECEIVED - ${term.toUpperCase()}, $session'
                : isLastTerm
                    ? 'RE: UNPAID FEES FROM ${term.toUpperCase()} - $session'
                    : 'RE: OUTSTANDING SCHOOL FEES - $term, $session';

    final html = '''
<div class="letter">
  <div class="letterhead">
    ${logoDataUri != null ? '<img src="$logoDataUri" class="logo">' : ''}
    <div class="school-block">
      <div class="school-name">${_esc(schoolName.toUpperCase())}</div>
      ${schoolAddress.isNotEmpty ? '<div class="school-line">${_esc(schoolAddress)}</div>' : ''}
      ${contactLine.isNotEmpty ? '<div class="school-line muted">${_esc(contactLine)}</div>' : ''}
    </div>
  </div>
  <hr>
  <div class="date-line">${_esc(formattedDate)}</div>
  <div class="addressee">The Parent/Guardian,</div>
  <div class="addressee bold">Of ${_esc(studentName)},</div>
  <div class="addressee">${_esc(schoolName)}</div>
  <div class="salutation">Dear Parent/Guardian,</div>
  <div class="subject">${_esc(subject).replaceAll('&amp;amp;', '&amp;')}</div>
  <div class="body">$opening</div>
  <div class="body">$closing</div>
  <div class="sign-off">Yours faithfully,</div>
  <div class="signature-line"></div>
  <div class="signatory">${_esc(signatory)}</div>
  <div class="signatory-role">Bursary Department</div>
  <div class="signatory-role">${_esc(schoolName)}</div>
  <div class="signatory-date">Date: ${_esc(formattedDate)}</div>
  <div class="letter-footer">This is a computer-generated letter — ${_esc(schoolName)}</div>
</div>
''';

    return _Letter(html);
  }

  static String _wrap(List<_Letter> letters, int copiesPerPage) {
    final perPage = copiesPerPage.clamp(1, 3);
    final pages = StringBuffer();

    for (var i = 0; i < letters.length; i += perPage) {
      final group = letters.skip(i).take(perPage).toList();
      pages.writeln('<div class="page cols-$perPage">');
      for (var j = 0; j < group.length; j++) {
        if (j > 0) pages.writeln('<div class="cut-line"></div>');
        pages.writeln(group[j].html);
      }
      pages.writeln('</div>');
    }

    return '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  @page { margin: ${copiesPerPage > 1 ? '16px' : '40px'}; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1a; margin:0; }
  .page { page-break-after: always; display:flex; flex-direction:column; ${copiesPerPage > 1 ? 'gap:0;' : ''} }
  .page:last-child { page-break-after: auto; }
  .page.cols-1 { font-size: 12px; }
  .page.cols-2 .letter { font-size: 10px; }
  .page.cols-3 .letter { font-size: 9px; }
  .cut-line { border-top: 1px dashed #9E9E9E; margin: 6px 0; }
  .letterhead { display:flex; align-items:center; gap:12px; justify-content:center; }
  .logo { width: 50px; height: 50px; }
  .school-block { text-align:center; }
  .school-name { font-size: 1.3em; font-weight:bold; letter-spacing: 0.5px; }
  .school-line { font-size: 0.85em; }
  .muted { color: #616161; }
  hr { border:none; border-top: 1.5px solid #424242; margin: 10px 0; }
  .date-line { text-align:right; margin-bottom: 12px; }
  .addressee { margin: 1px 0; }
  .addressee.bold { font-weight:bold; }
  .salutation { font-weight:bold; margin-top: 12px; }
  .subject { text-align:center; font-weight:bold; text-decoration: underline; margin: 10px 0; }
  .body { text-align: justify; margin-bottom: 12px; line-height: 1.5; }
  .sign-off { margin-top: 16px; }
  .signature-line { width: 160px; border-bottom: 0.5px solid #424242; margin-top: 24px; }
  .signatory { font-weight:bold; margin-top: 4px; }
  .signatory-role { font-size: 0.9em; color: #424242; }
  .signatory-date { font-size: 0.85em; color: #616161; margin-top: 4px; }
  .letter-footer { text-align:center; font-size: 0.75em; color: #757575; border-top: 0.5px solid #BDBDBD; margin-top: 16px; padding-top: 8px; }
</style>
</head><body>
$pages
</body></html>
''';
  }

  static String _esc(dynamic value) {
    final s = value?.toString() ?? '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}

class _Letter {
  final String html;
  _Letter(this.html);
}
