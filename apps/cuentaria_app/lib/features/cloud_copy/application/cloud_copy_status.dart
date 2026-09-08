/// Observable status of [CloudCopyUseCase] (issue #222, ADR-0023 §4): what
/// the "Copia en Drive: hace N" / "falló hace N: causa" label needs.
/// [lastSuccessAt] and [lastError] are persisted (`CloudCopyStatusStore`);
/// [lastAttemptAt], [inProgress] and [waitingForMergeConsent] are
/// session-only, reset on every launch — [waitingForMergeConsent] is
/// recomputed by `CloudCopyUseCase.sync()` on every call (issue #297,
/// ADR-0023 §6): the merge gate holding `sync()` back until the user
/// decides.
class CloudCopyStatus {
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final bool inProgress;
  final bool waitingForMergeConsent;

  const CloudCopyStatus({
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.lastError,
    this.inProgress = false,
    this.waitingForMergeConsent = false,
  });

  CloudCopyStatus copyWith({
    DateTime? lastSuccessAt,
    DateTime? lastAttemptAt,
    String? lastError,
    bool? inProgress,
    bool? waitingForMergeConsent,
  }) => CloudCopyStatus(
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    lastError: lastError ?? this.lastError,
    inProgress: inProgress ?? this.inProgress,
    waitingForMergeConsent:
        waitingForMergeConsent ?? this.waitingForMergeConsent,
  );
}
