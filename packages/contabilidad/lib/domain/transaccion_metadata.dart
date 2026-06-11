import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

class TransaccionMetadata extends Equatable {
  final EventId eventId;
  final String tipo;
  final DomainTimestamp occurredAt;
  final DomainTimestamp recordedAt;
  final String deviceId;
  final String? source;
  final EventId? reverses;
  final String? memo;
  final int schemaVersion;

  const TransaccionMetadata({
    required this.eventId,
    required this.tipo,
    required this.occurredAt,
    required this.recordedAt,
    required this.deviceId,
    this.source,
    this.reverses,
    this.memo,
    required this.schemaVersion,
  });

  @override
  List<Object?> get props => [
    eventId,
    tipo,
    occurredAt,
    recordedAt,
    deviceId,
    source,
    reverses,
    memo,
    schemaVersion,
  ];
}
