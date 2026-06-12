import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';

class RegistrarReverso {
  final RegistrarTransaccion _registrar;
  final EventStore _store;

  RegistrarReverso({
    required RegistrarTransaccion registrar,
    required EventStore store,
  })  : _registrar = registrar,
        _store = store;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required EventId originalEventId,
    DomainTimestamp? occurredAt,
  }) async {
    final original = await _store.get(originalEventId);
    if (original == null) {
      throw TransaccionNoEncontrada('No se encontró la transacción original: $originalEventId');
    }

    if (await _store.hasReversal(originalEventId)) {
      throw TransaccionYaReversada('La transacción ya ha sido reversada: $originalEventId');
    }

    final invertedPostings = original.postings.map((p) {
      return Posting(
        target: p.target,
        amountNative: Money(
          amount: -p.amountNative.amount,
          currency: p.amountNative.currency,
        ),
        currency: p.currency,
        amountUsd: -p.amountUsd,
        rateRef: p.rateRef,
      );
    }).toList();

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'Reverso',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
      reverses: originalEventId,
    );

    await _registrar(postings: invertedPostings, metadata: metadata);
  }
}
