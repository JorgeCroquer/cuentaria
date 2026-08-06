import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rates/sources/dolarapi_source.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('DolarApiSource', () {
    test('maps the fixture to oficial and paralelo observations', () async {
      final fixture =
          File('test/fixtures/dolarapi_response.json').readAsStringSync();
      final client = MockClient((request) async {
        expect(request.url, Uri.parse('https://ve.dolarapi.com/v1/dolares'));
        return http.Response(fixture, 200);
      });

      final observations = await DolarApiSource(client).fetch();

      expect(observations, hasLength(2));

      final oficial = observations.firstWhere(
        (o) => o.source == 'dolarapi:oficial',
      );
      expect(oficial.currency, CurrencyCode('VES'));
      expect(oficial.nativePerUsd, Decimal.parse('755.1552'));
      expect(oficial.observedAt, DateTime.parse('2026-08-05T00:00:00-04:00'));

      final paralelo = observations.firstWhere(
        (o) => o.source == 'dolarapi:paralelo',
      );
      expect(paralelo.nativePerUsd, Decimal.parse('834.370612'));
      expect(paralelo.observedAt, DateTime.parse('2026-08-05T19:02:18.542Z'));
    });

    test('ignores non-USD entries', () async {
      final client = MockClient((request) async {
        return http.Response(
          '[{"moneda":"EUR","fuente":"oficial","promedio":900.0,'
          '"fechaActualizacion":"2026-08-05T00:00:00-04:00"}]',
          200,
        );
      });

      final observations = await DolarApiSource(client).fetch();

      expect(observations, isEmpty);
    });

    test('returns an empty list when the request fails', () async {
      final client = MockClient((request) async {
        return http.Response('error', 500);
      });

      final observations = await DolarApiSource(client).fetch();

      expect(observations, isEmpty);
    });

    test('returns an empty list when the request throws', () async {
      final client = MockClient((request) async {
        throw const SocketException('unreachable');
      });

      final observations = await DolarApiSource(client).fetch();

      expect(observations, isEmpty);
    });
  });
}
