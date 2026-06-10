import 'package:equatable/equatable.dart';

abstract class DomainId extends Equatable {
  final String value;

  DomainId(this.value) {
    if (value.trim().isEmpty) {
      throw ArgumentError('ID value cannot be empty');
    }
  }

  @override
  List<Object?> get props => [value];
}

class AccountId extends DomainId {
  AccountId(super.value);
}

class EnvelopeId extends DomainId {
  EnvelopeId(super.value);
}

class EventId extends DomainId {
  EventId(super.value);
}
