import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';

class ExcelGenerator {
  static Future<File> generateStudentListExcel(
      List<Map<String, dynamic>> students) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Students'];

    // Headers
    sheet.appendRow(["SN", "Surname", "First Name", "Class", "Admission No"]);

    for (int i = 0; i < students.length; i++) {
      final s = students[i];

      sheet.appendRow([
        (i + 1).toString(),
        s["surname"] ?? "",
        s["firstName"] ?? "",
        s["className"] ?? "",
        s["admissionNo"] ?? "",
      ]);
    }

    final bytes = excel.save();

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/students_list.xlsx");

    await file.writeAsBytes(bytes!);
    return file;
  }
}
