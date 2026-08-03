/// Human-facing label for a movement's `metadata.type` (#115): the user
/// never sees factory names (PRD U1), only the family of what they did.
/// Falls back to the raw type for any factory not yet mapped here.
String humanMovementLabel(String type) {
  switch (type) {
    case 'Expense':
    case 'ForeignCurrencyExpense':
      return 'Gasto';
    case 'Income':
      return 'Ingreso';
    case 'Transfer':
    case 'AcquisitionConversion':
    case 'DisposalConversion':
    case 'CryptoSale':
      return 'Mover';
    case 'Distribution':
      return 'Distribución';
    case 'Opening':
      return 'Saldo inicial';
    case 'Reversal':
      return 'Reverso';
    case 'Adjustment':
      return 'Ajuste';
    default:
      return type;
  }
}
