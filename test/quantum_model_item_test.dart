import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/models/quantum_model_item.dart';

void main() {
  group('QuantumModelItem', () {
    test('predefinedModels have non-empty required metadata', () {
      expect(QuantumModelItem.predefinedModels, isNotEmpty);
      for (final model in QuantumModelItem.predefinedModels) {
        expect(model.id.trim(), isNotEmpty);
        expect(model.name.trim(), isNotEmpty);
        expect(model.providerName.trim(), isNotEmpty);
        expect(model.category.trim(), isNotEmpty);
        expect(model.badge.trim(), isNotEmpty);
      }
    });
  });
}
