// lib/screens/license/license_generator_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../utils/license_helper.dart';
import '../../utils/license_tier_helper.dart';

class LicenseGeneratorScreen extends StatefulWidget {
  const LicenseGeneratorScreen({super.key});

  @override
  State<LicenseGeneratorScreen> createState() => _LicenseGeneratorScreenState();
}

class _LicenseGeneratorScreenState extends State<LicenseGeneratorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _schoolNameController = TextEditingController();
  final _schoolCodeController = TextEditingController();
  final _maxStudentsController = TextEditingController();
  final _deviceIdController = TextEditingController();

  DateTime _expiryDate = DateTime.now().add(const Duration(days: 365));
  String? _generatedKey;
  bool _isGenerating = false;
  bool _bindToDevice = false;

  @override
  void dispose() {
    _schoolNameController.dispose();
    _schoolCodeController.dispose();
    _maxStudentsController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  Future<void> _selectExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)), // 10 years
    );

    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  /// Calendar-correct "n months from now" (handles year rollover and lets
  /// DateTime normalize day overflow, e.g. Jan 31 + 1 month -> Mar 3).
  DateTime _addMonths(int months) {
    final now = DateTime.now();
    return DateTime(now.year, now.month + months, now.day);
  }

  Widget _buildExpiryPresetChip(String label, DateTime date) {
    return ActionChip(
      label: Text(label),
      onPressed: () => setState(() => _expiryDate = date),
    );
  }

  void _generateLicense() {
    if (!_formKey.currentState!.validate()) return;

    // Validate device ID if binding is enabled
    if (_bindToDevice && _deviceIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Device ID or disable device binding'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final maxStudents = _maxStudentsController.text.isEmpty
          ? 0
          : int.parse(_maxStudentsController.text);

      final targetDeviceId = _bindToDevice
          ? _deviceIdController.text.trim()
          : null;

      final licenseKey = LicenseHelper.generateLicenseKey(
        schoolName: _schoolNameController.text.trim(),
        schoolCode: _schoolCodeController.text.trim().toUpperCase(),
        expiryDate: _expiryDate,
        maxStudents: maxStudents,
        targetDeviceId: targetDeviceId,
      );

      setState(() {
        _generatedKey = licenseKey;
        _isGenerating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _bindToDevice
                ? 'License key generated and bound to device!'
                : 'License key generated successfully!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _copyToClipboard() {
    if (_generatedKey != null) {
      Clipboard.setData(ClipboardData(text: _generatedKey!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('License key copied to clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearForm() {
    setState(() {
      _schoolNameController.clear();
      _schoolCodeController.clear();
      _maxStudentsController.clear();
      _deviceIdController.clear();
      _expiryDate = DateTime.now().add(const Duration(days: 365));
      _generatedKey = null;
      _bindToDevice = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('License Key Generator'),
        actions: [
          if (_generatedKey != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _clearForm,
              tooltip: 'Generate New',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon
              Icon(
                Icons.vpn_key,
                size: 64,
                color: Colors.blue.shade700,
              ),

              const SizedBox(height: 16),

              const Text(
                'Generate License Key',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              const Text(
                'Fill in the school details to generate a license key',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // School Name
              TextFormField(
                controller: _schoolNameController,
                decoration: InputDecoration(
                  labelText: 'School Name *',
                  hintText: 'e.g., St. Mary\'s High School',
                  prefixIcon: const Icon(Icons.school),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter school name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // School Code
              TextFormField(
                controller: _schoolCodeController,
                decoration: InputDecoration(
                  labelText: 'School Code *',
                  hintText: 'e.g., SMS001',
                  prefixIcon: const Icon(Icons.tag),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter school code';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Max Students
              TextFormField(
                controller: _maxStudentsController,
                decoration: InputDecoration(
                  labelText: 'Max Students (Optional)',
                  hintText: 'Leave empty for unlimited',
                  prefixIcon: const Icon(Icons.people),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 16),

              // License Tier / Pricing Guide
              _buildTierPicker(),

              const SizedBox(height: 16),

              // Device Binding Section
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.devices, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Device Binding (Optional)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Switch(
                            value: _bindToDevice,
                            onChanged: (value) {
                              setState(() => _bindToDevice = value);
                            },
                            activeTrackColor: Colors.orange.shade300,
                            activeThumbColor: Colors.orange,
                          ),
                        ],
                      ),
                      if (_bindToDevice) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Enter the Device ID from the target device:',
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _deviceIdController,
                          decoration: InputDecoration(
                            labelText: 'Device ID',
                            hintText: 'Paste device ID here',
                            prefixIcon: const Icon(Icons.fingerprint, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            const Expanded(
                              child: Text(
                                'If bound, this license will ONLY work on that specific device',
                                style: TextStyle(fontSize: 11, color: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            const Expanded(
                              child: Text(
                                'Without binding, license can be activated on any device (binding happens during activation)',
                                style: TextStyle(fontSize: 11, color: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Expiry Date
              Card(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: const Text('Expiry Date'),
                        subtitle: Text(
                          '${_expiryDate.day}/${_expiryDate.month}/${_expiryDate.year}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        trailing: const Icon(Icons.edit),
                        onTap: _selectExpiryDate,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildExpiryPresetChip('1 Month', _addMonths(1)),
                            _buildExpiryPresetChip('3 Months', _addMonths(3)),
                            _buildExpiryPresetChip('6 Months', _addMonths(6)),
                            _buildExpiryPresetChip('1 Year', _addMonths(12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Generate Button
              if (_generatedKey == null)
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateLicense,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.create, size: 28),
                  label: const Text(
                    'Generate License Key',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    elevation: 4,
                  ),
                ),

              // Generated License Display
              if (_generatedKey != null) ...[
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              'License Key Generated',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        const Divider(height: 24),

                        const Text(
                          'School Details:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildDetailRow('School', _schoolNameController.text),
                        _buildDetailRow('Code', _schoolCodeController.text.toUpperCase()),
                        _buildDetailRow(
                          'Expiry',
                          '${_expiryDate.day}/${_expiryDate.month}/${_expiryDate.year}',
                        ),
                        if (_maxStudentsController.text.isNotEmpty)
                          _buildDetailRow('Max Students', _maxStudentsController.text),

                        const SizedBox(height: 16),

                        const Text(
                          'LICENSE KEY:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade700, width: 2),
                          ),
                          child: SelectableText(
                            _generatedKey!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _copyToClipboard,
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy Key'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _clearForm,
                                icon: const Icon(Icons.refresh),
                                label: const Text('New License'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Info Card
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Important',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '• Each license key is unique and encrypted\n'
                        '• Keys are bound to the device upon activation\n'
                        '• One license can only be activated once per device\n'
                        '• Keep the license key secure\n'
                        '• Share the key with the school administrator',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Currently selected/detected tier, derived from whatever is in the
  /// Max Students field — picking a tier chip just writes a representative
  /// number into that field, so there is one source of truth either way.
  LicenseTier? get _currentTier {
    final students = int.tryParse(_maxStudentsController.text.trim());
    if (students == null) return null;
    return tierForStudentCount(students);
  }

  String _formatNaira(int amount) => '₦${NumberFormat("#,##0").format(amount)}';

  Widget _buildTierPicker() {
    final currentTier = _currentTier;

    return Card(
      color: Colors.purple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sell, color: Colors.purple.shade700, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'License Tier (Pricing Guide)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick a tier to auto-fill Max Students, or type a number above and the matching tier is detected automatically.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: licenseTiers.map((tier) {
                final isSelected = tier == currentTier;
                return ChoiceChip(
                  label: Text('${tier.emoji} ${tier.name} (${tier.rangeLabel})'),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _maxStudentsController.text =
                          (tier.maxStudents ?? tier.minStudents).toString();
                    });
                  },
                );
              }).toList(),
            ),
            if (currentTier != null) ...[
              const Divider(height: 20),
              _buildDetailRow(
                'License',
                _formatNaira(currentTier.licensePrice),
              ),
              _buildDetailRow(
                'Termly Support',
                _formatNaira(currentTier.termlySupport),
              ),
              _buildDetailRow(
                'Annual Support',
                _formatNaira(currentTier.annualSupport),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
