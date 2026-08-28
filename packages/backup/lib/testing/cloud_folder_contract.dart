/// Parametrized contract suite for [CloudFolder] (ADR-0023 §8).
///
/// Any adapter — in-memory, Google Drive, or a future provider — runs this
/// suite unchanged by passing a factory that returns a fresh instance.
library;

import 'package:test/test.dart';

import '../domain/ports/cloud_folder.dart';

/// Runs the full [CloudFolder] contract against [makeFolder]. [tags] is
/// forwarded to every test — e.g. so a real-provider adapter can tag its
/// run `google_drive` and stay opted out of default `flutter test` runs.
void cloudFolderContractTests(
  CloudFolder Function() makeFolder, {
  List<String> tags = const [],
}) {
  late CloudFolder folder;

  setUp(() {
    folder = makeFolder();
  });

  test('write then list then read round-trips the content', () async {
    await folder.write('a.ndjson', 'hola mundo');

    expect(await folder.list(), contains('a.ndjson'));
    expect(await folder.read('a.ndjson'), 'hola mundo');
  }, tags: tags);

  test('writing the same name twice leaves a single file with the last '
      'content', () async {
    await folder.write('a.ndjson', 'primero');
    await folder.write('a.ndjson', 'segundo');

    expect(await folder.list(), ['a.ndjson']);
    expect(await folder.read('a.ndjson'), 'segundo');
  }, tags: tags);

  test('reading a name that was never written returns null', () async {
    expect(await folder.read('no-existe.ndjson'), isNull);
  }, tags: tags);

  test('names with dashes, dots and UUIDs survive intact', () async {
    const name = '4f6c9f2e-9c1a-4c9e-8b0a-1e2d3c4b5a6f-device.ndjson';
    await folder.write(name, 'x');

    expect(await folder.list(), contains(name));
    expect(await folder.read(name), 'x');
  }, tags: tags);

  test(
    'multi-MB content with newlines round-trips character for character',
    () async {
      final line = '{"kind":"event","data":"${'x' * 1000}"}\n';
      final content = line * 3000; // ~3 MB

      await folder.write('big.ndjson', content);

      expect(await folder.read('big.ndjson'), content);
    },
    tags: tags,
  );
}
