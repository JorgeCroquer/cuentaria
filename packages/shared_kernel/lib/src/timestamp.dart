import 'package:equatable/equatable.dart';

class DomainTimestamp extends Equatable {
  final DateTime value;

  DomainTimestamp(this.value) {
    if (!value.isUtc) {
      throw ArgumentError('DomainTimestamp requires a UTC DateTime');
    }
  }

  @override
  List<Object?> get props => [value];
}
