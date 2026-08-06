/// Parametrized contract/parity suite for [RateFeed].
///
/// Runs the SAME behavioral contract against:
///   - [InMemoryRateFeed] (reference implementation)
///   - [HttpRateFeed]     (HTTP adapter, network mocked via [MockClient] —
///     zero real network in tests, ADR-0020 §1)
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_feed.dart';
import 'package:tasas/infrastructure/http/http_rate_feed.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_feed.dart';
import 'package:test/test.dart';

final _fixture = File('test/fixtures/rates.ndjson').readAsStringSync();

typedef _Factory = RateFeed Function(String ndjson);

void _runContractSuite(String label, _Factory makeFeed) {
  group('RateFeed contract [$label]', () {
    test('fetch returns every observation the feed contains', () async {
      final feed = makeFeed(_fixture);

      final observations = await feed.fetch();

      expect(observations, hasLength(4));
      final paralelo = observations.firstWhere(
        (o) => o.source == 'dolarapi:paralelo',
      );
      expect(paralelo.currency, CurrencyCode('VES'));
      expect(paralelo.nativePerUsd.toString(), '834.370612');
    });

    test('fetch returns an empty list for an empty feed', () async {
      final feed = makeFeed('');
      expect(await feed.fetch(), isEmpty);
    });
  });
}

void main() {
  _runContractSuite('InMemoryRateFeed', (ndjson) => InMemoryRateFeed(ndjson));

  _runContractSuite(
    'HttpRateFeed',
    (ndjson) => HttpRateFeed(
      client: MockClient((request) async => http.Response(ndjson, 200)),
    ),
  );

  group('HttpRateFeed failure modes (ADR-0020 §6 — fail silent)', () {
    test('returns an empty list on a non-200 response', () async {
      final feed = HttpRateFeed(
        client: MockClient((request) async => http.Response('', 404)),
      );
      expect(await feed.fetch(), isEmpty);
    });

    test('returns an empty list when the request throws', () async {
      final feed = HttpRateFeed(
        client: MockClient(
          (request) async => throw const SocketException('unreachable'),
        ),
      );
      expect(await feed.fetch(), isEmpty);
    });

    test(
      'returns an empty list when the request exceeds the timeout',
      () async {
        final feed = HttpRateFeed(
          timeout: const Duration(milliseconds: 20),
          client: MockClient((request) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return http.Response(_fixture, 200);
          }),
        );
        expect(await feed.fetch(), isEmpty);
      },
    );
  });
}
