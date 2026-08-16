// Run with: flutter test test/generate_debt_samples.dart
// Saves 3 sample PDFs to the Desktop.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bursary_manager/utils/debt_notification_pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate sample debt notification PDFs', () async {
    final desktop = 'C:/Users/tylyr/Desktop';

    final school = {
      'name': 'Greenfield Academy',
      'address': '14 School Road, Ikeja, Lagos',
      'phone': '08012345678',
      'email': 'bursar@greenfield.edu.ng',
      'logoPath': '',
    };

    final letterDate = DateTime(2026, 5, 18);
    final deadline = DateTime(2026, 5, 30);

    // ── Sample 1: 1-per-page (full letter) ────────────────────────────
    final r1 = await DebtNotificationPdfGenerator.generate(
      schoolProfile: school,
      studentName: 'Adebayo Oluwaseun Emmanuel',
      admissionNo: 'GFA/2023/0041',
      className: 'JSS 2A',
      term: 'Second Term',
      session: '2025/2026',
      totalBills: 185000,
      totalPaid: 80000,
      outstanding: 105000,
      letterDate: letterDate,
      signatoryName: 'Mrs. Chioma Okafor',
      paymentDeadline: deadline,
      saveToFile: false,
      twoUp: false,
      threeUp: false,
    );
    await File('$desktop/debt_sample_v4_1_per_page.pdf')
        .writeAsBytes(r1.bytes);
    print('Saved: debt_sample_v4_1_per_page.pdf');

    // ── Sample 2: 2-per-page (2 different students) ───────────────────
    final r2 = await DebtNotificationPdfGenerator.generateBulk(
      schoolProfile: school,
      students: [
        {
          'studentName': 'Adebayo Oluwaseun Emmanuel',
          'admissionNo': 'GFA/2023/0041',
          'className': 'JSS 2A',
          'totalBills': 185000.0,
          'totalPaid': 80000.0,
          'outstanding': 105000.0,
        },
        {
          'studentName': 'Ngozi Chidinma Eze',
          'admissionNo': 'GFA/2023/0057',
          'className': 'SSS 1B',
          'totalBills': 210000.0,
          'totalPaid': 210000.0 - 62500.0,
          'outstanding': 62500.0,
        },
      ],
      term: 'Second Term',
      session: '2025/2026',
      letterDate: letterDate,
      signatoryName: 'Mrs. Chioma Okafor',
      paymentDeadline: deadline,
      twoUp: true,
      threeUp: false,
      saveToFile: false,
    );
    await File('$desktop/debt_sample_v4_2_per_page.pdf')
        .writeAsBytes(r2.bytes);
    print('Saved: debt_sample_v4_2_per_page.pdf');

    // ── Sample 3: 3-per-page (3 different students) ───────────────────
    final r3 = await DebtNotificationPdfGenerator.generateBulk(
      schoolProfile: school,
      students: [
        {
          'studentName': 'Adebayo Oluwaseun Emmanuel',
          'admissionNo': 'GFA/2023/0041',
          'className': 'JSS 2A',
          'totalBills': 185000.0,
          'totalPaid': 80000.0,
          'outstanding': 105000.0,
        },
        {
          'studentName': 'Ngozi Chidinma Eze',
          'admissionNo': 'GFA/2023/0057',
          'className': 'SSS 1B',
          'totalBills': 210000.0,
          'totalPaid': 147500.0,
          'outstanding': 62500.0,
        },
        {
          'studentName': 'Tunde Afolabi Babatunde',
          'admissionNo': 'GFA/2024/0012',
          'className': 'JSS 3C',
          'totalBills': 175000.0,
          'totalPaid': 50000.0,
          'outstanding': 125000.0,
        },
      ],
      term: 'Second Term',
      session: '2025/2026',
      letterDate: letterDate,
      signatoryName: 'Mrs. Chioma Okafor',
      paymentDeadline: deadline,
      twoUp: false,
      threeUp: true,
      saveToFile: false,
    );
    await File('$desktop/debt_sample_v4_3_per_page.pdf')
        .writeAsBytes(r3.bytes);
    print('Saved: debt_sample_v4_3_per_page.pdf');

    print('\nAll 3 samples saved to your Desktop.');
  });
}
