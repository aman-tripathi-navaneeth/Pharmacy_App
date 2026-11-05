import 'package:flutter/foundation.dart';

import 'api_client.dart';

export 'api_client.dart' show ApiException, ApiHttpException, ApiNetworkException;

/// Per-operation result returned by POST /sync/push.
enum ResultStatus { synced, alreadyProcessed, conflict, failedPermanent, retryableFailure }

ResultStatus _parseStatus(String s) => switch (s) {
  'SYNCED' => ResultStatus.synced,
  'ALREADY_PROCESSED' => ResultStatus.alreadyProcessed,
  'CONFLICT' => ResultStatus.conflict,
  'FAILED_PERMANENT' => ResultStatus.failedPermanent,
  _ => ResultStatus.retryableFailure,
};

class OperationResultDto {
  OperationResultDto({
    required this.clientOperationId,
    required this.status,
    this.serverResourceId,
    this.version,
    this.errorCode,
    this.message,
    this.conflict,
    this.retryAfter,
  });

  factory OperationResultDto.fromJson(Map<String, dynamic> j) => OperationResultDto(
    clientOperationId: j['clientOperationId'] as String,
    status: _parseStatus(j['status'] as String),
    serverResourceId: j['serverResourceId'] as String?,
    version: j['version'] as int?,
    errorCode: j['errorCode'] as String?,
    message: j['message'] as String?,
    conflict: j['conflict'] as Map<String, dynamic>?,
    retryAfter: j['retryAfterMs'] == null ? null : Duration(milliseconds: j['retryAfterMs'] as int),
  );

  final String clientOperationId;
  final ResultStatus status;
  final String? serverResourceId;
  final int? version;
  final String? errorCode;
  final String? message;
  final Map<String, dynamic>? conflict;
  final Duration? retryAfter;
}

class PushOperation {
  PushOperation({
    required this.clientOperationId,
    required this.idempotencyKey,
    required this.module,
    required this.operationType,
    required this.payload,
    this.entityId,
    this.baseVersion,
    this.dependsOn = const [],
    this.clientCreatedAt,
  });

  final String clientOperationId;
  final String idempotencyKey;
  final String module;
  final String operationType;
  final Map<String, dynamic> payload;
  final String? entityId;
  final int? baseVersion;
  final List<String> dependsOn;
  final DateTime? clientCreatedAt;

  Map<String, dynamic> toJson() => {
    'clientOperationId': clientOperationId,
    'idempotencyKey': idempotencyKey,
    'module': module,
    'operationType': operationType,
    'payload': payload,
    if (entityId != null) 'entityId': entityId,
    if (baseVersion != null) 'baseVersion': baseVersion,
    if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
    if (clientCreatedAt != null) 'clientCreatedAt': clientCreatedAt!.toUtc().toIso8601String(),
  };
}

class PullChangeDto {
  PullChangeDto.fromJson(Map<String, dynamic> j)
    : entity = j['entity'] as String,
      entityId = j['entityId'] as String,
      version = j['version'] as int,
      deleted = j['deleted'] as bool? ?? false,
      data = j['data'] as Map<String, dynamic>?;

  final String entity;
  final String entityId;
  final int version;
  final bool deleted;
  final Map<String, dynamic>? data;
}

class PullPage {
  PullPage({required this.changes, required this.nextCursor, required this.hasMore});

  final List<PullChangeDto> changes;
  final String nextCursor;
  final bool hasMore;
}

// -------------------------------------------------------------------- API

abstract interface class SyncApi {
  Future<List<OperationResultDto>> push({
    required String storeId,
    required String deviceId,
    required List<PushOperation> operations,
  });

  Future<PullPage> pull({required String storeId, required String deviceId, String? cursor, int? limit});

  Future<void> cancel({
    required String storeId,
    required String deviceId,
    required String clientOperationId,
    required String idempotencyKey,
    required String module,
    required String operationType,
  });
}

class HttpSyncApi implements SyncApi {
  HttpSyncApi(this._client);

  final ApiClient _client;

  @override
  Future<List<OperationResultDto>> push({
    required String storeId,
    required String deviceId,
    required List<PushOperation> operations,
  }) async {
    final body = await _client.post(
      '/sync/push',
      data: {
        'storeId': storeId,
        'deviceId': deviceId,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'operations': [for (final o in operations) o.toJson()],
      },
    );
    return [for (final r in body['results'] as List) OperationResultDto.fromJson(r as Map<String, dynamic>)];
  }

  @override
  Future<PullPage> pull({required String storeId, required String deviceId, String? cursor, int? limit}) async {
    final body = await _client.get(
      '/sync/pull',
      queryParameters: {'storeId': storeId, 'deviceId': deviceId, 'cursor': ?cursor, 'limit': ?limit},
    );
    return PullPage(
      changes: [for (final c in body['changes'] as List) PullChangeDto.fromJson(c as Map<String, dynamic>)],
      nextCursor: body['nextCursor'] as String,
      hasMore: body['hasMore'] as bool,
    );
  }

  @override
  Future<void> cancel({
    required String storeId,
    required String deviceId,
    required String clientOperationId,
    required String idempotencyKey,
    required String module,
    required String operationType,
  }) async {
    await _client.post(
      '/sync/operations/$clientOperationId/cancel',
      data: {
        'storeId': storeId,
        'deviceId': deviceId,
        'idempotencyKey': idempotencyKey,
        'module': module,
        'operationType': operationType,
      },
    );
  }
}
