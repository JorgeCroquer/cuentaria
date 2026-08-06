import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rates/sources/criptoya_source.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('CriptoYaSource', () {
    test('maps the fixture to ask and bid observations', () async {
      final fixture =
          File('test/fixtures/criptoya_response.json').readAsStringSync();
      final client = MockClient((request) async {
        expect(
          request.url,
          Uri.parse('https://criptoya.com/api/binancep2p/usdt/ves/1'),
        );
        return http.Response(fixture, 200);
      });

      final observations = await CriptoYaSource(client).fetch();

      expect(observations, hasLength(2));

      final ask = observations.firstWhere((o) => o.source == 'binancep2p:ask');
      expect(ask.currency, CurrencyCode('VES'));
      expect(ask.nativePerUsd, Decimal.parse('845.88'));
      expect(
        ask.observedAt,
        DateTime.fromMillisecondsSinceEpoch(1785959800 * 1000, isUtc: true),
      );

      final bid = observations.firstWhere((o) => o.source == 'binancep2p:bid');
      expect(bid.nativePerUsd, Decimal.parse('844.815'));
      expect(
        bid.observedAt,
        DateTime.fromMillisecondsSinceEpoch(1785959800 * 1000, isUtc: true),
      );
    });

    test('returns an empty list when the request fails', () async {
      final client = MockClient((request) async {
        return http.Response('error', 500);
      });

      final observations = await CriptoYaSource(client).fetch();

      expect(observations, isEmpty);
    });

    test('returns an empty list when the request throws', () async {
      final client = MockClient((request) async {
        throw const SocketException('unreachable');
      });

      final observations = await CriptoYaSource(client).fetch();

      expect(observations, isEmpty);
    });
  });
}
