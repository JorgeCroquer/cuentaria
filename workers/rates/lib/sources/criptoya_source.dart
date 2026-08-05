import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

import 'rate_source.dart';

class CriptoYaSource implements RateSource {
  static final _uri = Uri.parse(
    'https://criptoya.com/api/binancep2p/usdt/ves/1',
  );

  final http.Client _client;

  CriptoYaSource(this._client);

  @override
  Future<List<RateObservation>> fetch() async {
    try {
      final response = await _client.get(_uri);
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final observedAt = DateTime.fromMillisecondsSinceEpoch(
        (body['time'] as num).toInt() * 1000,
        isUtc: true,
      );
      return [
        _toObservation('ask', body['ask'], observedAt),
        _toObservation('bid', body['bid'], observedAt),
      ];
    } catch (_) {
      return [];
    }
  }

  RateObservation _toObservation(
    String key,
    Object? value,
    DateTime observedAt,
  ) {
    return RateObservation(
      currency: CurrencyCode('VES'),
      source: 'binancep2p:$key',
      nativePerUsd: Decimal.parse(value.toString()),
      observedAt: observedAt,
    );
  }
}
