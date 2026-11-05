import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-User-Id': AppConfig.userId,
    'X-User-Role': AppConfig.role,
    'X-Store-Ids': AppConfig.storeId,
  };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('${AppConfig.baseUrl}$path');
    return query == null || query.isEmpty
        ? uri
        : uri.replace(queryParameters: query);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, {Object? body}) => _send(
    () =>
        _http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})),
  );

  Future<dynamic> put(String path, {Object? body}) => _send(
    () =>
        _http.put(_uri(path), headers: _headers, body: jsonEncode(body ?? {})),
  );

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException(
        'The server took too long to respond. Check your connection and retry.',
      );
    } catch (_) {
      throw ApiException(
        'Cannot reach the server. Check your connection and retry.',
      );
    }

    final dynamic data = res.body.isEmpty
        ? null
        : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw ApiException(_errorMessage(data), statusCode: res.statusCode);
  }

  String _errorMessage(dynamic data) {
    if (data is Map && data['detail'] is String)
      return data['detail'] as String;
    if (data is Map && data['detail'] is List) {
      final msgs = (data['detail'] as List)
          .map((e) => e is Map ? e['msg']?.toString() : null)
          .whereType<String>();
      if (msgs.isNotEmpty) return msgs.join('\n');
    }
    return 'Something went wrong. Try again.';
  }
}
