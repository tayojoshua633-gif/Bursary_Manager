// lib/screens/parents/manage_parent_contacts_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/parent.dart';
import '../../utils/display_settings_helper.dart';

class ManageParentContactsScreen extends StatefulWidget {
  const ManageParentContactsScreen({super.key});

  @override
  State<ManageParentContactsScreen> createState() =>
      _ManageParentContactsScreenState();
}

class _ManageParentContactsScreenState
    extends State<ManageParentContactsScreen> with SingleTickerProviderStateMixin {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Parent> _parents = [];
  Set<String> _savedPhoneNumbers = {};
  // Map of normalized phone number to Contact object (for updating)
  Map<String, Contact> _phoneToContactMap = {};
  bool _loading = true;
  bool _hasPermission = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Tab controller for filtering
  late TabController _tabController;
  int _selectedTabIndex = 0;

  // Stats
  int _totalParents = 0;
  int _savedCount = 0;
  int _notSavedCount = 0;
  int _needsUpdateCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedTabIndex = _tabController.index;
        });
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      // Request contact permission
      _hasPermission = await FlutterContacts.requestPermission(readonly: true);

      // Load all parents from database
      final parentsData = await _db.getAllParents();
      _parents = parentsData.map((p) => Parent.fromMap(p)).toList();
      _totalParents = _parents.length;

      // Load device contacts if permission granted
      if (_hasPermission) {
        await _loadDeviceContacts();
      }

      _updateStats();
    } catch (e) {
      debugPrint('Error loading data: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadDeviceContacts() async {
    try {
      // Get all contacts with phone numbers
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      // Extract all phone numbers (normalized) and map to contacts
      _savedPhoneNumbers = {};
      _phoneToContactMap = {};
      for (final contact in contacts) {
        for (final phone in contact.phones) {
          final normalized = _normalizePhoneNumber(phone.number);
          if (normalized.isNotEmpty) {
            _savedPhoneNumbers.add(normalized);
            _phoneToContactMap[normalized] = contact;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading device contacts: $e');
    }
  }

  String _normalizePhoneNumber(String phone) {
    // Remove all non-digit characters except leading +
    String normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
    // Remove leading zeros after country code or at start
    if (normalized.startsWith('+')) {
      // Keep country code format
      return normalized;
    }
    // Remove leading zeros
    normalized = normalized.replaceFirst(RegExp(r'^0+'), '');
    return normalized;
  }

  bool _isContactSaved(Parent parent) {
    if (!_hasPermission) return false;

    final phone1 = _normalizePhoneNumber(parent.phoneNumber);
    final phone2 = parent.phoneNumber2 != null
        ? _normalizePhoneNumber(parent.phoneNumber2!)
        : '';

    // Check if any of the parent's phone numbers are saved
    for (final savedPhone in _savedPhoneNumbers) {
      if (phone1.isNotEmpty && savedPhone.endsWith(phone1)) return true;
      if (phone1.isNotEmpty && phone1.endsWith(savedPhone)) return true;
      if (phone2.isNotEmpty && savedPhone.endsWith(phone2)) return true;
      if (phone2.isNotEmpty && phone2.endsWith(savedPhone)) return true;
    }
    return false;
  }

  /// Check if a saved contact needs to be updated (e.g., has new phone number 2)
  bool _contactNeedsUpdate(Parent parent) {
    if (!_hasPermission) return false;
    if (!_isContactSaved(parent)) return false;

    final phone1 = _normalizePhoneNumber(parent.phoneNumber);
    final phone2 = parent.phoneNumber2 != null && parent.phoneNumber2!.isNotEmpty
        ? _normalizePhoneNumber(parent.phoneNumber2!)
        : '';

    // If no phone2, no update needed
    if (phone2.isEmpty) return false;

    // Check if phone1 is saved
    bool phone1Saved = false;
    bool phone2Saved = false;

    for (final savedPhone in _savedPhoneNumbers) {
      if (phone1.isNotEmpty && (savedPhone.endsWith(phone1) || phone1.endsWith(savedPhone))) {
        phone1Saved = true;
      }
      if (phone2.isNotEmpty && (savedPhone.endsWith(phone2) || phone2.endsWith(savedPhone))) {
        phone2Saved = true;
      }
    }

    // Needs update if phone1 is saved but phone2 is not
    return phone1Saved && !phone2Saved;
  }

  /// Get the device contact that matches this parent (by phone number)
  Contact? _getMatchingDeviceContact(Parent parent) {
    final phone1 = _normalizePhoneNumber(parent.phoneNumber);

    for (final entry in _phoneToContactMap.entries) {
      if (phone1.isNotEmpty && (entry.key.endsWith(phone1) || phone1.endsWith(entry.key))) {
        return entry.value;
      }
    }
    return null;
  }

  void _updateStats() {
    _savedCount = 0;
    _notSavedCount = 0;
    _needsUpdateCount = 0;

    for (final parent in _parents) {
      if (_isContactSaved(parent)) {
        _savedCount++;
        if (_contactNeedsUpdate(parent)) {
          _needsUpdateCount++;
        }
      } else {
        _notSavedCount++;
      }
    }
  }

  List<Parent> get _filteredParents {
    // First filter by tab selection
    List<Parent> tabFiltered;
    switch (_selectedTabIndex) {
      case 1: // Saved
        tabFiltered = _parents.where((p) => _isContactSaved(p) && !_contactNeedsUpdate(p)).toList();
        break;
      case 2: // Not Saved
        tabFiltered = _parents.where((p) => !_isContactSaved(p)).toList();
        break;
      case 3: // Needs Update
        tabFiltered = _parents.where((p) => _contactNeedsUpdate(p)).toList();
        break;
      default: // All
        tabFiltered = _parents;
    }

    // Then filter by search query
    if (_searchQuery.isEmpty) return tabFiltered;

    final query = _searchQuery.toLowerCase();
    return tabFiltered.where((p) {
      return p.parentName.toLowerCase().contains(query) ||
          p.phoneNumber.contains(query) ||
          (p.phoneNumber2?.contains(query) ?? false);
    }).toList();
  }

  Future<void> _saveContact(Parent parent) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Request write permission
      if (!await FlutterContacts.requestPermission(readonly: false)) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied to access contacts'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Parse the parent name into parts
      final nameParts = parent.parentName.trim().split(' ');
      String firstName = '';
      String lastName = '';
      String middleName = '';
      const String suffix = 'Parent'; // Suffix to identify as parent in contacts

      if (nameParts.length == 1) {
        firstName = nameParts[0];
      } else if (nameParts.length == 2) {
        firstName = nameParts[0];
        lastName = nameParts[1];
      } else if (nameParts.length >= 3) {
        firstName = nameParts[0];
        middleName = nameParts.sublist(1, nameParts.length - 1).join(' ');
        lastName = nameParts.last;
      }

      // Create the contact with "Parent" suffix for easy identification
      final newContact = Contact(
        name: Name(
          first: firstName,
          middle: middleName,
          last: lastName,
          suffix: suffix,
        ),
        phones: [
          Phone(parent.phoneNumber, label: PhoneLabel.mobile),
          if (parent.phoneNumber2 != null && parent.phoneNumber2!.isNotEmpty)
            Phone(parent.phoneNumber2!, label: PhoneLabel.work),
        ],
        emails: [
          if (parent.emailAddress != null && parent.emailAddress!.isNotEmpty)
            Email(parent.emailAddress!, label: EmailLabel.home),
        ],
        addresses: [
          if (parent.homeAddress.isNotEmpty)
            Address(parent.homeAddress, label: AddressLabel.home),
          if (parent.officeAddress != null && parent.officeAddress!.isNotEmpty)
            Address(parent.officeAddress!, label: AddressLabel.work),
        ],
        organizations: [
          if (parent.occupation != null && parent.occupation!.isNotEmpty)
            Organization(title: parent.occupation!),
        ],
      );

      // Insert the contact
      await newContact.insert();

      // Update local state without reloading all contacts (faster)
      final phone1 = _normalizePhoneNumber(parent.phoneNumber);
      if (phone1.isNotEmpty) {
        _savedPhoneNumbers.add(phone1);
        _phoneToContactMap[phone1] = newContact;
      }
      if (parent.phoneNumber2 != null && parent.phoneNumber2!.isNotEmpty) {
        final phone2 = _normalizePhoneNumber(parent.phoneNumber2!);
        if (phone2.isNotEmpty) {
          _savedPhoneNumbers.add(phone2);
          _phoneToContactMap[phone2] = newContact;
        }
      }
      _updateStats();

      if (!mounted) return;
      Navigator.pop(context); // Close loading
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${parent.parentName} saved to contacts'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save contact: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Update an existing device contact with new phone numbers from the parent
  Future<void> _updateContact(Parent parent) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Request write permission
      if (!await FlutterContacts.requestPermission(readonly: false)) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied to access contacts'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Find the matching device contact
      final existingContact = _getMatchingDeviceContact(parent);
      if (existingContact == null) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find existing contact to update'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Get the full contact with all properties
      final fullContact = await FlutterContacts.getContact(existingContact.id,
          withProperties: true, withAccounts: true);
      if (fullContact == null) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load contact details'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Get existing phone numbers (normalized)
      final existingPhones = <String>{};
      for (final phone in fullContact.phones) {
        existingPhones.add(_normalizePhoneNumber(phone.number));
      }

      // Check which parent phone numbers need to be added
      final phone1 = parent.phoneNumber;
      final phone1Normalized = _normalizePhoneNumber(phone1);
      final phone2 = parent.phoneNumber2;
      final phone2Normalized = phone2 != null && phone2.isNotEmpty
          ? _normalizePhoneNumber(phone2)
          : '';

      List<Phone> updatedPhones = List.from(fullContact.phones);
      bool needsUpdate = false;

      // Check if phone1 needs to be added
      bool phone1Exists = existingPhones.any((p) =>
          p.endsWith(phone1Normalized) || phone1Normalized.endsWith(p));
      if (!phone1Exists && phone1.isNotEmpty) {
        updatedPhones.add(Phone(phone1, label: PhoneLabel.mobile));
        needsUpdate = true;
      }

      // Check if phone2 needs to be added
      if (phone2Normalized.isNotEmpty) {
        bool phone2Exists = existingPhones.any((p) =>
            p.endsWith(phone2Normalized) || phone2Normalized.endsWith(p));
        if (!phone2Exists) {
          updatedPhones.add(Phone(phone2!, label: PhoneLabel.work));
          needsUpdate = true;
        }
      }

      if (!needsUpdate) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact is already up to date'),
            backgroundColor: Colors.blue,
          ),
        );
        return;
      }

      // Update the contact
      fullContact.phones = updatedPhones;
      await fullContact.update();

      // Update local state without reloading all contacts (faster)
      if (phone2Normalized.isNotEmpty) {
        _savedPhoneNumbers.add(phone2Normalized);
        _phoneToContactMap[phone2Normalized] = fullContact;
      }
      _updateStats();

      if (!mounted) return;
      Navigator.pop(context); // Close loading
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${parent.parentName} contact updated'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update contact: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveAllUnsavedContacts() async {
    final unsavedParents =
        _parents.where((p) => !_isContactSaved(p)).toList();

    if (unsavedParents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All contacts are already saved'),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save All Contacts'),
        content: Text(
          'This will save ${unsavedParents.length} unsaved contact(s) to your device. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show progress dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text('Saving ${unsavedParents.length} contacts...'),
          ],
        ),
      ),
    );

    int savedCount = 0;
    int failedCount = 0;

    for (final parent in unsavedParents) {
      try {
        // Request write permission
        if (!await FlutterContacts.requestPermission(readonly: false)) {
          failedCount++;
          continue;
        }

        // Parse the parent name into parts
        final nameParts = parent.parentName.trim().split(' ');
        String firstName = '';
        String lastName = '';
        String middleName = '';
        const String suffix = 'Parent'; // Suffix to identify as parent in contacts

        if (nameParts.length == 1) {
          firstName = nameParts[0];
        } else if (nameParts.length == 2) {
          firstName = nameParts[0];
          lastName = nameParts[1];
        } else if (nameParts.length >= 3) {
          firstName = nameParts[0];
          middleName = nameParts.sublist(1, nameParts.length - 1).join(' ');
          lastName = nameParts.last;
        }

        // Create and insert the contact with "Parent" suffix
        final newContact = Contact(
          name: Name(
            first: firstName,
            middle: middleName,
            last: lastName,
            suffix: suffix,
          ),
          phones: [
            Phone(parent.phoneNumber, label: PhoneLabel.mobile),
            if (parent.phoneNumber2 != null && parent.phoneNumber2!.isNotEmpty)
              Phone(parent.phoneNumber2!, label: PhoneLabel.work),
          ],
          emails: [
            if (parent.emailAddress != null && parent.emailAddress!.isNotEmpty)
              Email(parent.emailAddress!, label: EmailLabel.home),
          ],
          addresses: [
            if (parent.homeAddress.isNotEmpty)
              Address(parent.homeAddress, label: AddressLabel.home),
            if (parent.officeAddress != null &&
                parent.officeAddress!.isNotEmpty)
              Address(parent.officeAddress!, label: AddressLabel.work),
          ],
          organizations: [
            if (parent.occupation != null && parent.occupation!.isNotEmpty)
              Organization(title: parent.occupation!),
          ],
        );

        await newContact.insert();
        savedCount++;
      } catch (e) {
        failedCount++;
        debugPrint('Failed to save ${parent.parentName}: $e');
      }
    }

    // Reload device contacts
    await _loadDeviceContacts();
    _updateStats();

    if (!mounted) return;
    Navigator.pop(context); // Close progress dialog
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failedCount > 0
              ? 'Saved $savedCount contacts. $failedCount failed.'
              : 'Successfully saved $savedCount contacts',
        ),
        backgroundColor: failedCount > 0 ? Colors.orange : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Parent Contacts'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
        bottom: _hasPermission && !_loading
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people, size: 18),
                        const SizedBox(width: 6),
                        Text('All ($_totalParents)'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, size: 18),
                        const SizedBox(width: 6),
                        Text('Saved (${_savedCount - _needsUpdateCount})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.pending, size: 18),
                        const SizedBox(width: 6),
                        Text('Not Saved ($_notSavedCount)'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sync, size: 18),
                        const SizedBox(width: 6),
                        Text('Update ($_needsUpdateCount)'),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasPermission
              ? _buildPermissionDenied()
              : Column(
                  children: [
                    // Search Bar
                    _buildSearchBar(ds),

                    // Parent List
                    Expanded(
                      child: _filteredParents.isEmpty
                          ? _buildEmptyState()
                          : _buildParentList(ds),
                    ),
                  ],
                ),
      floatingActionButton: !_loading && _hasPermission && _notSavedCount > 0 && _selectedTabIndex != 1
          ? FloatingActionButton.extended(
              onPressed: _saveAllUnsavedContacts,
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.save_alt),
              label: Text('Save All ($_notSavedCount)'),
            )
          : null,
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.contacts_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'Contact Permission Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please grant contact permission to manage parent contacts',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Request Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(DisplaySettings ds) {
    return Container(
      padding: EdgeInsets.all(ds.cardPadding),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by name or phone...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'No parents found'
                : 'No results for "$_searchQuery"',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentList(DisplaySettings ds) {
    final filtered = _filteredParents;

    return ListView.builder(
      padding: EdgeInsets.all(ds.cardPadding),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final parent = filtered[index];
        final isSaved = _isContactSaved(parent);
        final needsUpdate = _contactNeedsUpdate(parent);

        // Determine status color and text
        Color statusColor;
        String statusText;
        if (!isSaved) {
          statusColor = Colors.orange;
          statusText = 'Not Saved';
        } else if (needsUpdate) {
          statusColor = Colors.purple;
          statusText = 'Needs Update';
        } else {
          statusColor = Colors.green;
          statusText = 'Saved to Contacts';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: statusColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: statusColor.withValues(alpha: 0.2),
              child: Icon(
                !isSaved
                    ? Icons.person
                    : needsUpdate
                        ? Icons.sync
                        : Icons.check,
                color: statusColor,
              ),
            ),
            title: Text(
              parent.parentName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      parent.phoneNumber,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
                if (parent.phoneNumber2 != null &&
                    parent.phoneNumber2!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.phone_android,
                          size: 14, color: needsUpdate ? Colors.purple : Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        parent.phoneNumber2!,
                        style: TextStyle(
                          fontSize: 13,
                          color: needsUpdate ? Colors.purple : Colors.grey[700],
                          fontWeight: needsUpdate ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                      if (needsUpdate) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(New)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.purple[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            trailing: _buildTrailingWidget(parent, isSaved, needsUpdate),
          ),
        );
      },
    );
  }

  Widget _buildTrailingWidget(Parent parent, bool isSaved, bool needsUpdate) {
    if (!isSaved) {
      // Not saved - show prominent Save button
      return ElevatedButton.icon(
        onPressed: () => _saveContact(parent),
        icon: const Icon(Icons.save, size: 18),
        label: const Text('Save'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    } else if (needsUpdate) {
      // Saved but needs update - show Update button
      return ElevatedButton.icon(
        onPressed: () => _updateContact(parent),
        icon: const Icon(Icons.sync, size: 18),
        label: const Text('Update'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    } else {
      // Saved and up to date - show checkmark with label
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
            const SizedBox(width: 4),
            Text(
              'Saved',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
  }
}
