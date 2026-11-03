// lib/widgets/health_info_section.dart
// Optional health information fields shared by the student registration and
// edit forms (genotype, blood group, disability, allergies, etc.).

import 'package:flutter/material.dart';
import '../models/student.dart';
import '../utils/display_settings_helper.dart';

const List<String> kGenotypes = ['AA', 'AS', 'AC', 'SS', 'SC', 'CC', 'Unknown'];
const List<String> kBloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'];

/// Holds the state of the health section so the parent form can read it on save.
class HealthInfoController {
  String? genotype;
  String? bloodGroup;
  bool hasDisability;
  final TextEditingController disabilityDetailsCtrl;
  final TextEditingController allergiesCtrl;
  final TextEditingController medicalConditionsCtrl;
  final TextEditingController medicationCtrl;
  final TextEditingController emergencyContactNameCtrl;
  final TextEditingController emergencyContactPhoneCtrl;

  HealthInfoController({Student? student})
      // Ignore stored values that aren't in the dropdown list, so the
      // dropdown never receives an unknown value.
      : genotype = kGenotypes.contains(student?.genotype) ? student!.genotype : null,
        bloodGroup = kBloodGroups.contains(student?.bloodGroup) ? student!.bloodGroup : null,
        hasDisability = student?.hasDisability == 1,
        disabilityDetailsCtrl = TextEditingController(text: student?.disabilityDetails ?? ''),
        allergiesCtrl = TextEditingController(text: student?.allergies ?? ''),
        medicalConditionsCtrl = TextEditingController(text: student?.medicalConditions ?? ''),
        medicationCtrl = TextEditingController(text: student?.medication ?? ''),
        emergencyContactNameCtrl = TextEditingController(text: student?.emergencyContactName ?? ''),
        emergencyContactPhoneCtrl = TextEditingController(text: student?.emergencyContactPhone ?? '');

  static String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// Column values for the students table. Empty fields are saved as null.
  Map<String, dynamic> toMap() => {
        'genotype': genotype,
        'bloodGroup': bloodGroup,
        'hasDisability': hasDisability ? 1 : 0,
        'disabilityDetails': hasDisability ? _text(disabilityDetailsCtrl) : null,
        'allergies': _text(allergiesCtrl),
        'medicalConditions': _text(medicalConditionsCtrl),
        'medication': _text(medicationCtrl),
        'emergencyContactName': _text(emergencyContactNameCtrl),
        'emergencyContactPhone': _text(emergencyContactPhoneCtrl),
      };

  void dispose() {
    disabilityDetailsCtrl.dispose();
    allergiesCtrl.dispose();
    medicalConditionsCtrl.dispose();
    medicationCtrl.dispose();
    emergencyContactNameCtrl.dispose();
    emergencyContactPhoneCtrl.dispose();
  }
}

/// Collapsible "Health Information (Optional)" form section.
class HealthInfoSection extends StatefulWidget {
  final HealthInfoController controller;
  final DisplaySettings ds;
  final bool initiallyExpanded;

  const HealthInfoSection({
    super.key,
    required this.controller,
    required this.ds,
    this.initiallyExpanded = false,
  });

  @override
  State<HealthInfoSection> createState() => _HealthInfoSectionState();
}

class _HealthInfoSectionState extends State<HealthInfoSection> {
  HealthInfoController get _c => widget.controller;

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      );

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    final gap = SizedBox(height: ds.cardPadding);

    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Theme(
        // Hide ExpansionTile's default divider lines.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: widget.initiallyExpanded,
          leading: Icon(Icons.medical_services, color: Colors.red.shade700, size: 20),
          title: Text(
            "Health Information (Optional)",
            style: TextStyle(
              fontSize: ds.titleFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          childrenPadding: EdgeInsets.fromLTRB(
              ds.cardPadding * 0.75, 0, ds.cardPadding * 0.75, ds.cardPadding * 0.75),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _c.genotype,
              decoration: _decoration("Genotype"),
              items: kGenotypes
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _c.genotype = v),
            ),
            gap,
            DropdownButtonFormField<String>(
              initialValue: _c.bloodGroup,
              decoration: _decoration("Blood Group"),
              items: kBloodGroups
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: (v) => setState(() => _c.bloodGroup = v),
            ),
            gap,
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: SwitchListTile(
                title: const Text("Has any disability?"),
                value: _c.hasDisability,
                onChanged: (v) => setState(() => _c.hasDisability = v),
              ),
            ),
            if (_c.hasDisability) ...[
              gap,
              TextFormField(
                controller: _c.disabilityDetailsCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: _decoration("Disability Details",
                    hint: "e.g. visual impairment, hearing, mobility"),
              ),
            ],
            gap,
            TextFormField(
              controller: _c.allergiesCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: _decoration("Allergies", hint: "e.g. peanuts, penicillin"),
            ),
            gap,
            TextFormField(
              controller: _c.medicalConditionsCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: _decoration("Medical Conditions",
                  hint: "e.g. asthma, epilepsy, sickle cell, diabetes"),
            ),
            gap,
            TextFormField(
              controller: _c.medicationCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: _decoration("Current Medication"),
            ),
            gap,
            TextFormField(
              controller: _c.emergencyContactNameCtrl,
              decoration: _decoration("Emergency Contact / Family Doctor"),
            ),
            gap,
            TextFormField(
              controller: _c.emergencyContactPhoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: _decoration("Emergency Contact Phone"),
            ),
          ],
        ),
      ),
    );
  }
}
