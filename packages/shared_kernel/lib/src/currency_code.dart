import 'package:equatable/equatable.dart';

class CurrencyCode extends Equatable {
  final String value;

  CurrencyCode(this.value) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
      throw ArgumentError('Currency code must be exactly 3 uppercase letters');
    }
  }

  @override
  List<Object?> get props => [value];
}
