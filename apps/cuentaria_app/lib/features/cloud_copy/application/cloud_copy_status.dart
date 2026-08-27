/// Observable status of [CloudCopyUseCase] (issue #222, ADR-0023 §4): what
/// the "Copia en Drive: hace N" / "falló hace N: causa" label needs.
/// [lastSuccessAt] and [lastError] are persisted (`CloudCopyStatusStore`);
/// [lastAttemptAt] and [inProgress] are session-only, reset on every launch.
class CloudCopyStatus {
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final bool inProgress;

  const CloudCopyStatus({
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.lastError,
    this.inProgress = false,
  });

  CloudCopyStatus copyWith({
    DateTime? lastSuccessAt,
    DateTime? lastAttemptAt,
    String? lastError,
    bool? inProgress,
  }) => CloudCopyStatus(
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    lastError: lastError ?? this.lastError,
    inProgress: inProgress ?? this.inProgress,
  );
}
