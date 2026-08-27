import '../domain/ports/cloud_folder.dart';

/// In-memory [CloudFolder] backed by a [Map] — reference implementation for
/// tests, web and dev, never unavailable.
class InMemoryCloudFolder implements CloudFolder {
  final Map<String, String> _storage;

  InMemoryCloudFolder([Map<String, String>? storage])
    : _storage = storage ?? {};

  @override
  Future<List<String>> list() async => _storage.keys.toList();

  @override
  Future<String?> read(String name) async => _storage[name];

  @override
  Future<void> write(String name, String content) async {
    _storage[name] = content;
  }
}
