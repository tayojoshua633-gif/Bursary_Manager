import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import '../../utils/usb_printer_manager.dart';

class UsbPrinterScreen extends StatefulWidget {
  const UsbPrinterScreen({super.key});

  @override
  State<UsbPrinterScreen> createState() => _UsbPrinterScreenState();
}

class _UsbPrinterScreenState extends State<UsbPrinterScreen> {
  List<Map<String, dynamic>> _devices = [];
  bool _scanning = false;
  bool _connecting = false;
  bool _testPrinting = false;
  String _paperSize = 'mm80';
  Map<String, dynamic>? _connected;

  @override
  void initState() {
    super.initState();
    _connected = UsbPrinterManager.connectedDevice;
    _loadPrefs();
    _scan();
  }

  Future<void> _loadPrefs() async {
    final size = await UsbPrinterManager.getPaperSize();
    setState(() => _paperSize = size);
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _devices = [];
    });
    final devices = await UsbPrinterManager.getDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _scanning = false;
      });
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No USB devices found. Make sure the printer is connected via OTG cable.'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _connect(Map<String, dynamic> device) async {
    setState(() => _connecting = true);
    final ok = await UsbPrinterManager.connect(device);
    if (mounted) {
      setState(() {
        _connecting = false;
        _connected = UsbPrinterManager.connectedDevice;
      });
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Permission requested — tap "Allow" in the Android dialog, then you\'re ready to print.',
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device not found. Unplug and re-plug the OTG cable, then refresh.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    await UsbPrinterManager.disconnect();
    if (mounted) setState(() => _connected = null);
  }

  Future<void> _setPaperSize(String size) async {
    await UsbPrinterManager.setPaperSize(size);
    setState(() => _paperSize = size);
  }

  Future<void> _testPrint() async {
    if (!UsbPrinterManager.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to a printer first'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _testPrinting = true);
    try {
      await UsbPrinterManager.printTest(
        paperSize: _paperSize == 'mm58' ? PaperSize.mm58 : PaperSize.mm80,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test page sent!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _testPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('USB Printer'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _scanning ? null : _scan,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Info banner ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.deepPurple.shade100),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.deepPurple.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Connect your thermal printer to the phone using a USB OTG cable. '
                    'When prompted by Android, tap "Allow" to grant access.',
                    style: TextStyle(fontSize: 13, color: Colors.deepPurple.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Connected printer ─────────────────────────────────────────────
          if (_connected != null) ...[
            _sectionLabel('Connected Printer', Icons.usb, Colors.green),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.print, color: Colors.green.shade700),
                ),
                title: Text(
                  _connected!['productName']?.toString() ?? 'USB Printer',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Vendor: ${_connected!['vendorId']}  ·  Product: ${_connected!['productId']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: TextButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text('Disconnect'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Paper size ────────────────────────────────────────────────────
          _sectionLabel('Paper Size', Icons.straighten, Colors.indigo),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _paperSizeTile('58mm', 'mm58', 'Narrow thermal paper'),
                const Divider(height: 1),
                _paperSizeTile('80mm', 'mm80', 'Standard thermal paper (Recommended)'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Detected devices ──────────────────────────────────────────────
          _sectionLabel(
            _scanning ? 'Scanning for USB devices…' : 'Detected USB Devices (${_devices.length})',
            Icons.usb,
            Colors.deepPurple,
          ),
          const SizedBox(height: 8),

          if (_scanning)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (_devices.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.usb_off, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'No USB devices detected',
                    style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Plug in your printer and tap Refresh',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          else
            ...(_connecting
                ? [const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))]
                : _devices.map((d) => _deviceCard(d))),

          const SizedBox(height: 24),

          // ── Test print ────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_connected == null || _testPrinting) ? null : _testPrint,
              icon: _testPrinting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.print),
              label: Text(_testPrinting ? 'Printing…' : 'Print Test Page'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon, Color color) {
    return Row(
      children: [
        Container(width: 3, height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
      ],
    );
  }

  Widget _paperSizeTile(String label, String value, String subtitle) {
    final selected = _paperSize == value;
    return RadioListTile<String>(
      value: value,
      groupValue: _paperSize,
      onChanged: (v) => _setPaperSize(v!),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      activeColor: Colors.indigo,
      selected: selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _deviceCard(Map<String, dynamic> device) {
    final isConnected = _connected != null &&
        _connected!['vendorId']?.toString() == device['vendorId']?.toString() &&
        _connected!['productId']?.toString() == device['productId']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isConnected ? Colors.green.shade50 : Colors.deepPurple.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.usb,
            color: isConnected ? Colors.green.shade700 : Colors.deepPurple.shade700,
          ),
        ),
        title: Text(
          device['productName']?.toString().isNotEmpty == true
              ? device['productName'].toString()
              : 'USB Thermal Printer',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${device['manufacturerName'] ?? 'Unknown'} · VID:${device['vendorId']} PID:${device['productId']}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        trailing: isConnected
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Connected',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
              )
            : ElevatedButton(
                onPressed: () => _connect(device),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Connect', style: TextStyle(fontSize: 13)),
              ),
      ),
    );
  }
}
