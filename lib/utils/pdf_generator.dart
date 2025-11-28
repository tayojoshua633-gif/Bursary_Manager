import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

class PDFGenerator {
  /// Generate PDF for the student list
  static Future<File> generateStudentListPDF(List<Map<String, dynamic>> students) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "Student List",
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 20),

              pw.TableHelper.fromTextArray(
                headers: ["Surname", "First Name", "Admission No"],
                data: students.map((s) {
                  return [
                    s['surname'] ?? '',
                    s['firstName'] ?? '',
                    s['admissionNo'] ?? '',
                  ];
                }).toList(),
              ),
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/students_list.pdf");

    return await file.writeAsBytes(await pdf.save());
  }
}
