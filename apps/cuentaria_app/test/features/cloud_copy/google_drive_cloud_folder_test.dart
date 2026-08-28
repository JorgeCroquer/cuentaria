/// [GoogleDriveCloudFolder] over a mocked `http.Client` (issue #225): every
/// request/response shape the adapter relies on, offline and deterministic.
/// The contract suite against the real Drive API lives in
/// `google_drive_cloud_folder_contract_test.dart` — see the feature README.
library;

import 'package:backup/domain/ports/cloud_folder.dart';
import 'package:cuentaria_app/features/cloud_copy/infrastructure/google_drive_cloud_folder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloud_copy_test_support.dart';

void main() {
  test('list() reads names from appDataFolder', () async {
    final requests = <http.Request>[];
    final folder = GoogleDriveCloudFolder(
      FakeGoogleDriveSession('token-1'),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{"files":[{"name":"a.ndjson"},{"name":"b.ndjson"}]}',
          200,
        );
      }),
    );

    final names = await folder.list();

    expect(names, ['a.ndjson', 'b.ndjson']);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(requests.single.url.toString(), contains('spaces=appDataFolder'));
    expect(requests.single.headers['Authorization'], 'Bearer token-1');
  });

  test('read() returns null when no file matches the name', () async {
    final folder = GoogleDriveCloudFolder(
      FakeGoogleDriveSession('token-1'),
      client: MockClient((request) async {
        return http.Response('{"files":[]}', 200);
      }),
    );

    expect(await folder.read('missing.ndjson'), isNull);
  });

  test('read() finds the id by name then downloads its media', () async {
    final requests = <http.Request>[];
    final folder = GoogleDriveCloudFolder(
      FakeGoogleDriveSession('token-1'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.queryParameters.containsKey('q')) {
          return http.Response('{"files":[{"id":"file-1"}]}', 200);
        }
        return http.Response('hola mundo', 200);
      }),
    );

    final content = await folder.read('a.ndjson');

    expect(content, 'hola mundo');
    expect(requests, hasLength(2));
    expect(requests[1].url.toString(), contains('/files/file-1?alt=media'));
  });

  test('write() creates the file then uploads its content when new', () async {
    final requests = <http.Request>[];
    final folder = GoogleDriveCloudFolder(
      FakeGoogleDriveSession('token-1'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response('{"files":[]}', 200);
        }
        if (request.method == 'POST') {
          return http.Response('{"id":"new-file"}', 200);
        }
        return http.Response('', 200);
      }),
    );

    await folder.write('a.ndjson', 'contenido');

    expect(requests.map((r) => r.method), ['GET', 'POST', 'PATCH']);
    expect(requests[1].body, contains('"name":"a.ndjson"'));
    expect(requests[1].body, contains('"appDataFolder"'));
    expect(requests[2].url.toString(), contains('/files/new-file'));
    expect(requests[2].url.toString(), contains('uploadType=media'));
    expect(requests[2].body, 'contenido');
  });

  test(
    'write() overwrites content in place when the file already exists',
    () async {
      final requests = <http.Request>[];
      final folder = GoogleDriveCloudFolder(
        FakeGoogleDriveSession('token-1'),
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response('{"files":[{"id":"existing"}]}', 200);
          }
          return http.Response('', 200);
        }),
      );

      await folder.write('a.ndjson', 'segundo');

      expect(requests.map((r) => r.method), ['GET', 'PATCH']);
      expect(requests[1].url.toString(), contains('/files/existing'));
    },
  );

  test(
    'a 401 disconnects the session and reports "sin sesión de Google"',
    () async {
      final session = FakeGoogleDriveSession('token-1');
      final folder = GoogleDriveCloudFolder(
        session,
        client: MockClient((request) async => http.Response('', 401)),
      );

      await expectLater(
        folder.list(),
        throwsA(
          isA<CloudUnavailable>().having(
            (e) => e.reason,
            'reason',
            'sin sesión de Google',
          ),
        ),
      );
      expect(session.disconnectCalled, isTrue);
    },
  );

  test(
    'no session reports "sin sesión de Google" without any request',
    () async {
      var called = false;
      final folder = GoogleDriveCloudFolder(
        FakeGoogleDriveSession(),
        client: MockClient((request) async {
          called = true;
          return http.Response('', 200);
        }),
      );

      await expectLater(
        folder.list(),
        throwsA(
          isA<CloudUnavailable>().having(
            (e) => e.reason,
            'reason',
            'sin sesión de Google',
          ),
        ),
      );
      expect(called, isFalse);
    },
  );

  test('a network failure reports "sin internet"', () async {
    final folder = GoogleDriveCloudFolder(
      FakeGoogleDriveSession('token-1'),
      client: MockClient((request) async {
        throw http.ClientException('Failed host lookup');
      }),
    );

    await expectLater(
      folder.list(),
      throwsA(
        isA<CloudUnavailable>().having(
          (e) => e.reason,
          'reason',
          'sin internet',
        ),
      ),
    );
  });

  test('any other error status reports it verbatim', () async {
    final folder = GoogleDriveCloudFolder(
      FakeGoogleDriveSession('token-1'),
      client: MockClient((request) async => http.Response('', 500)),
    );

    await expectLater(
      folder.list(),
      throwsA(
        isA<CloudUnavailable>().having(
          (e) => e.reason,
          'reason',
          contains('500'),
        ),
      ),
    );
  });
}
