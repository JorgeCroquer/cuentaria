import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:shared_kernel/shared_kernel.dart';

class InMemoryCatalogRepository implements CatalogRepository {
  final Map<AccountId, Account> _accounts = {};
  final Map<EnvelopeId, Envelope> _envelopes = {};

  InMemoryCatalogRepository() {
    _seedSystemEnvelopes();
  }

  void _seedSystemEnvelopes() {
    final now = DateTime.now();
    const systemRoles = {
      EnvelopeRole.stage: ('Stage', 'sys-stage'),
      EnvelopeRole.differential: ('Differential', 'sys-differential'),
      EnvelopeRole.adjustments: ('Adjustments', 'sys-adjustments'),
      EnvelopeRole.opening: ('Opening', 'sys-opening'),
    };

    for (final entry in systemRoles.entries) {
      final role = entry.key;
      final name = entry.value.$1;
      final id = EnvelopeId(entry.value.$2);

      final hasRole = _envelopes.values.any((e) => e.role == role);
      if (!hasRole) {
        _saveEnvelopeSync(
          Envelope(
            id: id,
            name: name,
            role: role,
            isArchived: false,
            updatedAt: now,
          ),
        );
      }
    }
  }

  void _saveEnvelopeSync(Envelope envelope) {
    final existing = _envelopes[envelope.id];
    if (existing != null) {
      _envelopes[envelope.id] = existing.mergeWith(envelope);
    } else {
      _envelopes[envelope.id] = envelope;
    }
  }

  @override
  Iterable<AccountId> get accountIds => _accounts.keys;

  @override
  Iterable<Account> get accounts => _accounts.values;

  @override
  Iterable<Envelope> get envelopes => _envelopes.values;

  @override
  Account? getAccount(AccountId id) => _accounts[id];

  @override
  Envelope? getEnvelope(EnvelopeId id) => _envelopes[id];

  @override
  EnvelopeId getSystemEnvelope(EnvelopeRole role) {
    if (role == EnvelopeRole.none) {
      throw ArgumentError('Role none is not a system envelope');
    }
    final envelope = _envelopes.values.firstWhere(
      (e) => e.role == role,
      orElse:
          () =>
              throw TargetNotFound('System envelope for role $role not found'),
    );
    return envelope.id;
  }

  @override
  Future<void> saveAccount(Account account) async {
    final existing = _accounts[account.id];
    if (existing != null) {
      _accounts[account.id] = existing.mergeWith(account);
    } else {
      _accounts[account.id] = account;
    }
  }

  @override
  Future<void> saveEnvelope(Envelope envelope) async {
    _saveEnvelopeSync(envelope);
  }

  @override
  Future<void> deleteAccount(AccountId id) async {
    _accounts.remove(id);
  }

  @override
  Future<void> deleteEnvelope(EnvelopeId id) async {
    final envelope = _envelopes[id];
    if (envelope != null && envelope.role != EnvelopeRole.none) {
      throw SystemEnvelopeDeletionNotAllowed(
        'Cannot delete system envelope ${envelope.role.name}',
      );
    }
    _envelopes.remove(id);
  }
}
