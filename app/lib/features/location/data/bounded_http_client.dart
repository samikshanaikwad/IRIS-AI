import 'dart:async';
import 'package:http/http.dart' as http;

/// Enforces transfer limits before buffering, including when a server ignores
/// Range. Closing this client also cancels requests on timeout.
class BoundedHttpClient extends http.BaseClient {
  BoundedHttpClient({
    http.Client? inner,
    this.maxBytes = 12 * 1024 * 1024,
    this.timeout = const Duration(seconds: 20),
  }) : _inner = inner ?? http.Client();
  final http.Client _inner;
  final int maxBytes;
  final Duration timeout;
  int transferred = 0;
  final Stopwatch _elapsed = Stopwatch()..start();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final remaining = const Duration(seconds: 60) - _elapsed.elapsed;
    if (remaining <= Duration.zero) {
      close();
      throw TimeoutException('Environment request time budget exceeded');
    }
    final limit = remaining < timeout ? remaining : timeout;
    request.headers['User-Agent'] =
        'IRIS/1.0 (Android; bounded case environment research)';
    final response = await _inner
        .send(request)
        .timeout(
          limit,
          onTimeout: () {
            close();
            throw TimeoutException('Environment request timed out');
          },
        );
    final ranged =
        request.headers.containsKey('Range') ||
        request.headers.containsKey('range');
    if (ranged && response.statusCode != 206) {
      await response.stream.listen((_) {}).cancel();
      throw http.ClientException(
        'Range unavailable: HTTP ${response.statusCode}',
      );
    }
    final parts = <int>[];
    await for (final chunk in response.stream.timeout(timeout)) {
      transferred += chunk.length;
      if (transferred > maxBytes) {
        _inner.close();
        throw http.ClientException('Environment transfer budget exceeded');
      }
      parts.addAll(chunk);
    }
    return http.StreamedResponse(
      Stream.value(parts),
      response.statusCode,
      headers: response.headers,
      request: request,
      contentLength: parts.length,
    );
  }

  @override
  void close() => _inner.close();
}
