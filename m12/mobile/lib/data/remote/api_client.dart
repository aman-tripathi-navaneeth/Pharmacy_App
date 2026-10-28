import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth_session.dart';

sealed class ApiException implements Exception {
  const ApiException(this.code, this.message);
  final String code;

  /// Safe to show to the shop user.
  final String message;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// Connection failure or timeout. A timeout does NOT prove the server failed:
/// the request may have committed, so retries must reuse the same key.
class ApiNetworkException extends ApiException {
  const ApiNetworkException(super.code, super.message, {required this.isTimeout});
  final bool isTimeout;
}

class ApiHttpException extends ApiException {
  const ApiHttpException(this.statusCode, super.code, super.message, {this.retryAfter, this.requestId});
  final int statusCode;
  final Duration? retryAfter;
  final String? requestId;

  bool get isAuthProblem => statusCode == 401 || statusCode == 403;
  bool get isRetryable => statusCode == 408 || statusCode == 429 || statusCode >= 500;
}

/// Shared HTTP client for Member 12 APIs: bearer token, request id, timeouts
/// (spec §12: 15–30 s) and mapping of the server's `{ error: {...} }` shape.
class ApiClient {
  ApiClient({required String baseUrl, required AuthSession session, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 25),
              contentType: Headers.jsonContentType,
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await session.accessToken();
          if (token != null) options.headers['authorization'] = 'Bearer $token';
          options.headers['x-request-id'] = const Uuid().v4();
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _send(() => _dio.get<Map<String, dynamic>>(path, queryParameters: queryParameters));

  /// Raw bytes (e.g. an attachment download).
  Future<List<int>> getBytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
      return res.data ?? const [];
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Conditional GET: returns null on 304 Not Modified.
  Future<Map<String, dynamic>?> getOrNotModified(String path, {String? etag}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        path,
        options: Options(
          headers: {'if-none-match': ?etag},
          validateStatus: (s) => s != null && ((s >= 200 && s < 300) || s == 304),
        ),
      );
      return res.statusCode == 304 ? null : (res.data ?? const {});
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, dynamic>> post(String path, {Object? data}) =>
      _send(() => _dio.post<Map<String, dynamic>>(path, data: data));

  /// Multipart upload of a single file under the form field `file`.
  Future<Map<String, dynamic>> upload(
    String path, {
    required List<int> bytes,
    required String fileName,
    Map<String, String> fields = const {},
  }) => _send(
    () => _dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap({...fields, 'file': MultipartFile.fromBytes(bytes, filename: fileName)}),
      options: Options(sendTimeout: const Duration(seconds: 60)),
    ),
  );

  Future<Map<String, dynamic>> patch(String path, {Object? data}) =>
      _send(() => _dio.patch<Map<String, dynamic>>(path, data: data));

  Future<Map<String, dynamic>> _send(Future<Response<Map<String, dynamic>>> Function() call) async {
    try {
      final res = await call();
      return res.data ?? const {};
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  ApiException _map(DioException e) {
    final res = e.response;
    if (res == null) {
      final timeout =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      return ApiNetworkException(
        timeout ? 'NETWORK_TIMEOUT' : 'NETWORK_UNAVAILABLE',
        timeout ? 'Network timed out. Safe to retry.' : 'Could not reach the server. Safe to retry.',
        isTimeout: timeout,
      );
    }
    final err = (res.data is Map ? (res.data as Map)['error'] : null) as Map?;
    final retryAfterHeader = int.tryParse(res.headers.value('retry-after') ?? '');
    return ApiHttpException(
      res.statusCode ?? 0,
      err?['code'] as String? ?? 'HTTP_${res.statusCode}',
      err?['message'] as String? ?? 'The server returned an error (${res.statusCode}).',
      retryAfter: retryAfterHeader == null ? null : Duration(seconds: retryAfterHeader),
      requestId: err?['requestId'] as String?,
    );
  }
}
