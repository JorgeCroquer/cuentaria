import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

class Account extends Equatable {
  final AccountId id;
  final String name;
  final CurrencyCode nativeCurrency;
  final String? provider;
  final bool isArchived;
  final DateTime updatedAt;
  final Map<String, dynamic>? meta;

  const Account({
    required this.id,
    required this.name,
    required this.nativeCurrency,
    this.provider,
    required this.isArchived,
    required this.updatedAt,
    this.meta,
  });

  /// Theme swatch hex string tagged onto this account, stored in [meta]
  /// under the `"color"` key (FundingTarget pattern, ADR-0015).
  String? get colorHex => meta?['color'] as String?;

  /// When this account was last reconciled (C3 slice 4, #150), stored in
  /// [meta] under the `"lastReconciledAt"` key (FundingTarget pattern,
  /// ADR-0015). Null means it was never reconciled.
  DateTime? get lastReconciledAt {
    final raw = meta?['lastReconciledAt'] as String?;
    return raw == null ? null : DateTime.parse(raw);
  }

  /// Returns a copy stamped with [timestamp] as [lastReconciledAt],
  /// preserving other [meta] keys and advancing [updatedAt] so the stamp
  /// wins the catalog's Last-Write-Wins merge.
  Account withLastReconciledAt(DateTime timestamp) {
    final updatedMeta = Map<String, dynamic>.from(meta ?? {});
    updatedMeta['lastReconciledAt'] = timestamp.toUtc().toIso8601String();
    return Account(
      id: id,
      name: name,
      nativeCurrency: nativeCurrency,
      provider: provider,
      isArchived: isArchived,
      updatedAt: timestamp.toUtc(),
      meta: updatedMeta,
    );
  }

  /// Merges this account with another using Last-Write-Wins based on [updatedAt].
  /// If timestamps are exactly equal, the current instance is kept.
  Account mergeWith(Account other) {
    if (id != other.id) {
      throw ArgumentError('Cannot merge accounts with different IDs');
    }

    if (other.updatedAt.isAfter(updatedAt)) {
      return other;
    }
    return this;
  }

  @override
  List<Object?> get props => [
    id,
    name,
    nativeCurrency,
    provider,
    isArchived,
    updatedAt,
    meta,
  ];
}
