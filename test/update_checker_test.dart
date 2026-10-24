import 'package:flutter_test/flutter_test.dart';
import 'package:bursary_manager/utils/update_checker.dart';

void main() {
  test('compareVersions orders numerically', () {
    expect(UpdateChecker.compareVersions('24.10.0', '24.9.9') > 0, isTrue);
    expect(UpdateChecker.compareVersions('24.1.1', '24.1.5') < 0, isTrue);
    expect(UpdateChecker.compareVersions('24.1', '24.1.0'), 0);
    expect(UpdateChecker.compareVersions('25.0.0', '24.99.99') > 0, isTrue);
  });
}
