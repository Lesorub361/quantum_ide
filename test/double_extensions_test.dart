import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/utils/double_extensions.dart';

void main() {
  group('SafeClampDouble', () {
    test('clamps within normal bounds', () {
      expect(5.0.safeClamp(0.0, 10.0), 5.0);
      expect((-2.0).safeClamp(0.0, 10.0), 0.0);
      expect(15.0.safeClamp(0.0, 10.0), 10.0);
    });

    test('handles inverted bounds and NaN safely', () {
      expect(5.0.safeClamp(10.0, 0.0), 5.0);
      expect(double.nan.safeClamp(10.0, 2.0), 2.0);
    });
  });
}
