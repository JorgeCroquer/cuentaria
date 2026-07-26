import 'package:equatable/equatable.dart';

class CurrencyCode extends Equatable {
  static final _pattern = RegExp(r'^[A-Z]{3}$');

  final String value;

  CurrencyCode(this.value) {
    if (!_pattern.hasMatch(value)) {
      throw ArgumentError('Currency code must be 3 uppercase letters');
    }
  }

  @override
  List<Object?> get props => [value];
}
