import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

class LogFilters extends Equatable {
  final AccountId? account;
  final EnvelopeId? envelope;
  final DomainTimestamp? from;
  final DomainTimestamp? to;

  const LogFilters({this.account, this.envelope, this.from, this.to});

  @override
  List<Object?> get props => [account, envelope, from, to];
}
