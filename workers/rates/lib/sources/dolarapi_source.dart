import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

import 'rate_source.dart';

class DolarApiSource implements RateSource {
  static final _uri = Uri.parse('https://ve.dolarapi.com/v1/dolares');

  final http.Client _client;

  DolarApiSource(this._client);

  @override
  Future<List<RateObservation>> fetch() async {
    try {
      final response = await _client.get(_uri);
      if (response.statusCode != 200) return [];

      final entries =
          (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
      return entries
          .where((entry) => entry['moneda'] == 'USD')
          .map(_toObservation)
          .toList();
    } catch (_) {
      return [];
    }
  }

  RateObservation _toObservation(Map<String, dynamic> entry) {
    return RateObservation(
      currency: CurrencyCode('VES'),
      source: 'dolarapi:${entry['fuente']}',
      nativePerUsd: Decimal.parse(entry['promedio'].toString()),
      observedAt: DateTime.parse(entry['fechaActualizacion'] as String),
    );
  }
}
