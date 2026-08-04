/// Thrown when a quick-add use case needs an observed parallel Rate for a
/// foreign currency Account and none has been recorded (U1, #97/#119).
/// Shared by [QuickAddExpenseUseCase] and [QuickAddIncomeUseCase] so both
/// map to the same human-facing copy in the capture sheet (#112/#121).
class RateNotAvailable implements Exception {
  final String message;
  RateNotAvailable(this.message);

  @override
  String toString() => 'RateNotAvailable: $message';
}
