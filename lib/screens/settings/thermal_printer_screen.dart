import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../utils/thermal_printer_manager.dart';

class ThermalPrinterScreen extends StatefulWidget {
  const ThermalPrinterScreen({super.key});

  @override
  State<ThermalPrinterScreen> createState() => _ThermalPrinterScreenState();
}

class _ThermalPrinterScreenState extends State<ThermalPrinterScreen> {
  List<ScanResult> _scanResults = [];
  List<Map<String, String>> _recentPrinters = [];
  Map<String, String>? _defaultPrinter;
  Map<String, String> _printerPaperSizes = {}; // remoteId -> 'mm58' or 'mm80'
  bool _isScanning = false;
  bool _isConnecting = false;
  BluetoothDevice? _connectedPrinter;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _loadRecentAndDefault();
  }

  void _checkConnection() {
    setState(() {
      _connectedPrinter = ThermalPrinterManager.connectedPrinter;
    });
  }

  Future<void> _loadRecentAndDefault() async {
    final recent = await ThermalPrinterManager.getRecentPrinters();
    final defaultPrinter = await ThermalPrinterManager.getDefaultPrinter();

    // Load paper sizes for all recent printers
    final paperSizes = <String, String>{};
    for (var printer in recent) {
      final remoteId = printer['remoteId'] ?? '';
      if (remoteId.isNotEmpty) {
        paperSizes[remoteId] = await ThermalPrinterManager.getPrinterPaperSize(remoteId);
      }
    }

    setState(() {
      _recentPrinters = recent;
      _defaultPrinter = defaultPrinter;
      _printerPaperSizes = paperSizes;
    });
  }

  Future<void> _scanForPrinters() async {
    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    try {
      // Request Bluetooth permissions
      final permissionsGranted = await ThermalPrinterManager.requestBluetoothPermissions();
      if (!permissionsGranted) {
        setState(() => _isScanning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth permissions are required to scan for devices. Please grant permissions in Settings.'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Check if Bluetooth is on
      final bluetoothOn = await ThermalPrinterManager.isBluetoothOn();
      if (!bluetoothOn) {
        setState(() => _isScanning = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please turn on Bluetooth to scan for devices.'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }

        // Try to turn on Bluetooth
        try {
          await ThermalPrinterManager.requestBluetoothOn();
          await Future.delayed(const Duration(seconds: 1));
        } catch (e) {
          debugPrint('Could not turn on Bluetooth automatically: $e');
        }
        return;
      }

      final results = await ThermalPrinterManager.scanForPrinters();
      setState(() {
        _scanResults = results;
        _isScanning = false;
      });

      if (results.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Bluetooth devices found. Make sure your printer is turned on and in pairing mode.'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _connectToPrinter(BluetoothDevice device) async {
    setState(() => _isConnecting = true);

    try {
      final success = await ThermalPrinterManager.connect(device);

      setState(() {
        _isConnecting = false;
        if (success) {
          _connectedPrinter = device;
        }
      });

      // Reload recent printers
      await _loadRecentAndDefault();

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to ${device.platformName}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to printer'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _connectToRecentPrinter(Map<String, String> printerInfo) async {
    setState(() => _isConnecting = true);

    try {
      // Scan for the device
      final results = await ThermalPrinterManager.scanForPrinters(timeout: const Duration(seconds: 5));

      final matchingDevice = results.where((r) =>
        r.device.remoteId.toString() == printerInfo['remoteId']
      ).firstOrNull;

      if (matchingDevice == null) {
        setState(() => _isConnecting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${printerInfo['name']} not found. Make sure it is turned on.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await _connectToPrinter(matchingDevice.device);
    } catch (e) {
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    await ThermalPrinterManager.disconnect();
    setState(() => _connectedPrinter = null);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected from printer'),
          backgroundColor: Colors.grey,
        ),
      );
    }
  }

  Future<void> _setAsDefault(BluetoothDevice device) async {
    await ThermalPrinterManager.setDefaultPrinter(device);
    await _loadRecentAndDefault();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${device.platformName} set as default printer'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _clearDefault() async {
    await ThermalPrinterManager.clearDefaultPrinter();
    await _loadRecentAndDefault();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default printer cleared'),
          backgroundColor: Colors.grey,
        ),
      );
    }
  }

  // Show options bottom sheet for saved printer
  void _showPrinterOptions(Map<String, String> printer) {
    final remoteId = printer['remoteId'] ?? '';
    final printerName = printer['name'] ?? 'Unknown';
    final isDefault = _defaultPrinter?['remoteId'] == remoteId;
    final currentPaperSize = _printerPaperSizes[remoteId] ?? 'mm58';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Printer name header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.print, size: 28, color: Colors.indigo),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            printerName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Paper: ${currentPaperSize == 'mm80' ? '80mm' : '58mm'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 14, color: Colors.amber),
                            SizedBox(width: 4),
                            Text('Default', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const Divider(),

              // Option: Connect
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.bluetooth_connected, color: Colors.green.shade700),
                ),
                title: const Text('Connect to Printer'),
                subtitle: const Text('Establish connection to print'),
                onTap: () {
                  Navigator.pop(context);
                  _connectToRecentPrinter(printer);
                },
              ),

              // Option: Set as Default
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isDefault ? Icons.star : Icons.star_outline,
                    color: Colors.amber.shade700,
                  ),
                ),
                title: Text(isDefault ? 'Remove as Default' : 'Set as Default Printer'),
                subtitle: Text(isDefault
                    ? 'Clear this printer as default'
                    : 'Auto-connect to this printer'),
                onTap: () async {
                  Navigator.pop(context);
                  if (isDefault) {
                    await _clearDefault();
                  } else {
                    await _setDefaultFromSaved(printer);
                  }
                },
              ),

              // Option: Paper Size
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.straighten, color: Colors.blue.shade700),
                ),
                title: const Text('Paper Size'),
                subtitle: Text('Currently: ${currentPaperSize == 'mm80' ? '80mm' : '58mm'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _showPaperSizeDialog(printer);
                },
              ),

              // Option: Remove Printer
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.delete_outline, color: Colors.red.shade700),
                ),
                title: const Text('Remove Printer'),
                subtitle: const Text('Remove from saved printers'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmRemovePrinter(printer);
                },
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // Set default from saved printer info
  Future<void> _setDefaultFromSaved(Map<String, String> printer) async {
    final name = printer['name'] ?? 'Unknown';

    await ThermalPrinterManager.setDefaultPrinterFromInfo(printer);
    await _loadRecentAndDefault();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name set as default printer'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Show paper size selection dialog
  void _showPaperSizeDialog(Map<String, String> printer) {
    final remoteId = printer['remoteId'] ?? '';
    final currentSize = _printerPaperSizes[remoteId] ?? 'mm58';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.straighten, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            const Text('Select Paper Size'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 58mm option
            ListTile(
              leading: Icon(
                currentSize == 'mm58' ? Icons.radio_button_checked : Icons.radio_button_off,
                color: Colors.indigo,
              ),
              title: const Text('58mm (2.25 inch)'),
              subtitle: const Text('Standard small thermal paper'),
              onTap: () async {
                Navigator.pop(context);
                await _setPaperSize(printer, 'mm58');
              },
            ),
            // 80mm option
            ListTile(
              leading: Icon(
                currentSize == 'mm80' ? Icons.radio_button_checked : Icons.radio_button_off,
                color: Colors.indigo,
              ),
              title: const Text('80mm (3.15 inch)'),
              subtitle: const Text('Wide thermal paper'),
              onTap: () async {
                Navigator.pop(context);
                await _setPaperSize(printer, 'mm80');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // Set paper size for printer
  Future<void> _setPaperSize(Map<String, String> printer, String size) async {
    final remoteId = printer['remoteId'] ?? '';
    await ThermalPrinterManager.setPrinterPaperSize(remoteId, size);
    await _loadRecentAndDefault();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Paper size set to ${size == 'mm80' ? '80mm' : '58mm'}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Confirm and remove printer
  void _confirmRemovePrinter(Map<String, String> printer) {
    final name = printer['name'] ?? 'Unknown';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Printer?'),
        content: Text(
          'Are you sure you want to remove "$name" from your saved printers?\n\n'
          'This will also remove any saved settings for this printer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _removePrinter(printer);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // Remove printer from saved list
  Future<void> _removePrinter(Map<String, String> printer) async {
    final remoteId = printer['remoteId'] ?? '';
    final name = printer['name'] ?? 'Unknown';

    await ThermalPrinterManager.removeFromRecentPrinters(remoteId);
    await _loadRecentAndDefault();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name removed from saved printers'),
          backgroundColor: Colors.grey,
        ),
      );
    }
  }

  Future<void> _testPrint() async {
    try {
      await ThermalPrinterManager.printTest();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test print sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thermal Printer'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _scanForPrinters,
            tooltip: 'Scan for Printers',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Status Card
            if (_connectedPrinter != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        const Text(
                          'Connected',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        if (_defaultPrinter?['remoteId'] == _connectedPrinter!.remoteId.toString())
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 14, color: Colors.amber),
                                SizedBox(width: 4),
                                Text('Default', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _connectedPrinter!.platformName,
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      _connectedPrinter!.remoteId.toString(),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    // Paper size info
                    Builder(
                      builder: (context) {
                        final remoteId = _connectedPrinter!.remoteId.toString();
                        final paperSize = _printerPaperSizes[remoteId] ?? 'mm58';
                        return Text(
                          'Paper Size: ${paperSize == 'mm80' ? '80mm' : '58mm'}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _testPrint,
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('Test Print'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showPaperSizeDialog({
                            'remoteId': _connectedPrinter!.remoteId.toString(),
                            'name': _connectedPrinter!.platformName,
                          }),
                          icon: const Icon(Icons.straighten, size: 18),
                          label: const Text('Paper Size'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue.shade700,
                          ),
                        ),
                        if (_defaultPrinter?['remoteId'] != _connectedPrinter!.remoteId.toString())
                          OutlinedButton.icon(
                            onPressed: () => _setAsDefault(_connectedPrinter!),
                            icon: const Icon(Icons.star_outline, size: 18),
                            label: const Text('Set Default'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.amber.shade700,
                            ),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _clearDefault,
                            icon: const Icon(Icons.star_border, size: 18),
                            label: const Text('Clear Default'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey,
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: _disconnect,
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Disconnect'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Default Printer Card (when not connected)
            if (_connectedPrinter == null && _defaultPrinter != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Card(
                  color: Colors.amber.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.star, color: Colors.amber),
                    title: Text(
                      _defaultPrinter!['name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Paper: ${_printerPaperSizes[_defaultPrinter!['remoteId']] == 'mm80' ? '80mm' : '58mm'} • Tap for options',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showPrinterOptions(_defaultPrinter!),
                    ),
                    onTap: _isConnecting ? null : () => _connectToRecentPrinter(_defaultPrinter!),
                  ),
                ),
              ),

            // Recently Used Printers
            if (_recentPrinters.isNotEmpty && _connectedPrinter == null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    const Text(
                      'Recently Used',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentPrinters.length,
                itemBuilder: (context, index) {
                  final printer = _recentPrinters[index];
                  final remoteId = printer['remoteId'] ?? '';
                  final isDefault = _defaultPrinter?['remoteId'] == remoteId;
                  final paperSize = _printerPaperSizes[remoteId] ?? 'mm58';

                  // Skip if this is the default printer (already shown above)
                  if (isDefault) return const SizedBox.shrink();

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.print, color: Colors.grey),
                      title: Text(printer['name'] ?? 'Unknown'),
                      subtitle: Text(
                        'Paper: ${paperSize == 'mm80' ? '80mm' : '58mm'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _showPrinterOptions(printer),
                            tooltip: 'More options',
                          ),
                          if (_isConnecting)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            ElevatedButton(
                              onPressed: () => _connectToRecentPrinter(printer),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Connect'),
                            ),
                        ],
                      ),
                      onTap: () => _showPrinterOptions(printer),
                    ),
                  );
                },
              ),
            ],

            // Instructions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Bluetooth Thermal Printers',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _connectedPrinter == null
                        ? 'Tap Refresh to scan for available printers'
                        : 'Your printer is ready to use!',
                    style: TextStyle(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  if (_scanResults.isEmpty && !_isScanning && _connectedPrinter == null && _recentPrinters.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ElevatedButton.icon(
                        onPressed: _scanForPrinters,
                        icon: const Icon(Icons.search),
                        label: const Text('Scan for Printers'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Loading Indicator
            if (_isScanning)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Scanning for printers...'),
                  ],
                ),
              ),

            // Scanned Device List
            if (!_isScanning && _scanResults.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.bluetooth, size: 20, color: Colors.indigo.shade700),
                    const SizedBox(width: 8),
                    const Text(
                      'Available Devices',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _scanResults.length,
                itemBuilder: (context, index) {
                  final result = _scanResults[index];
                  final device = result.device;
                  final isConnected = _connectedPrinter?.remoteId == device.remoteId;
                  final isDefault = _defaultPrinter?['remoteId'] == device.remoteId.toString();
                  final deviceName = device.platformName.isNotEmpty
                      ? device.platformName
                      : 'Unknown Device';

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: Icon(
                        Icons.print,
                        color: isConnected ? Colors.green : Colors.grey,
                        size: 32,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              deviceName,
                              style: TextStyle(
                                fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star, size: 12, color: Colors.amber),
                                  SizedBox(width: 2),
                                  Text('Default', style: TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(device.remoteId.toString()),
                          if (result.rssi != 0)
                            Text('Signal: ${result.rssi} dBm',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      trailing: isConnected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : _isConnecting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : ElevatedButton(
                                  onPressed: () => _connectToPrinter(device),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Connect'),
                                ),
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
