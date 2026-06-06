import 'package:dio/dio.dart';

/// Shared Dio instance for TMDB catalog calls. Reuses one HTTP client across
/// the app (better connection pooling) and retries transient errors —
/// `Connection reset by peer`, TLS hiccups, timeouts. Without this every
/// detail page open is a fresh socket and a single drop kills the request,
/// which is what made some show/movie detail pages fail to load on TV.
class TmdbClient {
  TmdbClient._() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
      ),
    );
    _dio.interceptors.add(_retryInterceptor());
  }

  static final TmdbClient instance = TmdbClient._();
  late final Dio _dio;
  Dio get dio => _dio;

  static const _maxAttempts = 4;
  static const _baseBackoff = Duration(milliseconds: 350);

  Interceptor _retryInterceptor() {
    return InterceptorsWrapper(
      onError: (e, handler) async {
        final status = e.response?.statusCode ?? 0;
        // Retry transport-level drops AND transient server answers: 429 (rate
        // limited — common with the shared TMDB key) and 5xx. Other 4xx are
        // legitimate answers (e.g. 404) and shouldn't be hammered.
        final retriable = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            (e.type == DioExceptionType.badResponse &&
                (status == 429 || status >= 500));
        if (!retriable) return handler.next(e);

        final attempt = (e.requestOptions.extra['retryAttempt'] as int?) ?? 0;
        if (attempt >= _maxAttempts - 1) return handler.next(e);

        // Honour Retry-After (seconds) when present — 429s often send it —
        // capped so the UI never stalls; otherwise exponential backoff.
        Duration delay = _baseBackoff * (1 << attempt);
        final retryAfter =
            int.tryParse(e.response?.headers.value('retry-after') ?? '');
        if (retryAfter != null && retryAfter > 0) {
          delay = Duration(seconds: retryAfter.clamp(1, 5));
        }
        await Future.delayed(delay);

        try {
          final retried = await _dio.fetch(
            e.requestOptions..extra['retryAttempt'] = attempt + 1,
          );
          return handler.resolve(retried);
        } catch (err) {
          if (err is DioException) return handler.next(err);
          return handler.next(e);
        }
      },
    );
  }
}

/// Convenience getter — `tmdbDio.get(url)` reads cleaner than
/// `TmdbClient.instance.dio.get(url)` at call sites.
Dio get tmdbDio => TmdbClient.instance.dio;
