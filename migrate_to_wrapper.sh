#!/bin/bash

# List of files to migrate (excluding db_backup_helper.dart and license_checker.dart)
files=(
  "lib/screens/auth/user_management_screen.dart"
  "lib/screens/auth/welcome_screen.dart"
  "lib/screens/billing/bill_generate_screen.dart"
  "lib/screens/billing/bill_print_screen.dart"
  "lib/screens/billing/bill_receipt_screen.dart"
  "lib/screens/billing/bill_student_select_screen.dart"
  "lib/screens/classes/arm_form_screen.dart"
  "lib/screens/classes/arm_list_screen.dart"
  "lib/screens/classes/class_arm_screen.dart"
  "lib/screens/classes/class_form_screen.dart"
  "lib/screens/classes/class_list_screen.dart"
  "lib/screens/class_fees/class_fee_screen.dart"
  "lib/screens/dashboard/dashboard_screen.dart"
  "lib/screens/fees/class_fee_summary_screen.dart"
  "lib/screens/fees/fee_class_assignment_screen.dart"
  "lib/screens/fees/fee_item_form_screen.dart"
  "lib/screens/fees/fee_item_list_screen.dart"
  "lib/screens/license/license_activation_screen.dart"
  "lib/screens/license/license_management_screen.dart"
  "lib/screens/payments/payment_history_screen.dart"
  "lib/screens/payments/payment_receipt_screen.dart"
  "lib/screens/payments/payment_record_screen.dart"
  "lib/screens/payments/payment_student_select_screen.dart"
  "lib/screens/permissions/permission_management_screen.dart"
  "lib/screens/reports/daily_report_screen.dart"
  "lib/screens/reports/debtors_list_screen.dart"
  "lib/screens/school_profile/school_profile_screen.dart"
  "lib/screens/sessions/session_term_management_screen.dart"
  "lib/screens/settings/change_credentials_screen.dart"
  "lib/screens/settings/clear_data_screen.dart"
  "lib/screens/students/batch_student_upload_screen.dart"
  "lib/screens/students/deactivate_student_screen.dart"
  "lib/screens/students/inactive_students_screen.dart"
  "lib/screens/students/student_details_screen.dart"
  "lib/screens/students/student_edit_screen.dart"
  "lib/screens/students/student_form_screen.dart"
  "lib/screens/students/student_promotion_screen.dart"
  "lib/screens/students/student_statement_screen.dart"
  "lib/utils/batch_student_upload_helper.dart"
  "lib/utils/permission_helper.dart"
)

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo "Migrating $file..."
    # Replace relative path imports
    sed -i "s|import '../../db/database_helper.dart';|import '../../data/database_helper_wrapper.dart';|g" "$file"
    # Replace package imports
    sed -i "s|import 'package:bursary_manager/db/database_helper.dart';|import 'package:bursary_manager/data/database_helper_wrapper.dart';|g" "$file"
    # Replace DatabaseHelper instantiations
    sed -i "s|DatabaseHelper()|DatabaseHelperWrapper()|g" "$file"
    sed -i "s|final DatabaseHelper |final DatabaseHelperWrapper |g" "$file"
    sed -i "s|final db = DatabaseHelper|final db = DatabaseHelperWrapper|g" "$file"
  else
    echo "File not found: $file"
  fi
done

echo "Migration complete!"
