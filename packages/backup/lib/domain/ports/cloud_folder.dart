/// Port for the user's own cloud folder (ADR-0023 §8): a remote place to
/// list, read and write named files, with no notion of sessions, cursors
/// or events — those belong to the adapter, not the port.
abstract class CloudFolder {
  /// Names of every file currently in the folder.
  Future<List<String>> list();

  /// Contents of [name], or null if no such file exists.
  Future<String?> read(String name);

  /// Writes [content] to [name], overwriting it if it already exists.
  Future<void> write(String name, String content);
}

/// The single error a [CloudFolder] adapter can raise — a provider failure
/// (expired session, no network, quota) translated to one nameable [reason]
/// so a caller can show it without knowing the provider (ADR-0023 §8).
class CloudUnavailable implements Exception {
  final String reason;

  const CloudUnavailable(this.reason);

  @override
  String toString() => 'CloudUnavailable: $reason';
}
