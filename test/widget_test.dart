// Quantum IDE - Basic smoke test
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/app.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: QuantumApp()),
    );
    // Just verify the app builds without throwing
    expect(tester.takeException(), isNull);
  });
}
