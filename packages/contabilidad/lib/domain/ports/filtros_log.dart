import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

class FiltrosLog extends Equatable {
  final AccountId? cuenta;
  final EnvelopeId? sobre;
  final DomainTimestamp? desde;
  final DomainTimestamp? hasta;

  const FiltrosLog({
    this.cuenta,
    this.sobre,
    this.desde,
    this.hasta,
  });

  @override
  List<Object?> get props => [cuenta, sobre, desde, hasta];
}
