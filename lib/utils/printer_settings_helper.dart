// lib/utils/printer_settings_helper.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';

class PrinterSize {
  final String name;
  final double widthMm;
  final double fontSize;
  final double titleFontSize;
  final double amountFontSize;
  final double margin;
  final double lineSpacing;

  const PrinterSize({
    required this.name,
    required this.widthMm,
    required this.fontSize,
    required this.titleFontSize,
    required this.amountFontSize,
    required this.margin,
    required this.lineSpacing,
  });

  double get widthPoints => widthMm * PdfPageFormat.mm;
}

class PrinterSettingsHelper {
  static const String _paperSizeKey = 'thermal_printer_paper_size';

  // PRESET CONFIGURATIONS FOR COMMON PAPER SIZES
  // =============================================
  
  /// 58mm Paper (Most Common Small Printer)
  /// - Narrow width requires smaller fonts
  /// - Tighter spacing
  /// - Reduced margins
  static const PrinterSize size58mm = PrinterSize(
    name: '58mm',
    widthMm: 58,
    fontSize: 7,           // Smaller font
    titleFontSize: 9,      // Smaller title
    amountFontSize: 12,    // Smaller amount
    margin: 4,             // Tighter margins
    lineSpacing: 2,        // Compact spacing
  );

  /// 80mm Paper (Standard Thermal Printer)
  /// - Most common size
  /// - Comfortable reading
  /// - Standard layout
  static const PrinterSize size80mm = PrinterSize(
    name: '80mm',
    widthMm: 80,
    fontSize: 8,           // Standard font
    titleFontSize: 11,     // Standard title
    amountFontSize: 14,    // Standard amount
    margin: 8,             // Standard margins
    lineSpacing: 3,        // Normal spacing
  );

  /// 110mm Paper (Wide Format)
  /// - Wider paper allows larger fonts
  /// - More comfortable reading
  /// - Spacious layout
  static const PrinterSize size110mm = PrinterSize(
    name: '110mm',
    widthMm: 110,
    fontSize: 9,           // Larger font
    titleFontSize: 13,     // Larger title
    amountFontSize: 16,    // Larger amount
    margin: 12,            // More margins
    lineSpacing: 4,        // More spacing
  );

  /// Custom size (for special requirements)
  static PrinterSize createCustomSize({
    required String name,
    required double widthMm,
    double? fontSize,
    double? titleFontSize,
    double? amountFontSize,
    double? margin,
    double? lineSpacing,
  }) {
    // Auto-calculate sizes based on width if not provided
    final scale = widthMm / 80; // Use 80mm as baseline
    
    return PrinterSize(
      name: name,
      widthMm: widthMm,
      fontSize: fontSize ?? (8 * scale).clamp(6, 10),
      titleFontSize: titleFontSize ?? (11 * scale).clamp(9, 14),
      amountFontSize: amountFontSize ?? (14 * scale).clamp(12, 18),
      margin: margin ?? (8 * scale).clamp(4, 16),
      lineSpacing: lineSpacing ?? (3 * scale).clamp(2, 5),
    );
  }

  // AVAILABLE SIZES
  static const List<PrinterSize> availableSizes = [
    size58mm,
    size80mm,
    size110mm,
  ];

  /// Get current printer size setting
  static Future<PrinterSize> getCurrentSize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSize = prefs.getString(_paperSizeKey);

    switch (savedSize) {
      case '58mm':
        return size58mm;
      case '80mm':
        return size80mm;
      case '110mm':
        return size110mm;
      default:
        return size80mm; // Default to 80mm
    }
  }

  /// Save printer size setting
  static Future<void> setCurrentSize(PrinterSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paperSizeKey, size.name);
  }

  /// Get printer size by name
  static PrinterSize getSizeByName(String name) {
    switch (name) {
      case '58mm':
        return size58mm;
      case '80mm':
        return size80mm;
      case '110mm':
        return size110mm;
      default:
        return size80mm;
    }
  }

  /// Get size description for display
  static String getSizeDescription(String name) {
    switch (name) {
      case '58mm':
        return 'Small (58mm) - Compact receipt, smallest thermal printers';
      case '80mm':
        return 'Standard (80mm) - Most common thermal printer size';
      case '110mm':
        return 'Wide (110mm) - Large format, more readable';
      default:
        return 'Standard (80mm)';
    }
  }

  /// Check if size is supported
  static bool isSizeSupported(String name) {
    return availableSizes.any((size) => size.name == name);
  }

  /// Get all available size names
  static List<String> getAllSizeNames() {
    return availableSizes.map((size) => size.name).toList();
  }

  /// Reset to default (80mm)
  static Future<void> resetToDefault() async {
    await setCurrentSize(size80mm);
  }
}