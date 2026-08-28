import 'dart:convert';
import 'dart:io';

import 'package:backup/domain/ports/cloud_folder.dart';
import 'package:http/http.dart' as http;

import '../application/google_drive_session.dart';

const _filesEndpoint = 'https://www.googleapis.com/drive/v3/files';
const _uploadEndpoint = 'https://www.googleapis.com/upload/drive/v3/files';

/// [CloudFolder] over Google Drive's `appDataFolder` (issue #225,
/// ADR-0023 §8): `list`/`read`/`write` map to the Drive API v3 `files`
/// resource, scoped by [GoogleDriveSession]'s bearer token. A file is
/// created once (metadata `POST`, so it gets a name and lands in
/// `appDataFolder`) then every `write` after that overwrites its content
/// (`uploadType=media` `PATCH`) — matches the contract's "last write wins",
/// never a second file with the same name.
class GoogleDriveCloudFolder implements CloudFolder {
  GoogleDriveCloudFolder(this._session, {http.Client? client})
    : _client = client ?? http.Client();

  final GoogleDriveSession _session;
  final http.Client _client;

  @override
  Future<List<String>> list() async {
    final response = await _get(
      Uri.parse(
        '$_filesEndpoint?spaces=appDataFolder&fields=files(name)&pageSize=1000',
      ),
    );
    final files = _filesFrom(response);
    return files.map((f) => f['name'] as String).toList();
  }

  @override
  Future<String?> read(String name) async {
    final id = await _findFileId(name);
    if (id == null) return null;
    final response = await _get(Uri.parse('$_filesEndpoint/$id?alt=media'));
    return response.body;
  }

  @override
  Future<void> write(String name, String content) async {
    final id = await _findFileId(name) ?? await _createFile(name);
    await _send(
      'PATCH',
      Uri.parse('$_uploadEndpoint/$id?uploadType=media'),
      body: content,
      contentType: 'text/plain; charset=utf-8',
    );
  }

  Future<String?> _findFileId(String name) async {
    final response = await _get(
      Uri.parse(
        "$_filesEndpoint?spaces=appDataFolder&q=name='${_escapeQueryValue(name)}'&fields=files(id)",
      ),
    );
    final files = _filesFrom(response);
    if (files.isEmpty) return null;
    return files.first['id'] as String;
  }

  Future<String> _createFile(String name) async {
    final response = await _send(
      'POST',
      Uri.parse(_filesEndpoint),
      body: jsonEncode({
        'name': name,
        'parents': ['appDataFolder'],
      }),
      contentType: 'application/json',
    );
    return jsonDecode(response.body)['id'] as String;
  }

  List<Map<String, dynamic>> _filesFrom(http.Response response) =>
      ((jsonDecode(response.body)['files'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  Future<http.Response> _get(Uri uri) => _send('GET', uri);

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Object? body,
    String? contentType,
  }) async {
    final token = await _session.accessToken();
    final headers = {
      'Authorization': 'Bearer $token',
      if (contentType != null) 'Content-Type': contentType,
    };
    http.Response response;
    try {
      response = switch (method) {
        'GET' => await _client.get(uri, headers: headers),
        'POST' => await _client.post(uri, headers: headers, body: body),
        'PATCH' => await _client.patch(uri, headers: headers, body: body),
        _ => throw UnsupportedError(method),
      };
    } on SocketException {
      throw const CloudUnavailable('sin internet');
    } on http.ClientException {
      throw const CloudUnavailable('sin internet');
    }
    if (response.statusCode == 401) {
      await _session.disconnect();
      throw const CloudUnavailable('sin sesión de Google');
    }
    if (response.statusCode >= 400) {
      throw CloudUnavailable('Google Drive: ${response.statusCode}');
    }
    return response;
  }

  static String _escapeQueryValue(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}
