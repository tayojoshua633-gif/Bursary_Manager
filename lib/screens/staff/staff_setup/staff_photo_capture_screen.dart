// lib/screens/staff/staff_setup/staff_photo_capture_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/database_helper_wrapper.dart';
import '../../../models/staff.dart';
import '../../../utils/display_settings_helper.dart';

class StaffPhotoCaptureScreen extends StatefulWidget {
  const StaffPhotoCaptureScreen({super.key});

  @override
  State<StaffPhotoCaptureScreen> createState() => _StaffPhotoCaptureScreenState();
}

class _StaffPhotoCaptureScreenState extends State<StaffPhotoCaptureScreen> {
  final _db = DatabaseHelperWrapper();
  List<Staff> _staffList = [];
  List<Staff> _filteredStaff = [];
  bool _loading = true;
  String _searchQuery = '';
  String _filterType = 'All'; // 'All', 'With Photo', 'Without Photo'

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _loading = true);
    try {
      final db = await _db.database;
      final results = await db.query(
        'staff',
        where: 'isActive = ?',
        whereArgs: [1],
        orderBy: 'surname ASC, firstName ASC',
      );

      _staffList = results.map((map) => Staff.fromMap(map)).toList();
      _applyFilters();
    } catch (e) {
      debugPrint('Error loading staff: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyFilters() {
    _filteredStaff = _staffList.where((staff) {
      // Apply search filter
      final matchesSearch = _searchQuery.isEmpty ||
          staff.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          staff.staffId.toLowerCase().contains(_searchQuery.toLowerCase());

      // Apply photo filter
      final hasPhoto = staff.photoPath != null && staff.photoPath!.isNotEmpty;
      final matchesPhotoFilter = _filterType == 'All' ||
          (_filterType == 'With Photo' && hasPhoto) ||
          (_filterType == 'Without Photo' && !hasPhoto);

      return matchesSearch && matchesPhotoFilter;
    }).toList();
  }

  Future<void> _capturePhoto(Staff staff) async {
    final picker = ImagePicker();

    try {
      // Show source selection dialog
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Photo Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Camera'),
                subtitle: const Text('Take a new photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('Gallery'),
                subtitle: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
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

      if (source == null) return;

      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
        requestFullMetadata: false,
      );

      if (image != null && mounted) {
        // Save to app directory
        final appDir = await getApplicationDocumentsDirectory();
        final staffPhotosDir = Directory('${appDir.path}/staff_photos');
        if (!await staffPhotosDir.exists()) {
          await staffPhotosDir.create(recursive: true);
        }

        final fileName = 'staff_${staff.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedPath = '${staffPhotosDir.path}/$fileName';

        // Copy image to app directory
        await File(image.path).copy(savedPath);

        // Delete old photo if exists
        if (staff.photoPath != null && staff.photoPath!.isNotEmpty) {
          try {
            final oldFile = File(staff.photoPath!);
            if (await oldFile.exists()) {
              await oldFile.delete();
            }
          } catch (e) {
            debugPrint('Error deleting old photo: $e');
          }
        }

        // Update database
        final db = await _db.database;
        await db.update(
          'staff',
          {'photoPath': savedPath, 'updatedAt': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [staff.id],
        );

        // Reload staff list
        await _loadStaff();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Photo updated for ${staff.fullName}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error capturing photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deletePhoto(Staff staff) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: Text('Are you sure you want to delete the photo for ${staff.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Delete file
      if (staff.photoPath != null && staff.photoPath!.isNotEmpty) {
        final file = File(staff.photoPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Update database
      final db = await _db.database;
      await db.update(
        'staff',
        {'photoPath': null, 'updatedAt': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [staff.id],
      );

      await _loadStaff();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo deleted for ${staff.fullName}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    final withPhotoCount = _staffList.where((s) => s.photoPath != null && s.photoPath!.isNotEmpty).length;
    final withoutPhotoCount = _staffList.length - withPhotoCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Photo Capture'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStaff,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats Card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(ds.cardPadding),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Total Staff', _staffList.length.toString(), Icons.people, Colors.white),
                _buildStatItem('With Photo', withPhotoCount.toString(), Icons.check_circle, Colors.greenAccent),
                _buildStatItem('Without Photo', withoutPhotoCount.toString(), Icons.camera_alt, Colors.orangeAccent),
              ],
            ),
          ),

          // Search and Filter Bar
          Padding(
            padding: EdgeInsets.all(ds.cardPadding),
            child: Column(
              children: [
                // Search Field
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by name or staff ID...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                      _applyFilters();
                    });
                  },
                ),
                SizedBox(height: ds.cardPadding * 0.75),

                // Filter Chips
                Row(
                  children: [
                    Text('Filter: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: ds.bodyFontSize)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', Icons.people),
                            const SizedBox(width: 8),
                            _buildFilterChip('With Photo', Icons.check_circle),
                            const SizedBox(width: 8),
                            _buildFilterChip('Without Photo', Icons.camera_alt),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Staff List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredStaff.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty || _filterType != 'All'
                                  ? 'No staff match your filters'
                                  : 'No staff found',
                              style: TextStyle(fontSize: ds.titleFontSize, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: ds.cardPadding),
                        itemCount: _filteredStaff.length,
                        itemBuilder: (context, index) => _buildStaffCard(_filteredStaff[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, IconData icon) {
    final isSelected = _filterType == label;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.deepPurple),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      selectedColor: Colors.deepPurple,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
      ),
      onSelected: (selected) {
        setState(() {
          _filterType = label;
          _applyFilters();
        });
      },
    );
  }

  Widget _buildStaffCard(Staff staff) {
    final ds = DisplaySettingsProvider.of(context);
    final hasPhoto = staff.photoPath != null && staff.photoPath!.isNotEmpty;
    final photoFile = hasPhoto ? File(staff.photoPath!) : null;
    final photoExists = photoFile != null && photoFile.existsSync();

    return Card(
      margin: EdgeInsets.only(bottom: ds.cardPadding * 0.75),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _capturePhoto(staff),
        child: Padding(
          padding: EdgeInsets.all(ds.cardPadding),
          child: Row(
            children: [
              // Photo
              GestureDetector(
                onTap: () => _capturePhoto(staff),
                onLongPress: photoExists ? () => _showPhotoOptions(staff) : null,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: photoExists ? Colors.green : Colors.orange,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: photoExists
                        ? Image.file(
                            photoFile,
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stack) => _buildPhotoPlaceholder(),
                          )
                        : _buildPhotoPlaceholder(),
                  ),
                ),
              ),
              SizedBox(width: ds.cardPadding),

              // Staff Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.fullName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: ds.titleFontSize * 0.9,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            staff.staffId,
                            style: TextStyle(
                              fontSize: ds.subtitleFontSize,
                              color: Colors.deepPurple.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: staff.isTeachingStaff ? Colors.blue.shade100 : Colors.teal.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            staff.isTeachingStaff ? 'Teaching' : 'Non-Teaching',
                            style: TextStyle(
                              fontSize: ds.subtitleFontSize,
                              color: staff.isTeachingStaff ? Colors.blue.shade700 : Colors.teal.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Action Buttons
              Column(
                children: [
                  // Capture Button
                  IconButton(
                    icon: Icon(
                      photoExists ? Icons.camera_alt : Icons.add_a_photo,
                      color: photoExists ? Colors.blue : Colors.deepPurple,
                    ),
                    onPressed: () => _capturePhoto(staff),
                    tooltip: photoExists ? 'Update Photo' : 'Capture Photo',
                  ),
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: photoExists ? Colors.green.shade100 : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      photoExists ? 'Has Photo' : 'No Photo',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: photoExists ? Colors.green.shade700 : Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: 40,
        color: Colors.grey[500],
      ),
    );
  }

  void _showPhotoOptions(Staff staff) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blue),
              title: const Text('View Photo'),
              onTap: () {
                Navigator.pop(context);
                _viewPhoto(staff);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Update Photo'),
              onTap: () {
                Navigator.pop(context);
                _capturePhoto(staff);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Photo'),
              onTap: () {
                Navigator.pop(context);
                _deletePhoto(staff);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _viewPhoto(Staff staff) {
    if (staff.photoPath == null || staff.photoPath!.isEmpty) return;

    final file = File(staff.photoPath!);
    if (!file.existsSync()) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(staff.fullName),
              centerTitle: true,
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: Image.file(
                file,
                fit: BoxFit.contain,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _capturePhoto(staff);
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Update'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _deletePhoto(staff);
                    },
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
