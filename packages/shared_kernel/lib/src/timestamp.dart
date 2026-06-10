import 'package:equatable/equatable.dart';

class DomainTimestamp extends Equatable {
  final DateTime value;

  const DomainTimestamp(this.value);

  @override
  List<Object?> get props => [value];
}
