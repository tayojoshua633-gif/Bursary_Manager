// lib/utils/debt_notification_pdf_generator.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DebtNotificationPdfGenerator {
  static final _currency = NumberFormat('#,##0.00');

  /// Generates a debt-notification letter as a PDF.
  ///
  /// [twoUp]   = true → two compact copies on one A4 page.
  /// [threeUp] = true → three compact copies on one A4 page (max paper saving).
  static Future<({Uint8List bytes, String? filePath})> generate({
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
    bool saveToFile = true,
    bool twoUp = false,
    bool threeUp = false,
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
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final schoolAddress = (schoolProfile['address'] ?? '').toString();
    final schoolPhone = (schoolProfile['phone'] ?? '').toString();
    final schoolEmail = (schoolProfile['email'] ?? '').toString();
    final schoolLogo = (schoolProfile['logoPath'] ?? '').toString();

    final signatory = signatoryName?.trim().isNotEmpty == true
        ? signatoryName!.trim()
        : schoolName;

    final formattedDate = DateFormat('d MMMM, yyyy').format(letterDate);

    final contactLine = [
      if (schoolPhone.isNotEmpty) 'Tel: $schoolPhone',
      if (schoolEmail.isNotEmpty) schoolEmail,
    ].join('  |  ');

    pw.MemoryImage? logoImage;
    if (schoolLogo.isNotEmpty) {
      final logoFile = File(schoolLogo);
      if (await logoFile.exists()) {
        logoImage = pw.MemoryImage(await logoFile.readAsBytes());
      }
    }

    final args = _LetterArgs(
      schoolName: schoolName,
      schoolAddress: schoolAddress,
      contactLine: contactLine,
      logo: logoImage,
      formattedDate: formattedDate,
      studentName: studentName,
      admissionNo: admissionNo,
      className: className,
      term: term,
      session: session,
      totalBills: totalBills,
      totalPaid: totalPaid,
      outstanding: outstanding,
      signatory: signatory,
      customOpening: customOpening,
      customClosing: customClosing,
      paymentDeadline: paymentDeadline,
      isLastTerm: isLastTerm,
      isZeroPayment: isZeroPayment,
      isPta: isPta,
      isMidTerm: isMidTerm,
      ptaMeetingDate: ptaMeetingDate != null
          ? DateFormat('EEEE, d MMMM yyyy').format(ptaMeetingDate)
          : '',
      ptaMeetingTime: ptaMeetingTime,
      ptaVenue: ptaVenue,
      midTermStart: midTermStartDate != null
          ? DateFormat('d MMMM, yyyy').format(midTermStartDate)
          : '',
      midTermReturn: midTermReturnDate != null
          ? DateFormat('d MMMM, yyyy').format(midTermReturnDate)
          : '',
    );

    final pdf = pw.Document();

    if (threeUp) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 14),
          build: (ctx) => pw.Column(
            children: [
              pw.Expanded(child: _buildThirdLetter(args)),
              _buildCutLine(),
              pw.Expanded(child: _buildThirdLetter(args, label: 'COPY 2')),
              _buildCutLine(),
              pw.Expanded(
                  child: _buildThirdLetter(args, label: 'SCHOOL COPY')),
            ],
          ),
        ),
      );
    } else if (twoUp) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          build: (ctx) => pw.Column(
            children: [
              pw.Expanded(child: _buildHalfLetter(args)),
              _buildCutLine(),
              pw.Expanded(
                  child: _buildHalfLetter(args, label: 'SCHOOL COPY')),
            ],
          ),
        ),
      );
    } else {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 56, vertical: 48),
          build: (ctx) => _buildFullLetter(args),
        ),
      );
    }

    final bytes = Uint8List.fromList(await pdf.save());

    String? filePath;
    if (saveToFile) {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final safeName = studentName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final suffix = threeUp ? '_3up' : (twoUp ? '_2up' : '');
      final file = File(
          '${dir.path}/DebtNotification_${safeName}_$ts$suffix.pdf');
      await file.writeAsBytes(bytes);
      filePath = file.path;
    }

    return (bytes: bytes, filePath: filePath);
  }

  // ── Bulk generation ────────────────────────────────────────────────────────

  static Future<({Uint8List bytes, String? filePath})> generateBulk({
    required Map<String, dynamic> schoolProfile,
    required List<Map<String, dynamic>> students,
    required String term,
    required String session,
    required DateTime letterDate,
    String? signatoryName,
    String? customOpening,
    String? customClosing,
    DateTime? paymentDeadline,
    bool twoUp = false,
    bool threeUp = false,
    bool isLastTerm = false,
    bool isZeroPayment = false,
    bool isPta = false,
    bool isMidTerm = false,
    DateTime? ptaMeetingDate,
    String ptaMeetingTime = '',
    String ptaVenue = '',
    DateTime? midTermStartDate,
    DateTime? midTermReturnDate,
    bool saveToFile = true,
  }) async {
    final schoolName = (schoolProfile['name'] ?? 'School Name').toString();
    final schoolAddress = (schoolProfile['address'] ?? '').toString();
    final schoolPhone = (schoolProfile['phone'] ?? '').toString();
    final schoolEmail = (schoolProfile['email'] ?? '').toString();
    final schoolLogo = (schoolProfile['logoPath'] ?? '').toString();

    final signatory = signatoryName?.trim().isNotEmpty == true
        ? signatoryName!.trim()
        : schoolName;

    final formattedDate = DateFormat('d MMMM, yyyy').format(letterDate);

    final contactLine = [
      if (schoolPhone.isNotEmpty) 'Tel: $schoolPhone',
      if (schoolEmail.isNotEmpty) schoolEmail,
    ].join('  |  ');

    pw.MemoryImage? logoImage;
    if (schoolLogo.isNotEmpty) {
      final logoFile = File(schoolLogo);
      if (await logoFile.exists()) {
        logoImage = pw.MemoryImage(await logoFile.readAsBytes());
      }
    }

    _LetterArgs args(Map<String, dynamic> s) => _LetterArgs(
          schoolName: schoolName,
          schoolAddress: schoolAddress,
          contactLine: contactLine,
          logo: logoImage,
          formattedDate: formattedDate,
          studentName: (s['studentName'] ?? '').toString(),
          admissionNo: (s['admissionNo'] ?? '').toString(),
          className: (s['className'] ?? '').toString(),
          term: term,
          session: session,
          totalBills: (s['totalBills'] as num).toDouble(),
          totalPaid: (s['totalPaid'] as num).toDouble(),
          outstanding: (s['outstanding'] as num).toDouble(),
          signatory: signatory,
          customOpening: customOpening,
          customClosing: customClosing,
          paymentDeadline: paymentDeadline,
          isLastTerm: isLastTerm,
          isZeroPayment: isZeroPayment,
          isPta: isPta,
          isMidTerm: isMidTerm,
          ptaMeetingDate: ptaMeetingDate != null
              ? DateFormat('EEEE, d MMMM yyyy').format(ptaMeetingDate)
              : '',
          ptaMeetingTime: ptaMeetingTime,
          ptaVenue: ptaVenue,
          midTermStart: midTermStartDate != null
              ? DateFormat('d MMMM, yyyy').format(midTermStartDate)
              : '',
          midTermReturn: midTermReturnDate != null
              ? DateFormat('d MMMM, yyyy').format(midTermReturnDate)
              : '',
        );

    final pdf = pw.Document();

    if (threeUp) {
      for (int i = 0; i < students.length; i += 3) {
        final a1 = args(students[i]);
        final a2 = i + 1 < students.length ? args(students[i + 1]) : null;
        final a3 = i + 2 < students.length ? args(students[i + 2]) : null;
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin:
                const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 14),
            build: (ctx) => pw.Column(
              children: [
                pw.Expanded(child: _buildThirdLetter(a1)),
                _buildCutLine(),
                pw.Expanded(
                  child: a2 != null
                      ? _buildThirdLetter(a2)
                      : pw.SizedBox(),
                ),
                _buildCutLine(),
                pw.Expanded(
                  child: a3 != null
                      ? _buildThirdLetter(a3)
                      : pw.SizedBox(),
                ),
              ],
            ),
          ),
        );
      }
    } else if (twoUp) {
      for (int i = 0; i < students.length; i += 2) {
        final a1 = args(students[i]);
        final a2 = i + 1 < students.length ? args(students[i + 1]) : null;
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin:
                const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            build: (ctx) => pw.Column(
              children: [
                pw.Expanded(child: _buildHalfLetter(a1)),
                _buildCutLine(),
                pw.Expanded(
                  child: a2 != null
                      ? _buildHalfLetter(a2)
                      : pw.SizedBox(),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      for (final s in students) {
        final a = args(s);
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(
                horizontal: 56, vertical: 48),
            build: (ctx) => _buildFullLetter(a),
          ),
        );
      }
    }

    final bytes = Uint8List.fromList(await pdf.save());

    String? filePath;
    if (saveToFile) {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final suffix = threeUp ? '_3up' : (twoUp ? '_2up' : '');
      final file =
          File('${dir.path}/DebtNotification_Bulk_$ts$suffix.pdf');
      await file.writeAsBytes(bytes);
      filePath = file.path;
    }

    return (bytes: bytes, filePath: filePath);
  }

  // ── Full-page single letter ────────────────────────────────────────────────

  static pw.Widget _buildFullLetter(_LetterArgs a) {
    final opening = a.customOpening?.trim().isNotEmpty == true
        ? a.customOpening!.trim()
        : a.isPta
            ? 'We are pleased to formally invite you to our '
                'Parent-Teacher Association (PTA) meeting scheduled as follows:\n\n'
                'Date:   ${a.ptaMeetingDate.isNotEmpty ? a.ptaMeetingDate : "To be announced"}\n'
                'Time:   ${a.ptaMeetingTime.isNotEmpty ? a.ptaMeetingTime : "To be announced"}\n'
                'Venue: ${a.ptaVenue.isNotEmpty ? a.ptaVenue : a.schoolName}\n\n'
                'Your presence at this meeting is of utmost importance as we shall '
                'be discussing matters relating to the academic progress and welfare '
                'of all students for the ${a.term} term of the ${a.session} academic session.'
            : a.isMidTerm
                ? 'We write to inform you that the school will be proceeding on '
                    'a mid-term break'
                    '${a.midTermStart.isNotEmpty ? " from ${a.midTermStart}" : ""}. '
                    'Students are expected to resume school'
                    '${a.midTermReturn.isNotEmpty ? " on ${a.midTermReturn}" : " after the break"}.\n\n'
                    'We also wish to bring to your urgent attention that your '
                    'child/ward, ${a.studentName} (Admission No: ${a.admissionNo}), '
                    'currently in ${a.className}, has an outstanding school fee balance '
                    'of N${_currency.format(a.outstanding)} for the ${a.term} term '
                    'of the ${a.session} academic session.'
            : a.isZeroPayment
            ? 'We write to bring to your urgent attention that your child/ward, '
                '${a.studentName} (Admission No: ${a.admissionNo}), currently in '
                '${a.className}, has NOT made any payment whatsoever towards the '
                'school fees for the ${a.term} term of the ${a.session} academic '
                'session. The total school fees billed for this term amount to '
                'N${_currency.format(a.totalBills)}, and as of the date of this '
                'letter, no payment has been received from your ward\'s account.'
            : a.isLastTerm
                ? 'We write to bring to your notice that your child/ward, '
                    '${a.studentName} (Admission No: ${a.admissionNo}), currently '
                    'in ${a.className}, has an uncleared fee balance carried over '
                    'from the ${a.term} term of the ${a.session} academic session. '
                    'The total school fees billed for that term amounted to '
                    'N${_currency.format(a.totalBills)}, out of which '
                    'N${_currency.format(a.totalPaid)} was paid, leaving an '
                    'outstanding balance of N${_currency.format(a.outstanding)} '
                    'which remains unpaid to date.'
                : 'We write to bring to your notice that your child/ward, '
                    '${a.studentName} (Admission No: ${a.admissionNo}), currently in '
                    '${a.className}, has an outstanding fee balance for the ${a.term} '
                    'term of the ${a.session} academic session. The total school fees '
                    'billed for this term amount to N${_currency.format(a.totalBills)}, '
                    'out of which N${_currency.format(a.totalPaid)} has been paid, '
                    'leaving an outstanding balance of '
                    'N${_currency.format(a.outstanding)}.';

    final deadlinePhrase = a.paymentDeadline != null
        ? 'on or before ${DateFormat('d MMMM, yyyy').format(a.paymentDeadline!)}'
        : 'as soon as possible';

    final closing = a.customClosing?.trim().isNotEmpty == true
        ? a.customClosing!.trim()
        : a.isPta
            ? 'We strongly urge all parents and guardians to make every effort '
                'to attend this meeting. Your active participation helps us build a '
                'strong partnership between the school and parents, which is essential '
                'for the academic success and holistic development of our students.\n\n'
                'Please ensure you make the necessary arrangements to be present. '
                'We look forward to seeing you.\n\n'
                'Thank you for your continued support and cooperation.'
            : a.isMidTerm
                ? 'Kindly ensure that your child/ward returns to school after the '
                    'mid-term break with a payment of '
                    'N${_currency.format(a.outstanding)} or as much as possible '
                    'towards the outstanding balance'
                    '${a.midTermReturn.isNotEmpty ? " on ${a.midTermReturn}" : ""}.\n\n'
                    'Please be informed that students with outstanding fee balances '
                    'will NOT be permitted to remain on the school premises after the '
                    'mid-term break without evidence of payment. We strongly encourage '
                    'you to use this break period to make the necessary arrangements.\n\n'
                    'For payment enquiries or to discuss a payment plan, please contact '
                    'the school bursar\'s office'
                    '${a.contactLine.isNotEmpty ? " at ${a.contactLine}" : ""}.\n\n'
                    'Thank you for your understanding and cooperation.'
            : a.isZeroPayment
                ? 'We strongly urge you to make full payment of '
                'N${_currency.format(a.outstanding)} $deadlinePhrase. '
                'Please be advised that your child/ward will NOT be permitted '
                'to continue attending classes until full payment of the school '
                'fees is made. This is a matter that requires your immediate '
                'attention and action.\n\n'
                'Should you wish to discuss a payment arrangement, please '
                'contact the school bursar\'s office without delay'
                '${a.contactLine.isNotEmpty ? " at ${a.contactLine}" : ""}.\n\n'
                'We trust you will treat this matter with the urgency it deserves.'
            : 'Kindly ensure that payment of the outstanding amount of '
                'N${_currency.format(a.outstanding)} is made $deadlinePhrase. '
                'Please be informed that failure to settle this balance by the '
                'due date will result in your child/ward not being permitted to '
                'remain in school until full payment is made.\n\n'
                'Should you require further clarification or wish to discuss a '
                'payment arrangement, please do not hesitate to contact the '
                'school bursar\'s office'
                '${a.contactLine.isNotEmpty ? " at ${a.contactLine}" : ""}.\n\n'
                'Thank you for your continued cooperation and support.';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildLetterhead(
          schoolName: a.schoolName,
          schoolAddress: a.schoolAddress,
          contactLine: a.contactLine,
          logo: a.logo,
        ),
        pw.SizedBox(height: 20),
        pw.Divider(thickness: 1.5, color: PdfColors.grey800),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(a.formattedDate,
              style: const pw.TextStyle(fontSize: 11)),
        ),
        pw.SizedBox(height: 20),
        pw.Text('The Parent/Guardian,',
            style: const pw.TextStyle(fontSize: 11)),
        pw.Text('Of ${a.studentName},',
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text(a.schoolName, style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 18),
        pw.Text('Dear Parent/Guardian,',
            style: pw.TextStyle(
                fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text(
            a.isPta
                ? 'RE: PTA MEETING NOTIFICATION - ${a.term.toUpperCase()}, ${a.session}'
                : a.isMidTerm
                    ? 'RE: MID-TERM HOLIDAY NOTICE & FEE REMINDER - ${a.term.toUpperCase()}, ${a.session}'
                    : a.isZeroPayment
                        ? 'RE: NO PAYMENT RECEIVED - ${a.term.toUpperCase()}, ${a.session}'
                        : a.isLastTerm
                            ? 'RE: UNPAID FEES FROM ${a.term.toUpperCase()} - ${a.session}'
                            : 'RE: OUTSTANDING SCHOOL FEES - ${a.term}, ${a.session}',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(opening,
            style: const pw.TextStyle(fontSize: 11),
            textAlign: pw.TextAlign.justify),
        pw.SizedBox(height: 20),
        pw.Text(closing,
            style: const pw.TextStyle(fontSize: 11),
            textAlign: pw.TextAlign.justify),
        pw.SizedBox(height: 36),
        pw.Text('Yours faithfully,',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 40),
        pw.Container(
          width: 200,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom:
                  pw.BorderSide(color: PdfColors.grey800, width: 0.5),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(a.signatory,
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text('Bursary Department',
            style: const pw.TextStyle(fontSize: 10)),
        pw.Text(a.schoolName, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 6),
        pw.Text('Date: ${a.formattedDate}',
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey700)),
        pw.Spacer(),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.Center(
          child: pw.Text(
            'This is a computer-generated letter — ${a.schoolName}',
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ],
    );
  }

  // ── Half-page compact letter (2-up) ───────────────────────────────────────

  static pw.Widget _buildHalfLetter(_LetterArgs a, {String? label}) {
    final opening = a.customOpening?.trim().isNotEmpty == true
        ? a.customOpening!.trim()
        : a.isPta
            ? 'You are invited to our PTA meeting:\n'
                'Date: ${a.ptaMeetingDate.isNotEmpty ? a.ptaMeetingDate : "TBA"}  '
                'Time: ${a.ptaMeetingTime.isNotEmpty ? a.ptaMeetingTime : "TBA"}  '
                'Venue: ${a.ptaVenue.isNotEmpty ? a.ptaVenue : a.schoolName}\n\n'
                'Your attendance is very important as we will discuss matters on '
                'the academic progress and welfare of students for ${a.term}, ${a.session}.'
            : a.isMidTerm
                ? 'The school will be on mid-term break'
                    '${a.midTermStart.isNotEmpty ? " from ${a.midTermStart}" : ""}. '
                    'Students resume'
                    '${a.midTermReturn.isNotEmpty ? " on ${a.midTermReturn}" : " after the break"}. '
                    'Your child/ward, ${a.studentName} '
                    '(Adm: ${a.admissionNo}, ${a.className}), has an outstanding '
                    'fee balance of N${_currency.format(a.outstanding)} for ${a.term}, ${a.session}.'
            : a.isZeroPayment
            ? 'We write to urgently notify you that your child/ward, ${a.studentName} '
                '(Admission No: ${a.admissionNo}, Class: ${a.className}), has made '
                'NO payment at all towards school fees for ${a.term}, ${a.session}. '
                'Total fees billed: N${_currency.format(a.totalBills)}. '
                'Amount paid: N0.00. Full balance outstanding: '
                'N${_currency.format(a.outstanding)}.'
            : a.isLastTerm
                ? 'We write to notify you that your child/ward, ${a.studentName} '
                    '(Admission No: ${a.admissionNo}, Class: ${a.className}), has '
                    'an uncleared fee balance carried over from ${a.term}, '
                    '${a.session}. Total billed: N${_currency.format(a.totalBills)}, '
                    'paid: N${_currency.format(a.totalPaid)}, outstanding balance: '
                    'N${_currency.format(a.outstanding)}, which remains unpaid to date.'
                : 'We write to notify you that your child/ward, ${a.studentName} '
                    '(Admission No: ${a.admissionNo}, Class: ${a.className}), has an '
                    'outstanding fee balance for ${a.term}, ${a.session}. The total '
                    'fees billed amount to N${_currency.format(a.totalBills)}, out of '
                    'which N${_currency.format(a.totalPaid)} has been paid, leaving an '
                    'outstanding balance of N${_currency.format(a.outstanding)}.';

    final deadlinePhrase = a.paymentDeadline != null
        ? 'on or before ${DateFormat('d MMMM, yyyy').format(a.paymentDeadline!)}'
        : 'promptly';

    final closing = a.customClosing?.trim().isNotEmpty == true
        ? a.customClosing!.trim()
        : a.isPta
            ? 'We strongly urge all parents/guardians to attend. '
                'Your participation is vital for the academic development of our students. '
                'Thank you for your continued support.'
            : a.isMidTerm
                ? 'Your child/ward MUST return with a payment of '
                    'N${_currency.format(a.outstanding)}'
                    '${a.midTermReturn.isNotEmpty ? " on ${a.midTermReturn}" : " after the break"}. '
                    'Students with outstanding balances will NOT be permitted to '
                    'remain on school premises without payment'
                    '${a.contactLine.isNotEmpty ? ". Contact: ${a.contactLine}" : ""}. '
                    'Thank you.'
            : a.isZeroPayment
                ? 'Immediate payment of N${_currency.format(a.outstanding)} is required $deadlinePhrase. '
                    'Your child/ward will NOT be permitted to attend classes until full '
                    'payment is made. Please contact the bursar\'s office urgently'
                    '${a.contactLine.isNotEmpty ? " at ${a.contactLine}" : ""}. '
                    'Thank you.'
                : 'Kindly pay the outstanding balance of '
                'N${_currency.format(a.outstanding)} $deadlinePhrase. '
                'Please note that failure to do so will result in your child/ward '
                'not being permitted to remain in school'
                '${a.contactLine.isNotEmpty ? ". Contact: ${a.contactLine}" : ""}. '
                'Thank you.';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey700)),
            ),
          ),
          pw.SizedBox(height: 4),
        ],
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (a.logo != null) ...[
              pw.Image(a.logo!, width: 46, height: 46),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    a.schoolName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  if (a.schoolAddress.isNotEmpty)
                    pw.Text(a.schoolAddress,
                        style: const pw.TextStyle(fontSize: 10),
                        textAlign: pw.TextAlign.center),
                  if (a.contactLine.isNotEmpty)
                    pw.Text(a.contactLine,
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey700),
                        textAlign: pw.TextAlign.center),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1, color: PdfColors.grey800),
        pw.SizedBox(height: 6),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(a.formattedDate,
              style: const pw.TextStyle(fontSize: 10)),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'The Parent/Guardian of ${a.studentName}  |  ${a.schoolName}',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Dear Parent/Guardian,',
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            a.isPta
                ? 'RE: PTA MEETING NOTIFICATION - ${a.term.toUpperCase()}, ${a.session}'
                : a.isMidTerm
                    ? 'RE: MID-TERM NOTICE & FEE REMINDER - ${a.term.toUpperCase()}, ${a.session}'
                    : a.isZeroPayment
                        ? 'RE: NO PAYMENT RECEIVED - ${a.term.toUpperCase()}, ${a.session}'
                        : a.isLastTerm
                            ? 'RE: UNPAID FEES FROM ${a.term.toUpperCase()} - ${a.session}'
                            : 'RE: OUTSTANDING SCHOOL FEES - ${a.term}, ${a.session}',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(opening,
            style: const pw.TextStyle(fontSize: 10),
            textAlign: pw.TextAlign.justify),
        pw.SizedBox(height: 10),
        pw.Text(closing,
            style: const pw.TextStyle(fontSize: 10),
            textAlign: pw.TextAlign.justify),
        pw.SizedBox(height: 10),
        pw.Text('Yours faithfully,',
            style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 22),
        pw.Container(
          width: 160,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey800, width: 0.5),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(a.signatory,
            style:
                pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text(
          'Bursary Department  |  ${a.schoolName}  |  ${a.formattedDate}',
          style: const pw.TextStyle(
              fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    );
  }

  // ── Third-page compact letter (3-up) ──────────────────────────────────────

  static pw.Widget _buildThirdLetter(_LetterArgs a, {String? label}) {
    final opening = a.customOpening?.trim().isNotEmpty == true
        ? a.customOpening!.trim()
        : a.isPta
            ? 'PTA Meeting — '
                '${a.ptaMeetingDate.isNotEmpty ? a.ptaMeetingDate : "TBA"}, '
                '${a.ptaMeetingTime.isNotEmpty ? a.ptaMeetingTime : "TBA"} @ '
                '${a.ptaVenue.isNotEmpty ? a.ptaVenue : a.schoolName}. '
                'Your attendance is required to discuss student welfare and progress '
                'for ${a.term}, ${a.session}.'
            : a.isMidTerm
                ? 'Mid-term break'
                    '${a.midTermStart.isNotEmpty ? ": ${a.midTermStart}" : ""}. '
                    'Resume${a.midTermReturn.isNotEmpty ? ": ${a.midTermReturn}" : " after break"}. '
                    '${a.studentName} (${a.className}) has an outstanding fee balance '
                    'of N${_currency.format(a.outstanding)} for ${a.term}, ${a.session}.'
            : a.isZeroPayment
            ? 'We urgently notify you that your child/ward, ${a.studentName} '
                '(Adm: ${a.admissionNo}, ${a.className}), has made NO payment '
                'for ${a.term}, ${a.session}. Total billed: '
                'N${_currency.format(a.totalBills)}, paid: N0.00, '
                'full balance outstanding: N${_currency.format(a.outstanding)}.'
            : a.isLastTerm
                ? 'We notify you that your child/ward, ${a.studentName} '
                    '(Adm: ${a.admissionNo}, ${a.className}), has an uncleared fee '
                    'balance from ${a.term}, ${a.session}. Billed: '
                    'N${_currency.format(a.totalBills)}, paid: '
                    'N${_currency.format(a.totalPaid)}, outstanding: '
                    'N${_currency.format(a.outstanding)}, still unpaid to date.'
                : 'We notify you that your child/ward, ${a.studentName} '
                    '(Adm: ${a.admissionNo}, ${a.className}), has an outstanding fee '
                    'balance for ${a.term}, ${a.session}. Total fees billed: '
                    'N${_currency.format(a.totalBills)}, amount paid: '
                    'N${_currency.format(a.totalPaid)}, outstanding balance: '
                    'N${_currency.format(a.outstanding)}.';

    final deadlinePhrase = a.paymentDeadline != null
        ? 'by ${DateFormat('d MMM yyyy').format(a.paymentDeadline!)}'
        : 'promptly';

    final closing = a.customClosing?.trim().isNotEmpty == true
        ? a.customClosing!.trim()
        : a.isPta
            ? 'All parents/guardians are strongly urged to attend. '
                'Your presence matters for your child\'s academic welfare. '
                'Thank you.'
            : a.isMidTerm
                ? 'Your ward MUST return with payment of N${_currency.format(a.outstanding)}'
                    '${a.midTermReturn.isNotEmpty ? " on ${a.midTermReturn}" : " after the break"}. '
                    'Students with outstanding balances will NOT be allowed on school premises'
                    '${a.contactLine.isNotEmpty ? ". Contact: ${a.contactLine}" : ""}. '
                    'Thank you.'
            : a.isZeroPayment
                ? 'Immediate full payment of N${_currency.format(a.outstanding)} '
                    'is required $deadlinePhrase. Your ward will NOT attend classes '
                    'until fees are fully paid'
                    '${a.contactLine.isNotEmpty ? ". Contact: ${a.contactLine}" : ""}. '
                    'Thank you.'
                : 'Please pay the outstanding balance of '
                'N${_currency.format(a.outstanding)} $deadlinePhrase. '
                'Failure to do so will result in your child/ward not being '
                'permitted to remain in school'
                '${a.contactLine.isNotEmpty ? ". Contact: ${a.contactLine}" : ""}. '
                'Thank you.';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Copy label
        if (label != null) ...[
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 5, vertical: 2),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey700)),
            ),
          ),
          pw.SizedBox(height: 3),
        ],

        // Compact letterhead
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (a.logo != null) ...[
              pw.Image(a.logo!, width: 36, height: 36),
              pw.SizedBox(width: 8),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    a.schoolName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  if (a.schoolAddress.isNotEmpty)
                    pw.Text(a.schoolAddress,
                        style: const pw.TextStyle(fontSize: 9),
                        textAlign: pw.TextAlign.center),
                  if (a.contactLine.isNotEmpty)
                    pw.Text(a.contactLine,
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey700),
                        textAlign: pw.TextAlign.center),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.8, color: PdfColors.grey800),
        pw.SizedBox(height: 4),

        // Date + address inline
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'The Parent/Guardian of ${a.studentName}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(a.formattedDate,
                style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        pw.SizedBox(height: 5),

        pw.Text('Dear Parent/Guardian,',
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),

        pw.Center(
          child: pw.Text(
            a.isPta
                ? 'RE: PTA MEETING - ${a.term.toUpperCase()}, ${a.session}'
                : a.isMidTerm
                    ? 'RE: MID-TERM NOTICE & FEE REMINDER - ${a.term.toUpperCase()}, ${a.session}'
                    : a.isZeroPayment
                        ? 'RE: NO PAYMENT RECEIVED - ${a.term.toUpperCase()}, ${a.session}'
                        : a.isLastTerm
                            ? 'RE: UNPAID FEES FROM ${a.term.toUpperCase()} - ${a.session}'
                            : 'RE: OUTSTANDING SCHOOL FEES - ${a.term}, ${a.session}',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(height: 6),

        pw.Text(opening,
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.justify),
        pw.SizedBox(height: 7),

        pw.Text(closing,
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.justify),
        pw.SizedBox(height: 8),

        pw.Text('Yours faithfully,',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 16),
        pw.Container(
          width: 130,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey800, width: 0.5),
            ),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(a.signatory,
            style:
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text(
          'Bursary Dept  |  ${a.schoolName}  |  ${a.formattedDate}',
          style: const pw.TextStyle(
              fontSize: 7, color: PdfColors.grey700),
        ),
      ],
    );
  }

  // ── Cut line ──────────────────────────────────────────────────────────────

  static pw.Widget _buildCutLine() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Divider(
        thickness: 0.5,
        color: PdfColors.grey400,
        borderStyle: pw.BorderStyle.dashed,
      ),
    );
  }

  // ── Letterhead (full size) ─────────────────────────────────────────────────

  static pw.Widget _buildLetterhead({
    required String schoolName,
    required String schoolAddress,
    required String contactLine,
    pw.MemoryImage? logo,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null) ...[
          pw.Image(logo, width: 64, height: 64),
          pw.SizedBox(width: 16),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                schoolName.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                ),
                textAlign: pw.TextAlign.center,
              ),
              if (schoolAddress.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(schoolAddress,
                    style: const pw.TextStyle(fontSize: 10),
                    textAlign: pw.TextAlign.center),
              ],
              if (contactLine.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text(contactLine,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center),
              ],
            ],
          ),
        ),
      ],
    );
  }

}

