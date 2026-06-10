import 'package:equatable/equatable.dart';
import 'currency_code.dart';

class Money extends Equatable {
  final BigInt amount;
  final CurrencyCode currency;

  const Money({
    required this.amount,
    required this.currency,
  });

  Money add(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('Cannot add money with different currencies');
    }
    return Money(
      amount: amount + other.amount,
      currency: currency,
    );
  }

  Money subtract(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('Cannot subtract money with different currencies');
    }
    return Money(
      amount: amount - other.amount,
      currency: currency,
    );
  }

  @override
  List<Object?> get props => [amount, currency];
}
