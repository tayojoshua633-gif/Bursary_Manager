import 'dart:typed_data';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'pdf_export_helper.dart';

/// Writes an HTML string to a PDF file using Android's native WebView print
/// pipeline (same mechanism as a browser's "Print / Save as PDF"). Used by
/// every generator's Android branch — see custom_report_pdf_generator.dart
/// for the reasoning (avoids the pure-Dart `pdf` package's memory
/// characteristics, which caused OOM crashes on constrained devices).
class NativeHtmlPdfHelper {
  static Future<String> saveHtmlAsPdf({
    required String html,
    required String baseFileName,
    required bool saveToDownloads,
  }) async {
    final dir = await PdfExportDirectoryHelper.resolve(saveToDownloads: saveToDownloads);
    final file = await HtmlToPdfConverter().convertHtmlToPdf(
      html: html,
      targetDirectory: dir.path,
      targetName: baseFileName,
      pageSize: PdfPageSize.a4,
    );
    return file.path;
  }

  /// Same as [saveHtmlAsPdf] but returns raw bytes without writing to disk —
  /// used for in-app print-preview flows (e.g. `Printing.layoutPdf`).
  static Future<Uint8List> htmlToBytes(String html) {
    return HtmlToPdfConverter().convertHtmlToPdfBytes(html: html, pageSize: PdfPageSize.a4);
  }
}
