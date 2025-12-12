import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';

class ExcelGenerator {
  static Future<File> generateStudentListExcel(
      List<Map<String, dynamic>> students) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Students'];

    // Headers - Use TextCellValue for Excel 4.0+
    sheet.appendRow([
      TextCellValue("SN"),
      TextCellValue("Surname"),
      TextCellValue("First Name"),
      TextCellValue("Class"),
      TextCellValue("Admission No"),
    ]);

    // Data rows - Use TextCellValue for all string values
    for (int i = 0; i < students.length; i++) {
      final s = students[i];

      sheet.appendRow([
        TextCellValue((i + 1).toString()),
        TextCellValue(s["surname"] ?? ""),
        TextCellValue(s["firstName"] ?? ""),
        TextCellValue(s["className"] ?? ""),
        TextCellValue(s["admissionNo"] ?? ""),
      ]);
    }

    final bytes = excel.save();

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/students_list.xlsx");

    await file.writeAsBytes(bytes!);
    return file;
  }
}