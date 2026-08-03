import 'package:cuentaria_app/ui/screens/movements/movement_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('humanMovementLabel', () {
    final cases = {
      'Expense': 'Gasto',
      'ForeignCurrencyExpense': 'Gasto',
      'Income': 'Ingreso',
      'Transfer': 'Mover',
      'AcquisitionConversion': 'Mover',
      'DisposalConversion': 'Mover',
      'CryptoSale': 'Mover',
      'Distribution': 'Distribución',
      'Opening': 'Saldo inicial',
      'Reversal': 'Reverso',
      'Adjustment': 'Ajuste',
    };

    cases.forEach((type, label) {
      test('maps $type to $label', () {
        expect(humanMovementLabel(type), label);
      });
    });

    test('falls back to the raw type for an unknown factory name', () {
      expect(humanMovementLabel('SomeFutureFactory'), 'SomeFutureFactory');
    });
  });
}
