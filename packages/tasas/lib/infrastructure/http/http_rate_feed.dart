import 'package:http/http.dart' as http;

import '../../domain/rate_feed.dart';
import '../../domain/rate_observation.dart';
import '../ndjson/ndjson_rate_store.dart';

/// Downloads the NDJSON feed the `rates` worker publishes as a GitHub
/// Release asset (ADR-0020 §1) — a public URL, no auth, no server. Fails
/// silent on any network error, timeout, or non-200 response: the app
/// never blocks or shows an error for a feed it can't reach (ADR-0020 §6),
/// it just keeps whatever it already has.
class HttpRateFeed implements RateFeed {
  static final Uri defaultUrl = Uri.parse(
    'https://github.com/JorgeCroquer/cuentaria/releases/download/rates/rates.ndjson',
  );

  final http.Client _client;
  final Uri _url;
  final Duration _timeout;

  HttpRateFeed({
    http.Client? client,
    Uri? url,
    Duration timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _url = url ?? defaultUrl,
       _timeout = timeout;

  @override
  Future<List<RateObservation>> fetch() async {
    try {
      final response = await _client.get(_url).timeout(_timeout);
      if (response.statusCode != 200) return [];
      return NdjsonRateStore.parse(response.body).observations;
    } catch (_) {
      return [];
    }
  }
}
