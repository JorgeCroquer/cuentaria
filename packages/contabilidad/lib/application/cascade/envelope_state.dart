/// Input state for a single envelope passed to [CascadeEngine].
/// Decoupled from the catalog — the orchestrator assembles this.
class EnvelopeState {
  final int balanceUsd;
  final int? capUsd;

  const EnvelopeState({required this.balanceUsd, this.capUsd});
}