// ── Data carrier ───────────────────────────────────────────────────────────

class _LetterArgs {
  final String schoolName;
  final String schoolAddress;
  final String contactLine;
  final pw.MemoryImage? logo;
  final String formattedDate;
  final String studentName;
  final String admissionNo;
  final String className;
  final String term;
  final String session;
  final double totalBills;
  final double totalPaid;
  final double outstanding;
  final String signatory;
  final String? customOpening;
  final String? customClosing;
  final DateTime? paymentDeadline;
  final bool isLastTerm;
  final bool isZeroPayment;
  final bool isPta;
  final bool isMidTerm;
  final String ptaMeetingDate;
  final String ptaMeetingTime;
  final String ptaVenue;
  final String midTermStart;
  final String midTermReturn;

  const _LetterArgs({
    required this.schoolName,
    required this.schoolAddress,
    required this.contactLine,
    required this.logo,
    required this.formattedDate,
    required this.studentName,
    required this.admissionNo,
    required this.className,
    required this.term,
    required this.session,
    required this.totalBills,
    required this.totalPaid,
    required this.outstanding,
    required this.signatory,
    this.customOpening,
    this.customClosing,
    this.paymentDeadline,
    this.isLastTerm = false,
    this.isZeroPayment = false,
    this.isPta = false,
    this.isMidTerm = false,
    this.ptaMeetingDate = '',
    this.ptaMeetingTime = '',
    this.ptaVenue = '',
    this.midTermStart = '',
    this.midTermReturn = '',
  });
}
