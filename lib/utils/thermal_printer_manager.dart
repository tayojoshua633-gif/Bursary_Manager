import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ThermalPrinterManager {
  static BluetoothDevice? _connectedPrinter;
  static BluetoothCharacteristic? _writeCharacteristic;
  static StreamSubscription? _connectionSubscription;

  // Storage keys
  static const String _recentPrintersKey = 'recent_printers';
  static const String _defaultPrinterKey = 'default_printer';
  static const String _printerPaperSizeKey = 'printer_paper_sizes';

  // Format currency with thousands separator (2 decimal places)
  static String _formatAmount(double amount) {
    final formatter = NumberFormat("#,##0.00");
    return formatter.format(amount);
  }

  // Format currency as whole number (no decimal places)
  static String _formatInt(double amount) {
    final formatter = NumberFormat("#,##0");
    return formatter.format(amount);
  }

  // Chars per line for the default font, per paper size (see esc_pos_utils Generator._getMaxCharsPerLine)
  static int _charsPerLine(PaperSize paperSize) {
    if (paperSize == PaperSize.mm58) return 32;
    if (paperSize == PaperSize.mm72) return 42;
    return 48;
  }

  // Truncate text to fit a column so long names never wrap and break row alignment
  static String _fitToWidth(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    if (maxChars <= 1) return text.substring(0, maxChars);
    return '${text.substring(0, maxChars - 1)}.';
  }

  // Build phone line after school address
  static List<int> _buildPhoneLine(Generator generator, String? schoolPhone) {
    List<int> bytes = [];
    if (schoolPhone != null && schoolPhone.isNotEmpty) {
      bytes += generator.text('Tel: $schoolPhone',
          styles: const PosStyles(align: PosAlign.center));
    }
    return bytes;
  }

  // Build bank details section before footer/cut
  static List<int> _buildBankDetailsSection(Generator generator, List<Map<String, dynamic>>? bankAccounts) {
    List<int> bytes = [];
    if (bankAccounts == null || bankAccounts.isEmpty) return bytes;

    // Filter to only accounts with bank name and account number
    final validAccounts = bankAccounts.where((acc) {
      final bankName = acc['bankName']?.toString() ?? '';
      final accNum = acc['accountNumber']?.toString() ?? '';
      return bankName.isNotEmpty && accNum.isNotEmpty;
    }).toList();

    if (validAccounts.isEmpty) return bytes;

    bytes += generator.text('BANK DETAILS',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr(ch: '-');

    for (var acc in validAccounts) {
      final bankName = acc['bankName']?.toString() ?? '';
      final accNum = acc['accountNumber']?.toString() ?? '';
      final accName = acc['accountName']?.toString() ?? '';
      bytes += generator.text(bankName,
          styles: const PosStyles(bold: true));
      bytes += generator.text('$accNum - $accName');
      bytes += generator.emptyLines(1);
    }

    bytes += generator.hr(ch: '-');
    return bytes;
  }

  // Get connected printer
  static BluetoothDevice? get connectedPrinter => _connectedPrinter;

  // ============================================================
  // RECENTLY USED PRINTERS & DEFAULT PRINTER STORAGE
  // ============================================================

  // Get recently used printers
  static Future<List<Map<String, String>>> getRecentPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_recentPrintersKey);
    if (jsonString == null) return [];

    try {
      final List<dynamic> decoded = json.decode(jsonString);
      return decoded.map((item) => Map<String, String>.from(item)).toList();
    } catch (e) {
      debugPrint('Error loading recent printers: $e');
      return [];
    }
  }

  // Add printer to recently used list
  static Future<void> addToRecentPrinters(BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = await getRecentPrinters();

    // Create printer info map
    final printerInfo = {
      'name': device.platformName,
      'remoteId': device.remoteId.toString(),
    };

    // Remove if already exists (to move to top)
    recent.removeWhere((p) => p['remoteId'] == printerInfo['remoteId']);

    // Add to beginning of list
    recent.insert(0, printerInfo);

    // Keep only last 5
    if (recent.length > 5) {
      recent.removeRange(5, recent.length);
    }

    // Save
    await prefs.setString(_recentPrintersKey, json.encode(recent));
  }

  // Get default printer
  static Future<Map<String, String>?> getDefaultPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_defaultPrinterKey);
    if (jsonString == null) return null;

    try {
      return Map<String, String>.from(json.decode(jsonString));
    } catch (e) {
      debugPrint('Error loading default printer: $e');
      return null;
    }
  }

  // Set default printer
  static Future<void> setDefaultPrinter(BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final printerInfo = {
      'name': device.platformName,
      'remoteId': device.remoteId.toString(),
    };
    await prefs.setString(_defaultPrinterKey, json.encode(printerInfo));
  }

  // Set default printer from saved printer info
  static Future<void> setDefaultPrinterFromInfo(Map<String, String> printerInfo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultPrinterKey, json.encode(printerInfo));
  }

  // Clear default printer
  static Future<void> clearDefaultPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultPrinterKey);
  }

  // Check if a device is the default printer
  static Future<bool> isDefaultPrinter(String remoteId) async {
    final defaultPrinter = await getDefaultPrinter();
    return defaultPrinter?['remoteId'] == remoteId;
  }

  // ============================================================
  // PAPER SIZE SETTINGS PER PRINTER
  // ============================================================

  // Get paper size for a printer (returns 'mm58' or 'mm80')
  static Future<String> getPrinterPaperSize(String remoteId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_printerPaperSizeKey);
    if (jsonString == null) return 'mm58'; // Default to 58mm

    try {
      final Map<String, dynamic> sizes = json.decode(jsonString);
      return sizes[remoteId] ?? 'mm58';
    } catch (e) {
      debugPrint('Error loading paper size: $e');
      return 'mm58';
    }
  }

  // Set paper size for a printer
  static Future<void> setPrinterPaperSize(String remoteId, String paperSize) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_printerPaperSizeKey);

    Map<String, dynamic> sizes = {};
    if (jsonString != null) {
      try {
        sizes = Map<String, dynamic>.from(json.decode(jsonString));
      } catch (e) {
        debugPrint('Error parsing paper sizes: $e');
      }
    }

    sizes[remoteId] = paperSize;
    await prefs.setString(_printerPaperSizeKey, json.encode(sizes));
  }

  // Get PaperSize enum from stored string
  static Future<PaperSize> getPrinterPaperSizeEnum(String remoteId) async {
    final size = await getPrinterPaperSize(remoteId);
    return size == 'mm80' ? PaperSize.mm80 : PaperSize.mm58;
  }

  // ============================================================
  // REMOVE PRINTER FROM RECENT LIST
  // ============================================================

  // Remove a printer from recent printers list
  static Future<void> removeFromRecentPrinters(String remoteId) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = await getRecentPrinters();

    recent.removeWhere((p) => p['remoteId'] == remoteId);
    await prefs.setString(_recentPrintersKey, json.encode(recent));

    // Also clear default if it was the removed printer
    final defaultPrinter = await getDefaultPrinter();
    if (defaultPrinter?['remoteId'] == remoteId) {
      await clearDefaultPrinter();
    }

    // Also clear paper size setting
    final sizesJson = prefs.getString(_printerPaperSizeKey);
    if (sizesJson != null) {
      try {
        final sizes = Map<String, dynamic>.from(json.decode(sizesJson));
        sizes.remove(remoteId);
        await prefs.setString(_printerPaperSizeKey, json.encode(sizes));
      } catch (e) {
        debugPrint('Error removing paper size: $e');
      }
    }
  }

  // Clear all saved printers
  static Future<void> clearAllSavedPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentPrintersKey);
    await prefs.remove(_defaultPrinterKey);
    await prefs.remove(_printerPaperSizeKey);
  }

  // Check if connected
  static bool get isConnected => _connectedPrinter != null;

  // Request Bluetooth permissions
  static Future<bool> requestBluetoothPermissions() async {
    if (!Platform.isAndroid) {
      return true; // iOS handles permissions differently
    }

    try {
      // Request all necessary Bluetooth and location permissions
      // Location is required for Bluetooth scanning on Android
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      // Check if critical permissions are granted
      final bluetoothScanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
      final bluetoothConnectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      final locationGranted = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

      debugPrint('Bluetooth Scan: $bluetoothScanGranted');
      debugPrint('Bluetooth Connect: $bluetoothConnectGranted');
      debugPrint('Location: $locationGranted');

      // All three permissions are needed for Bluetooth scanning
      return bluetoothScanGranted && bluetoothConnectGranted && locationGranted;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  // Check if Bluetooth is turned on
  static Future<bool> isBluetoothOn() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('Error checking Bluetooth state: $e');
      return false;
    }
  }

  // Turn on Bluetooth (only works on Android)
  static Future<void> requestBluetoothOn() async {
    try {
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }
    } catch (e) {
      debugPrint('Error turning on Bluetooth: $e');
      rethrow;
    }
  }

  // Scan for Bluetooth devices
  static Future<List<ScanResult>> scanForPrinters({Duration timeout = const Duration(seconds: 10)}) async {
    final devices = <ScanResult>[];

    try {
      // Check if Bluetooth is supported
      if (await FlutterBluePlus.isSupported == false) {
        throw Exception('Bluetooth not supported on this device');
      }

      // Start scanning
      await FlutterBluePlus.startScan(timeout: timeout);

      // Listen to scan results
      final subscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          // Only add if not already in list
          if (!devices.any((d) => d.device.remoteId == result.device.remoteId)) {
            devices.add(result);
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(timeout);
      await subscription.cancel();
      await FlutterBluePlus.stopScan();

      return devices;
    } catch (e) {
      debugPrint('Error scanning for printers: $e');
      return devices;
    }
  }

  // Connect to printer
  static Future<bool> connect(BluetoothDevice device) async {
    try {
      // Disconnect from any existing connection
      await disconnect();

      // Connect to device
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedPrinter = device;

      // Discover services
      final services = await device.discoverServices();

      // Find write characteristic (usually in Serial Port service)
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
            _writeCharacteristic = characteristic;
            debugPrint('Found write characteristic: ${characteristic.uuid}');
            break;
          }
        }
        if (_writeCharacteristic != null) break;
      }

      if (_writeCharacteristic == null) {
        throw Exception('No write characteristic found on printer');
      }

      // Listen for disconnection
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint('Printer disconnected');
          _connectedPrinter = null;
          _writeCharacteristic = null;
        }
      });

      // Add to recently used printers
      await addToRecentPrinters(device);

      return true;
    } catch (e) {
      debugPrint('Error connecting to printer: $e');
      _connectedPrinter = null;
      _writeCharacteristic = null;
      return false;
    }
  }

  // Disconnect from printer
  static Future<void> disconnect() async {
    try {
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;

      if (_connectedPrinter != null) {
        await _connectedPrinter!.disconnect();
        _connectedPrinter = null;
        _writeCharacteristic = null;
      }
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  // Send raw bytes to printer
  static Future<void> _writeBytes(Uint8List bytes) async {
    if (_writeCharacteristic == null) {
      throw Exception('Not connected to printer');
    }

    try {
      // Split into chunks of 20 bytes (MTU limit)
      const chunkSize = 20;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);

        await _writeCharacteristic!.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 50)); // Small delay between chunks
      }
    } catch (e) {
      debugPrint('Error writing to printer: $e');
      rethrow;
    }
  }

  // Print test page
  static Future<void> printTest({PaperSize paperSize = PaperSize.mm58}) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    List<int> bytes = [];

    bytes += generator.text('BURSARY MANAGER',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.text('Test Print',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr();
    bytes += generator.text('Printer is working correctly!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Paper Size: ${paperSize == PaperSize.mm58 ? "58mm" : "80mm"}',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Date: ${DateTime.now()}',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }

  // Print bill receipt
  static Future<void> printBill({
    required String schoolName,
    required String schoolAddress,
    required String studentName,
    required String studentClass,
    required String term,
    required List<Map<String, dynamic>> feeItems,
    required double total,
    required String billDate,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    List<int> bytes = [];

    // Header
    bytes += generator.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));

    if (schoolAddress.isNotEmpty) {
      bytes += generator.text(schoolAddress,
          styles: const PosStyles(align: PosAlign.center));
    }

    bytes += _buildPhoneLine(generator, schoolPhone);
    bytes += generator.hr();

    // Title
    bytes += generator.text('FEE BILL',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    // Student info
    bytes += generator.text('Student: $studentName');
    bytes += generator.text('Class: $studentClass');
    bytes += generator.text('Term: $term');
    bytes += generator.text('Date: $billDate');
    bytes += generator.hr();

    // Fee items header
    bytes += generator.text('FEE BREAKDOWN',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr();

    // Column widths for 58mm paper (32 chars total)
    // Fee name: 8 columns, Amount: 4 columns (ratio 2:1)
    for (final item in feeItems) {
      final name = item['name'] ?? '';
      final amountValue = (item['amount'] as num?)?.toDouble() ?? 0.0;
      final amount = 'N ${_formatAmount(amountValue)}';

      bytes += generator.row([
        PosColumn(
          text: name,
          width: 7,
          styles: const PosStyles(align: PosAlign.left),
        ),
        PosColumn(
          text: amount,
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    bytes += generator.hr();

    // Total
    bytes += generator.text('TOTAL: N ${_formatAmount(total)}',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.hr();

    // Bank details
    bytes += _buildBankDetailsSection(generator, bankAccounts);

    // Footer
    bytes += generator.text('Thank you!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }

  // Print sibling bills summary
  // Each entry in [siblingItems] needs: 'name', 'className', 'totalBill', 'totalPaid', 'outstanding'
  static Future<void> printSiblingsBills({
    required String schoolName,
    required String schoolAddress,
    required String parentName,
    required int siblingCount,
    required String term,
    required List<Map<String, dynamic>> siblingItems,
    required double groupTotalBills,
    required double groupTotalPaid,
    required double groupTotalOutstanding,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    List<int> bytes = [];

    // Header
    bytes += generator.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      bytes += generator.text(schoolAddress,
          styles: const PosStyles(align: PosAlign.center));
    }
    bytes += _buildPhoneLine(generator, schoolPhone);
    bytes += generator.hr();

    // Title
    bytes += generator.text('SIBLING BILLS/PAYMENT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.hr();

    // Group info — compact, no blank lines
    bytes += generator.text('Name of Parent: $parentName',
        styles: const PosStyles(bold: true));
    bytes += generator.text('No. of Sibling: $siblingCount');
    bytes += generator.text('Term: $term');
    bytes += generator.hr();

    // Fee breakdown header
    bytes += generator.text('FEE BREAKDOWN',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr(ch: '-');

    // Each sibling row
    for (int i = 0; i < siblingItems.length; i++) {
      final s = siblingItems[i];
      final name = (s['name'] as String? ?? '').trim();
      final className = (s['className'] as String? ?? '').trim();
      final totalBill = (s['totalBill'] as num?)?.toDouble() ?? 0.0;
      final totalPaid = (s['totalPaid'] as num?)?.toDouble() ?? 0.0;
      final outstanding = (s['outstanding'] as num?)?.toDouble() ?? 0.0;

      // Student name + class on one line
      bytes += generator.text('$name  ($className)',
          styles: const PosStyles(bold: true));

      // Bill / Paid / Bal on one row — no decimal places, no fixed column caps
      bytes += generator.text(
        'Bill:N${_formatInt(totalBill)}  Paid:N${_formatInt(totalPaid)}  Bal:N${_formatInt(outstanding)}',
      );

      // Separator between siblings (not after last)
      if (i < siblingItems.length - 1) {
        bytes += generator.hr(ch: '-');
      }
    }

    bytes += generator.hr();

    // Summary — all lines centred
    bytes += generator.text('SUMMARY',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('Total Bills: N${_formatInt(groupTotalBills)}',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Total Paid: N${_formatInt(groupTotalPaid)}',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr(ch: '-');
    bytes += generator.text('Outstanding: N${_formatInt(groupTotalOutstanding)}',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr();

    // PAYMENT STATUS — prominent double-height centred line
    final bool isBalanced = groupTotalOutstanding <= 0;
    bytes += generator.text(
      isBalanced ? '** BALANCED **' : '** YET TO BALANCE **',
      styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.hr();

    // Bank details
    bytes += _buildBankDetailsSection(generator, bankAccounts);

    // Footer
    bytes += generator.text('Thank you!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }

  // Print payment receipt
  static Future<void> printPaymentReceipt({
    required String schoolName,
    required String schoolAddress,
    required String studentName,
    required String studentClass,
    required String receiptNo,
    required double amountPaid,
    required String paymentDate,
    required String paymentMethod,
    String? reference,
    String? paymentFor,
    double? totalBills,
    double? totalPaid,
    double? outstanding,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    List<int> bytes = [];

    // Header
    bytes += generator.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));

    if (schoolAddress.isNotEmpty) {
      bytes += generator.text(schoolAddress,
          styles: const PosStyles(align: PosAlign.center));
    }

    bytes += _buildPhoneLine(generator, schoolPhone);
    bytes += generator.hr();

    // Title
    bytes += generator.text('PAYMENT RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    // Receipt info
    bytes += generator.text('Receipt No: $receiptNo',
        styles: const PosStyles(bold: true));
    bytes += generator.text('Student: $studentName');
    bytes += generator.text('Class: $studentClass');

    // Date and time on the same line
    try {
      final parsed = DateTime.tryParse(paymentDate);
      if (parsed != null) {
        final dateOnly = DateFormat('dd/MM/yyyy').format(parsed);
        final timeOnly = DateFormat('HH:mm').format(parsed);
        bytes += generator.text('Date/Time: $dateOnly  $timeOnly',
            styles: const PosStyles(bold: true));
      } else {
        bytes += generator.text('Date: $paymentDate');
      }
    } catch (_) {
      bytes += generator.text('Date: $paymentDate');
    }

    bytes += generator.text('Method: $paymentMethod');

    if (paymentFor != null && paymentFor.isNotEmpty) {
      bytes += generator.text('Payment For: $paymentFor');
    }

    if (reference != null && reference.isNotEmpty) {
      bytes += generator.text('Reference: $reference');
    }

    bytes += generator.hr();

    // Amount — size2 x size2, no extra blank lines around it
    bytes += generator.text('AMOUNT PAID',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('N ${_formatAmount(amountPaid)}',
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ));
    bytes += generator.hr();

    // Financial Summary (if provided)
    if (totalBills != null || totalPaid != null || outstanding != null) {
      bytes += generator.text('ACCOUNT SUMMARY',
          styles: const PosStyles(align: PosAlign.center, bold: true));

      if (totalBills != null) {
        bytes += generator.text('Total Bills : N ${_formatAmount(totalBills)}');
      }
      if (totalPaid != null) {
        bytes += generator.text('Total Paid  : N ${_formatAmount(totalPaid)}');
      }
      if (outstanding != null) {
        bytes += generator.text('Outstanding : N ${_formatAmount(outstanding)}',
            styles: const PosStyles(bold: true));
      }

      // Payment status — bold and prominent, no extra blank lines
      if (outstanding != null) {
        final isBalanced = outstanding <= 0;
        bytes += generator.hr(ch: '-');
        bytes += generator.text(
          isBalanced ? 'BALANCED' : 'YET TO BALANCE',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        );
      }

      bytes += generator.hr();
    }

    // Bank details
    bytes += _buildBankDetailsSection(generator, bankAccounts);

    // Footer
    bytes += generator.text('Thank you for your payment!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }

  static Future<void> printFamilyPaymentReceipt({
    required String schoolName,
    required String schoolAddress,
    required String parentName,
    required String parentPhone,
    required String term,
    required String session,
    required String method,
    required String date,
    required String note,
    required List<Map<String, dynamic>> paymentItems,
    required double totalAmount,
    String? schoolPhone,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    bytes += generator.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      bytes += generator.text(schoolAddress,
          styles: const PosStyles(align: PosAlign.center));
    }
    bytes += _buildPhoneLine(generator, schoolPhone);
    bytes += generator.hr();

    bytes += generator.text('FAMILY PAYMENT RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    bytes += generator.text('Parent: $parentName', styles: const PosStyles(bold: true));
    if (parentPhone.isNotEmpty) {
      bytes += generator.text('Phone : $parentPhone');
    }
    bytes += generator.text('Term  : $term  $session');
    bytes += generator.text('Date  : $date');
    bytes += generator.text('Method: $method');
    if (note.isNotEmpty) {
      bytes += generator.text('Note  : $note');
    }
    bytes += generator.hr();

    // Total amount paid — shown prominently before the split
    bytes += generator.text('AMOUNT PAID',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('N ${_formatAmount(totalAmount)}',
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ));
    bytes += generator.hr();

    bytes += generator.text('PAYMENT SPLIT',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.emptyLines(1);

    final splitNameChars = (_charsPerLine(paperSize) * 7 / 12).floor();
    for (final item in paymentItems) {
      final name = item['name']?.toString() ?? '';
      final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
      bytes += generator.row([
        PosColumn(
          text: _fitToWidth(name, splitNameChars),
          width: 7,
          styles: const PosStyles(align: PosAlign.left),
        ),
        PosColumn(
          text: 'N ${_formatAmount(amount)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
    }

    bytes += generator.hr();

    // Account summary per sibling (if financial data was provided)
    final hasAccountData = paymentItems.isNotEmpty &&
        paymentItems.first.containsKey('totalBill');
    if (hasAccountData) {
      bytes += generator.text('ACCOUNT SUMMARY',
          styles: const PosStyles(align: PosAlign.center, bold: true));

      for (final item in paymentItems) {
        final name = item['name']?.toString() ?? '';
        final className = item['className']?.toString() ?? '';
        final totalBill = (item['totalBill'] as num?)?.toDouble() ?? 0.0;
        final totalPaid = (item['totalPaid'] as num?)?.toDouble() ?? 0.0;
        final outstanding = (item['outstanding'] as num?)?.toDouble() ?? 0.0;
        final isBalanced = outstanding <= 0;

        bytes += generator.hr(ch: '-');
        final label = className.isNotEmpty ? '$name  ($className)' : name;
        bytes += generator.text(label,
            styles: const PosStyles(bold: true));
        bytes += generator.text('Total Bills : N ${_formatAmount(totalBill)}');
        bytes += generator.text('Total Paid  : N ${_formatAmount(totalPaid)}');
        bytes += generator.text(
          'Outstanding : N ${_formatAmount(outstanding)}',
          styles: const PosStyles(bold: true),
        );
        bytes += generator.text(
          isBalanced ? 'BALANCED' : 'YET TO BALANCE',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        );
      }
      bytes += generator.hr();

      // Family summary totals
      final familyTotalBills = paymentItems.fold(
          0.0, (sum, i) => sum + ((i['totalBill'] as num?)?.toDouble() ?? 0.0));
      final familyTotalPaid = paymentItems.fold(
          0.0, (sum, i) => sum + ((i['totalPaid'] as num?)?.toDouble() ?? 0.0));
      final familyOutstanding = paymentItems.fold(
          0.0, (sum, i) => sum + ((i['outstanding'] as num?)?.toDouble() ?? 0.0));
      final familyBalanced = familyOutstanding <= 0;

      bytes += generator.text('FAMILY SUMMARY',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('Total Bills : N ${_formatAmount(familyTotalBills)}');
      bytes += generator.text('Total Paid  : N ${_formatAmount(familyTotalPaid)}');
      bytes += generator.text(
        'Outstanding : N ${_formatAmount(familyOutstanding)}',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.hr(ch: '-');
      bytes += generator.text(
        familyBalanced ? '** BALANCED **' : '** YET TO BALANCE **',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.hr();
    }

    bytes += generator.text('Thank you for your payment!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }

  // Print sales receipt
  static Future<void> printSalesReceipt({
    required String schoolName,
    required String schoolAddress,
    required String buyerName,
    required String buyerType,
    required String itemName,
    required int quantity,
    required double unitPrice,
    required double totalAmount,
    required String paymentMethod,
    required String paymentStatus,
    required String saleDate,
    required String receiptNo,
    String? note,
    double? amountPaid,
    double? outstandingBalance,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    List<int> bytes = [];

    // Header
    bytes += generator.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));

    if (schoolAddress.isNotEmpty) {
      bytes += generator.text(schoolAddress,
          styles: const PosStyles(align: PosAlign.center));
    }

    bytes += _buildPhoneLine(generator, schoolPhone);
    bytes += generator.hr();

    // Title
    bytes += generator.text('SALES RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    // Receipt info
    bytes += generator.text('Receipt No: $receiptNo',
        styles: const PosStyles(bold: true));
    bytes += generator.text('Buyer: $buyerName');
    bytes += generator.text('Type: $buyerType');
    bytes += generator.text('Date: $saleDate');
    bytes += generator.hr();

    // Item details
    bytes += generator.text('ITEM DETAILS',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.emptyLines(1);
    bytes += generator.text('Item: $itemName');
    bytes += generator.text('Quantity: $quantity');
    bytes += generator.text('Unit Price: N ${_formatAmount(unitPrice)}');

    if (note != null && note.isNotEmpty) {
      bytes += generator.text('Note: $note');
    }

    bytes += generator.hr();

    // Total amount
    bytes += generator.text('TOTAL AMOUNT',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('N ${_formatAmount(totalAmount)}',
        styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size3, bold: true));
    bytes += generator.hr();

    // Payment details
    bytes += generator.text('PAYMENT DETAILS',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.emptyLines(1);
    bytes += generator.text('Method: $paymentMethod');
    bytes += generator.text('Status: $paymentStatus',
        styles: const PosStyles(bold: true));

    // Credit/Part payment details
    if (paymentStatus != 'Paid') {
      if (amountPaid != null) {
        bytes += generator.text('Amount Paid: N ${_formatAmount(amountPaid)}');
      }
      if (outstandingBalance != null && outstandingBalance > 0) {
        bytes += generator.text('Outstanding: N ${_formatAmount(outstandingBalance)}',
            styles: const PosStyles(bold: true, height: PosTextSize.size2));
      }
    }

    bytes += generator.hr();

    // Bank details
    bytes += _buildBankDetailsSection(generator, bankAccounts);

    // Footer
    bytes += generator.text('Thank you for your purchase!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }

  // Print multi-item sales receipt
  static Future<void> printMultiItemSalesReceipt({
    required String schoolName,
    required String schoolAddress,
    required String buyerName,
    required String buyerType,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required double amountPaid,
    required double outstandingBalance,
    required String paymentMethod,
    required String paymentStatus,
    required String saleDate,
    required String receiptNo,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    List<int> bytes = [];

    // Header
    bytes += generator.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));

    if (schoolAddress.isNotEmpty) {
      bytes += generator.text(schoolAddress,
          styles: const PosStyles(align: PosAlign.center));
    }

    bytes += _buildPhoneLine(generator, schoolPhone);
    bytes += generator.hr();

    // Title
    bytes += generator.text('SALES RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    // Receipt info
    bytes += generator.text('Receipt No: $receiptNo',
        styles: const PosStyles(bold: true));
    bytes += generator.text('Buyer: $buyerName');
    bytes += generator.text('Type: $buyerType');
    bytes += generator.text('Date: $saleDate');
    bytes += generator.hr();

    // Items purchased
    bytes += generator.text('ITEMS PURCHASED (${items.length})',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.emptyLines(1);

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final itemName = item['itemName'] as String;
      final quantity = item['quantity'] as int;
      final unitPrice = (item['unitPrice'] as num).toDouble();
      final itemTotal = (item['totalAmount'] as num).toDouble();

      bytes += generator.text('${i + 1}. $itemName',
          styles: const PosStyles(bold: true));
      bytes += generator.text('   Qty: $quantity x N ${_formatAmount(unitPrice)}');
      bytes += generator.text('   Total: N ${_formatAmount(itemTotal)}',
          styles: const PosStyles(align: PosAlign.right));

      if (i < items.length - 1) {
        bytes += generator.emptyLines(1);
      }
    }

    bytes += generator.hr();

    // Payment summary
    bytes += generator.text('PAYMENT SUMMARY',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.emptyLines(1);
    bytes += generator.text('Total Amount: N ${_formatAmount(totalAmount)}',
        styles: const PosStyles(bold: true));
    bytes += generator.text('Amount Paid: N ${_formatAmount(amountPaid)}');

    if (outstandingBalance > 0) {
      bytes += generator.text('Outstanding: N ${_formatAmount(outstandingBalance)}',
          styles: const PosStyles(bold: true, height: PosTextSize.size2));
    }

    bytes += generator.hr();

    // Payment details
    bytes += generator.text('Method: $paymentMethod');
    bytes += generator.text('Status: $paymentStatus',
        styles: const PosStyles(bold: true));

    bytes += generator.hr();

    // Bank details
    bytes += _buildBankDetailsSection(generator, bankAccounts);

    // Footer
    bytes += generator.text('Thank you for your purchase!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }

  // Print new intake bill
  static Future<void> printNewIntakeBill({
    required String schoolName,
    required String schoolAddress,
    required String className,
    String? armName,
    required String term,
    required String session,
    required List<Map<String, dynamic>> regularFees,
    required List<Map<String, dynamic>> groupedCategories,
    required List<Map<String, dynamic>> standaloneItems,
    required double grandTotal,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm58,
    String title = 'NEW INTAKE BILL',
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    List<int> bytes = [];

    // Header
    bytes += generator.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));

    if (schoolAddress.isNotEmpty) {
      bytes += generator.text(schoolAddress,
          styles: const PosStyles(align: PosAlign.center));
    }

    bytes += _buildPhoneLine(generator, schoolPhone);
    bytes += generator.hr();

    // Title
    bytes += generator.text(title,
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    // Class info
    final classLabel = armName != null ? '$className - $armName' : className;
    bytes += generator.text('Class: $classLabel',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('$term | $session',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr();

    int serialNumber = 0;

    // === REGISTRATION FEES (standalone items) - shown first ===
    if (standaloneItems.isNotEmpty) {
      bytes += generator.text('REGISTRATION FEES',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.hr(ch: '-');

      double sectionTotal = 0;
      for (var item in standaloneItems) {
        serialNumber++;
        final name = item['name'] ?? 'Unknown';
        final amountValue = (item['amount'] as num?)?.toDouble() ?? 0.0;
        sectionTotal += amountValue;

        bytes += generator.row([
          PosColumn(
            text: '$serialNumber. $name',
            width: 7,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: 'N ${_formatAmount(amountValue)}',
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      bytes += generator.row([
        PosColumn(
          text: 'Subtotal:',
          width: 7,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
        PosColumn(
          text: 'N ${_formatAmount(sectionTotal)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += generator.hr(ch: '-');
    }

    // === CURRENT TERM FEES section ===
    if (regularFees.isNotEmpty) {
      bytes += generator.text('CURRENT TERM FEES',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.hr(ch: '-');

      double sectionTotal = 0;
      for (var fee in regularFees) {
        serialNumber++;
        final name = fee['feeItemName'] ?? 'Unknown';
        final amountValue = (fee['amount'] as num?)?.toDouble() ?? 0.0;
        sectionTotal += amountValue;

        bytes += generator.row([
          PosColumn(
            text: '$serialNumber. $name',
            width: 7,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: 'N ${_formatAmount(amountValue)}',
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      bytes += generator.row([
        PosColumn(
          text: 'Subtotal:',
          width: 7,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
        PosColumn(
          text: 'N ${_formatAmount(sectionTotal)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += generator.hr(ch: '-');
    }

    // === CATEGORY sections ===
    for (var category in groupedCategories) {
      final categoryName = category['categoryName'] ?? 'Unknown';
      final items = category['items'] as List<Map<String, dynamic>>? ?? [];
      final categoryTotal = (category['categoryTotal'] as num?)?.toDouble() ?? 0;

      if (items.isEmpty) continue;

      bytes += generator.text(categoryName.toUpperCase(),
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.hr(ch: '-');

      for (var item in items) {
        serialNumber++;
        final name = item['name'] ?? 'Unknown';
        final amountValue = (item['amount'] as num?)?.toDouble() ?? 0.0;

        bytes += generator.row([
          PosColumn(
            text: '$serialNumber. $name',
            width: 7,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: 'N ${_formatAmount(amountValue)}',
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      bytes += generator.row([
        PosColumn(
          text: 'Subtotal:',
          width: 7,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
        PosColumn(
          text: 'N ${_formatAmount(categoryTotal)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += generator.hr(ch: '-');
    }

    bytes += generator.hr();

    // Grand Total
    bytes += generator.text('GRAND TOTAL',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('N ${_formatAmount(grandTotal)}',
        styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size3, bold: true));
    bytes += generator.hr();

    // Bank details
    bytes += _buildBankDetailsSection(generator, bankAccounts);

    // Footer
    bytes += generator.text('New Intake Bill',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }

  // Print payment history
  static Future<void> printPaymentHistory({
    required String schoolName,
    required String schoolAddress,
    required String studentName,
    required String studentClass,
    required List<Map<String, dynamic>> payments,
    required double totalPaid,
    double? totalBills,
    double? outstanding,
    String? schoolPhone,
    List<Map<String, dynamic>>? bankAccounts,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);

    List<int> bytes = [];

    // Header
    bytes += generator.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));

    if (schoolAddress.isNotEmpty) {
      bytes += generator.text(schoolAddress,
          styles: const PosStyles(align: PosAlign.center));
    }

    bytes += _buildPhoneLine(generator, schoolPhone);
    bytes += generator.hr();

    // Title
    bytes += generator.text('PAYMENT HISTORY',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    // Student info
    bytes += generator.text('Student: $studentName');
    bytes += generator.text('Class: $studentClass');
    bytes += generator.hr();

    // Payments
    bytes += generator.text('PAYMENTS',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr();

    for (final payment in payments) {
      final date = payment['date'] ?? '';
      final method = payment['method'] ?? '';
      final amount = 'N${_formatAmount((payment['amount'] as num?)?.toDouble() ?? 0.0)}';
      final paymentFor = payment['paymentFor']?.toString() ?? '';

      // All on one line: Date+Time | Method | Amount
      bytes += generator.row([
        PosColumn(text: date, width: 6, styles: const PosStyles(align: PosAlign.left)),
        PosColumn(text: method, width: 3, styles: const PosStyles(align: PosAlign.center)),
        PosColumn(text: amount, width: 3, styles: const PosStyles(align: PosAlign.right)),
      ]);
      if (paymentFor.isNotEmpty) {
        bytes += generator.text('  For: $paymentFor');
      }
    }

    bytes += generator.hr();

    // Summary
    bytes += generator.text('FINANCIAL SUMMARY',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.emptyLines(1);

    if (totalBills != null) {
      bytes += generator.text('Total Bills: N ${_formatAmount(totalBills)}');
    }
    bytes += generator.text('Total Paid: N ${_formatAmount(totalPaid)}');
    if (outstanding != null) {
      bytes += generator.text('Outstanding: N ${_formatAmount(outstanding)}',
          styles: const PosStyles(bold: true, align: PosAlign.center));
      bytes += generator.emptyLines(1);
      final isBalanced = outstanding <= 0;
      // Double width+height so characters scale proportionally (not compressed)
      bytes += generator.text(
        isBalanced ? '** BALANCED **' : '** YET TO BALANCE **',
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          align: PosAlign.center,
        ),
      );
      bytes += generator.text('- Payment Status -',
          styles: const PosStyles(align: PosAlign.center, bold: true));
    }
    bytes += generator.hr();

    // Bank details
    bytes += _buildBankDetailsSection(generator, bankAccounts);

    // Footer
    bytes += generator.text('Thank you!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }

  // siblingItems: list of { name, className, totalBill, totalPaid, outstanding, payments: [{date, method, amount}] }
  static Future<void> printFamilyPaymentHistory({
    required String schoolName,
    required String schoolAddress,
    required String parentName,
    required String parentPhone,
    required String term,
    required String session,
    required List<Map<String, dynamic>> siblingItems,
    required double groupTotalBills,
    required double groupTotalPaid,
    required double groupTotalOutstanding,
    String? schoolPhone,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    bytes += generator.text(schoolName.toUpperCase(),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (schoolAddress.isNotEmpty) {
      bytes += generator.text(schoolAddress,
          styles: const PosStyles(align: PosAlign.center));
    }
    bytes += _buildPhoneLine(generator, schoolPhone);
    bytes += generator.hr();

    bytes += generator.text('FAMILY PAYMENT HISTORY',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    bytes += generator.text('Parent: $parentName', styles: const PosStyles(bold: true));
    if (parentPhone.isNotEmpty) {
      bytes += generator.text('Phone : $parentPhone');
    }
    bytes += generator.text('Term  : $term  $session');
    bytes += generator.hr();

    for (final sibling in siblingItems) {
      final name = sibling['name']?.toString() ?? '';
      final className = sibling['className']?.toString() ?? '';
      final totalBill = (sibling['totalBill'] as num?)?.toDouble() ?? 0.0;
      final totalPaid = (sibling['totalPaid'] as num?)?.toDouble() ?? 0.0;
      final outstanding = (sibling['outstanding'] as num?)?.toDouble() ?? 0.0;
      final payments = sibling['payments'] as List? ?? [];

      bytes += generator.text(name, styles: const PosStyles(bold: true));
      if (className.isNotEmpty) {
        bytes += generator.text(className);
      }
      bytes += generator.hr(ch: '-');

      if (payments.isEmpty) {
        bytes += generator.text('No payments this term',
            styles: const PosStyles(align: PosAlign.center));
      } else {
        for (final p in payments) {
          final date = p['date']?.toString() ?? '';
          final method = p['method']?.toString() ?? '';
          final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          bytes += generator.row([
            PosColumn(text: date, width: 6, styles: const PosStyles(align: PosAlign.left)),
            PosColumn(text: method, width: 3, styles: const PosStyles(align: PosAlign.center)),
            PosColumn(
              text: 'N${_formatAmount(amt)}',
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
      }

      bytes += generator.row([
        PosColumn(text: 'Bill:', width: 4),
        PosColumn(text: 'N${_formatAmount(totalBill)}', width: 4, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(text: '', width: 4),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Paid:', width: 4),
        PosColumn(text: 'N${_formatAmount(totalPaid)}', width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
        PosColumn(
          text: outstanding > 0 ? 'OWING' : 'OK',
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += generator.hr();
    }

    bytes += generator.text('FAMILY TOTALS',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('Total Bills  : N ${_formatAmount(groupTotalBills)}');
    bytes += generator.text('Total Paid   : N ${_formatAmount(groupTotalPaid)}',
        styles: const PosStyles(bold: true));
    bytes += generator.text('Outstanding  : N ${_formatAmount(groupTotalOutstanding)}',
        styles: const PosStyles(bold: true));
    bytes += generator.hr(ch: '-');
    bytes += generator.text(
      groupTotalOutstanding <= 0 ? '** BALANCED **' : '** YET TO BALANCE **',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.hr();
    bytes += generator.text('Thank you!',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.cut();

    await _writeBytes(Uint8List.fromList(bytes));
  }
}
