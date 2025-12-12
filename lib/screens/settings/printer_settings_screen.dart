// lib/screens/settings/printer_settings_screen.dart

import 'package:flutter/material.dart';
import '../../utils/printer_settings_helper.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  PrinterSize _currentSize = PrinterSettingsHelper.size80mm;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    _currentSize = await PrinterSettingsHelper.getCurrentSize();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _changePaperSize(PrinterSize newSize) async {
    await PrinterSettingsHelper.setCurrentSize(newSize);
    setState(() => _currentSize = newSize);
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Paper size changed to ${newSize.name}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Printer Settings'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Settings'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current Setting Card
          Card(
            elevation: 3,
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.print,
                    size: 64,
                    color: Colors.indigo.shade700,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Current Paper Size',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentSize.name,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    PrinterSettingsHelper.getSizeDescription(_currentSize.name),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Select Paper Size',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose the size that matches your thermal printer',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey,
            ),
          ),

          const SizedBox(height: 16),

          // Paper Size Options
          ...PrinterSettingsHelper.availableSizes.map((size) {
            final isSelected = size.name == _currentSize.name;
            
            return Card(
              elevation: isSelected ? 3 : 1,
              color: isSelected ? Colors.indigo.shade50 : null,
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => _changePaperSize(size),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.indigo.shade100
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.receipt_long,
                          color: isSelected
                              ? Colors.indigo.shade700
                              : Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  size.name,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.indigo.shade700
                                        : Colors.black,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'ACTIVE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              PrinterSettingsHelper.getSizeDescription(size.name),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Technical specs
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                _buildSpec('Width', '${size.widthMm}mm'),
                                _buildSpec('Font', '${size.fontSize}pt'),
                                _buildSpec('Margin', '${size.margin}pt'),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Radio indicator
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: Colors.indigo.shade700,
                          size: 28,
                        )
                      else
                        Icon(
                          Icons.radio_button_unchecked,
                          color: Colors.grey.shade400,
                          size: 28,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 24),

          // Info Card
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'How to Choose',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '• 58mm: For small, portable thermal printers\n'
                    '• 80mm: Most common size, standard thermal printers\n'
                    '• 110mm: For wide format printers\n\n'
                    'Check your printer specifications or measure the paper width to select the correct size.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Preview Button
          ElevatedButton.icon(
            onPressed: () {
              _showPreview();
            },
            icon: const Icon(Icons.preview),
            label: const Text('Preview Receipt'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpec(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _showPreview() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receipt Preview'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _currentSize.widthMm * 2, // Scale for display
              padding: EdgeInsets.all(_currentSize.margin),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'SCHOOL NAME',
                    style: TextStyle(
                      fontSize: _currentSize.titleFontSize * 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: _currentSize.lineSpacing * 2),
                  Text(
                    'PAYMENT RECEIPT',
                    style: TextStyle(
                      fontSize: _currentSize.titleFontSize * 1.3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: _currentSize.lineSpacing * 2),
                  Text(
                    'Amount: ₦10,000.00',
                    style: TextStyle(
                      fontSize: _currentSize.amountFontSize * 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: _currentSize.lineSpacing),
                  Text(
                    'Student: John Doe',
                    style: TextStyle(fontSize: _currentSize.fontSize * 1.5),
                  ),
                  SizedBox(height: _currentSize.lineSpacing),
                  Text(
                    'Paper: ${_currentSize.name}',
                    style: TextStyle(
                      fontSize: (_currentSize.fontSize - 1) * 1.5,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This is a scaled preview.\nActual print will match ${_currentSize.name} paper.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}