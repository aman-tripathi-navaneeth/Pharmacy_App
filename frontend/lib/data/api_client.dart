/// API client for the Today Dashboard & Reports module (Member 11).
///
/// Talks only to the FastAPI backend under /api/v1 — never to the database directly
/// (repo rule: no database credentials or connections in frontend code).
/// DTO field names mirror backend/app/modules/today_dashboard_reports/schemas.py.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class TaskAction {
  TaskAction({required this.type, required this.label, required this.target});

  factory TaskAction.fromJson(Map<String, dynamic> json) => TaskAction(
    type: json['type'] as String? ?? '',
    label: json['label'] as String? ?? 'Open',
    target: json['target'] as String? ?? '',
  );

  final String type;
  final String label;
  final String target;
}

class Task {
  Task({
    required this.key,
    required this.category,
    required this.urgency,
    required this.score,
    required this.title,
    required this.detail,
    required this.reason,
    required this.valuePaise,
    required this.source,
    required this.action,
    required this.state,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    key: json['key'] as String,
    category: json['category'] as String,
    urgency: json['urgency'] as String,
    score: (json['score'] as num).toDouble(),
    title: json['title'] as String,
    detail: json['detail'] as String,
    reason: json['reason'] as String? ?? '',
    valuePaise: (json['value_paise'] as num?)?.toInt() ?? 0,
    source: json['source'] as String? ?? '',
    action: TaskAction.fromJson(json['action'] as Map<String, dynamic>? ?? {}),
    state: json['state'] as String? ?? 'open',
  );

  final String key;
  final String category;
  final String urgency;
  final double score;
  final String title;
  final String detail;
  final String reason;
  final int valuePaise;
  final String source;
  final TaskAction action;
  final String state;
}

class Counts {
  Counts({
    required this.urgent,
    required this.soon,
    required this.routine,
    required this.snoozed,
    required this.doneToday,
  });

  factory Counts.fromJson(Map<String, dynamic> json) => Counts(
    urgent: (json['urgent'] as num?)?.toInt() ?? 0,
    soon: (json['soon'] as num?)?.toInt() ?? 0,
    routine: (json['routine'] as num?)?.toInt() ?? 0,
    snoozed: (json['snoozed'] as num?)?.toInt() ?? 0,
    doneToday: (json['done_today'] as num?)?.toInt() ?? 0,
  );

  final int urgent;
  final int soon;
  final int routine;
  final int snoozed;
  final int doneToday;
}

/// None values mean the source is unavailable — they never mean zero.
class Glance {
  Glance({
    this.expiring30DaysValuePaise,
    this.itemsBelowMinimum,
    this.creditToCollectPaise,
  });

  factory Glance.fromJson(Map<String, dynamic> json) => Glance(
    expiring30DaysValuePaise: (json['expiring_30_days_value_paise'] as num?)
        ?.toInt(),
    itemsBelowMinimum: (json['items_below_minimum'] as num?)?.toInt(),
    creditToCollectPaise: (json['credit_to_collect_paise'] as num?)?.toInt(),
  );

  final int? expiring30DaysValuePaise;
  final int? itemsBelowMinimum;
  final int? creditToCollectPaise;
}

class SourceStatus {
  SourceStatus({required this.source, required this.ok, this.error});

  factory SourceStatus.fromJson(Map<String, dynamic> json) => SourceStatus(
    source: json['source'] as String,
    ok: json['ok'] as bool? ?? false,
    error: json['error'] as String?,
  );

  final String source;
  final bool ok;
  final String? error;
}

class TodayResponse {
  TodayResponse({
    required this.generatedAt,
    required this.counts,
    required this.glance,
    required this.tasks,
    required this.sourceStatus,
  });

  factory TodayResponse.fromJson(Map<String, dynamic> json) {
    final tasks = json['tasks'] as List<dynamic>? ?? <dynamic>[];
    final sources = json['source_status'] as List<dynamic>? ?? <dynamic>[];
    return TodayResponse(
      generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? ''),
      counts: Counts.fromJson(json['counts'] as Map<String, dynamic>? ?? {}),
      glance: Glance.fromJson(json['glance'] as Map<String, dynamic>? ?? {}),
      tasks: tasks
          .whereType<Map<String, dynamic>>()
          .map(Task.fromJson)
          .toList(),
      sourceStatus: sources
          .whereType<Map<String, dynamic>>()
          .map(SourceStatus.fromJson)
          .toList(),
    );
  }

  final DateTime? generatedAt;
  final Counts counts;
  final Glance glance;
  final List<Task> tasks;
  final List<SourceStatus> sourceStatus;

  List<SourceStatus> get failedSources =>
      sourceStatus.where((s) => !s.ok).toList();
}

class TaskStateResponse {
  TaskStateResponse({required this.taskKey, required this.status});

  factory TaskStateResponse.fromJson(Map<String, dynamic> json) =>
      TaskStateResponse(
        taskKey: json['task_key'] as String? ?? '',
        status: json['status'] as String? ?? 'open',
      );

  final String taskKey;
  final String status;
}

/// One day's confirmed figures. A null figure means 'not known yet', never zero.
class DailySummary {
  DailySummary({
    required this.summaryDate,
    required this.confirmed,
    this.note,
    this.confirmedAt,
    this.totalSalesPaise,
    this.totalPurchasesPaise,
    this.udhaarCollectedPaise,
    this.udhaarIssuedPaise,
    this.expiredStockValuePaise,
    this.lowStockSkuCount,
  });

  factory DailySummary.fromJson(Map<String, dynamic> json) => DailySummary(
    summaryDate:
        DateTime.tryParse(json['summary_date'] as String? ?? '') ??
        DateTime.now(),
    confirmed: json['confirmed'] as bool? ?? false,
    note: json['note'] as String?,
    confirmedAt: DateTime.tryParse(json['confirmed_at'] as String? ?? ''),
    totalSalesPaise: (json['total_sales_paise'] as num?)?.toInt(),
    totalPurchasesPaise: (json['total_purchases_paise'] as num?)?.toInt(),
    udhaarCollectedPaise: (json['udhaar_collected_paise'] as num?)?.toInt(),
    udhaarIssuedPaise: (json['udhaar_issued_paise'] as num?)?.toInt(),
    expiredStockValuePaise: (json['expired_stock_value_paise'] as num?)
        ?.toInt(),
    lowStockSkuCount: (json['low_stock_sku_count'] as num?)?.toInt(),
  );

  final DateTime summaryDate;
  final bool confirmed;
  final String? note;
  final DateTime? confirmedAt;
  final int? totalSalesPaise;
  final int? totalPurchasesPaise;
  final int? udhaarCollectedPaise;
  final int? udhaarIssuedPaise;
  final int? expiredStockValuePaise;
  final int? lowStockSkuCount;
}

class TrendPoint {
  TrendPoint({
    required this.summaryDate,
    this.totalSalesPaise,
    this.totalPurchasesPaise,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
    summaryDate:
        DateTime.tryParse(json['summary_date'] as String? ?? '') ??
        DateTime.now(),
    totalSalesPaise: (json['total_sales_paise'] as num?)?.toInt(),
    totalPurchasesPaise: (json['total_purchases_paise'] as num?)?.toInt(),
  );

  final DateTime summaryDate;
  final int? totalSalesPaise;
  final int? totalPurchasesPaise;
}

class TrendResponse {
  TrendResponse({required this.points, this.error});

  factory TrendResponse.fromJson(Map<String, dynamic> json) {
    final points = json['points'] as List<dynamic>? ?? <dynamic>[];
    return TrendResponse(
      points: points
          .whereType<Map<String, dynamic>>()
          .map(TrendPoint.fromJson)
          .toList(),
      error: json['error'] as String?,
    );
  }

  final List<TrendPoint> points;
  final String? error;
}

/// Current stock health. available=false means the owning module's tables are
/// not merged yet — shown as dashes, never zeros.
class StockNow {
  StockNow({
    required this.available,
    this.note,
    this.expiring30,
    this.expiring30ValuePaise,
    this.expiring60,
    this.expiring90,
    this.belowMinimum,
    this.outOfStock,
  });

  factory StockNow.fromJson(Map<String, dynamic> json) => StockNow(
    available: json['available'] as bool? ?? false,
    note: json['note'] as String?,
    expiring30: (json['expiring_30'] as num?)?.toInt(),
    expiring30ValuePaise: (json['expiring_30_value_paise'] as num?)?.toInt(),
    expiring60: (json['expiring_60'] as num?)?.toInt(),
    expiring90: (json['expiring_90'] as num?)?.toInt(),
    belowMinimum: (json['below_minimum'] as num?)?.toInt(),
    outOfStock: (json['out_of_stock'] as num?)?.toInt(),
  );

  final bool available;
  final String? note;
  final int? expiring30;
  final int? expiring30ValuePaise;
  final int? expiring60;
  final int? expiring90;
  final int? belowMinimum;
  final int? outOfStock;
}

class PurchaseLine {
  PurchaseLine({
    required this.medicine,
    this.batchNo,
    this.expiryDate,
    this.quantity,
    this.amountPaise,
  });

  factory PurchaseLine.fromJson(Map<String, dynamic> json) => PurchaseLine(
    medicine: json['medicine'] as String? ?? '',
    batchNo: json['batch_no'] as String?,
    expiryDate: DateTime.tryParse(json['expiry_date'] as String? ?? ''),
    quantity: (json['quantity'] as num?)?.toDouble(),
    amountPaise: (json['amount_paise'] as num?)?.toInt(),
  );

  final String medicine;
  final String? batchNo;
  final DateTime? expiryDate;
  final double? quantity;
  final int? amountPaise;
}

class PurchaseRegisterRow {
  PurchaseRegisterRow({
    required this.invoiceId,
    required this.invoiceNo,
    this.invoiceDate,
    this.supplier,
    required this.totalPaise,
    this.itemCount,
    this.lines,
  });

  factory PurchaseRegisterRow.fromJson(Map<String, dynamic> json) {
    final lines = json['lines'] as List<dynamic>?;
    return PurchaseRegisterRow(
      invoiceId: json['invoice_id'] as String? ?? '',
      invoiceNo: json['invoice_no'] as String? ?? '',
      invoiceDate: DateTime.tryParse(json['invoice_date'] as String? ?? ''),
      supplier: json['supplier'] as String?,
      totalPaise: (json['total_paise'] as num?)?.toInt() ?? 0,
      itemCount: (json['item_count'] as num?)?.toInt(),
      lines: lines
          ?.whereType<Map<String, dynamic>>()
          .map(PurchaseLine.fromJson)
          .toList(),
    );
  }

  final String invoiceId;
  final String invoiceNo;
  final DateTime? invoiceDate;
  final String? supplier;
  final int totalPaise;
  final int? itemCount;
  final List<PurchaseLine>? lines;
}

class PurchaseRegisterResponse {
  PurchaseRegisterResponse({
    required this.available,
    this.note,
    required this.rows,
    this.totalPaise,
    this.totalCount = 0,
  });

  factory PurchaseRegisterResponse.fromJson(Map<String, dynamic> json) {
    final rows = json['rows'] as List<dynamic>? ?? <dynamic>[];
    return PurchaseRegisterResponse(
      available: json['available'] as bool? ?? false,
      note: json['note'] as String?,
      rows: rows
          .whereType<Map<String, dynamic>>()
          .map(PurchaseRegisterRow.fromJson)
          .toList(),
      totalPaise: (json['total_paise'] as num?)?.toInt(),
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
    );
  }

  final bool available;
  final String? note;
  final List<PurchaseRegisterRow> rows;
  final int? totalPaise;
  final int totalCount;
}

class ApiClient {
  ApiClient({http.Client? client, this.baseUrl = configuredBaseUrl})
    : _client = client ?? http.Client();

  static const String defaultBaseUrl = 'http://127.0.0.1:8000';
  static const String configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultBaseUrl,
  );

  final http.Client _client;
  final String baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Future<TodayResponse> fetchToday(String storeId) async {
    final res = await _client.get(
      _uri('/stores/$storeId/dashboard/today'),
      headers: {'Accept': 'application/json'},
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'Failed to load today ($storeId)');
    }
    return TodayResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<TaskStateResponse> snooze(
    String storeId,
    String taskKey,
    String until,
  ) async {
    final res = await _client.post(
      _uri('/stores/$storeId/dashboard/tasks/$taskKey/snooze'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'until': until}),
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'Snooze failed');
    }
    return TaskStateResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<TaskStateResponse> markDone(String storeId, String taskKey) async {
    final res = await _client.post(
      _uri('/stores/$storeId/dashboard/tasks/$taskKey/done'),
      headers: {'Content-Type': 'application/json'},
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'Mark done failed');
    }
    return TaskStateResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<TaskStateResponse> reopen(String storeId, String taskKey) async {
    final res = await _client.post(
      _uri('/stores/$storeId/dashboard/tasks/$taskKey/reopen'),
      headers: {'Content-Type': 'application/json'},
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'Reopen failed');
    }
    return TaskStateResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<DailySummary> fetchDailySummary(String storeId, {String? date}) async {
    final res = await _client.get(
      _uri(
        '/stores/$storeId/dashboard/reports/daily-summary'
        '${date == null ? '' : '?date=$date'}',
      ),
      headers: {'Accept': 'application/json'},
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'Failed to load the daily summary');
    }
    return DailySummary.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<TrendResponse> fetchTrend(String storeId) async {
    final res = await _client.get(
      _uri('/stores/$storeId/dashboard/reports/trend'),
      headers: {'Accept': 'application/json'},
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'Failed to load the 7-day trend');
    }
    final TrendResponse trend = TrendResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
    if (trend.error != null) {
      throw ApiException(503, trend.error!);
    }
    return trend;
  }

  Future<StockNow> fetchStockNow(String storeId) async {
    final res = await _client.get(
      _uri('/stores/$storeId/dashboard/reports/stock-now'),
      headers: {'Accept': 'application/json'},
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, 'Failed to load stock figures');
    }
    return StockNow.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<PurchaseRegisterResponse> fetchPurchaseRegister(
    String storeId, {
    String q = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final Uri uri = _uri('/stores/$storeId/dashboard/reports/purchase-register')
        .replace(
          queryParameters: <String, String>{
            'q': q,
            'limit': '$limit',
            'offset': '$offset',
          },
        );
    final res = await _client.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode != 200) {
      throw ApiException(
        res.statusCode,
        'Failed to load the purchase register',
      );
    }
    return PurchaseRegisterResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }
}

/// Formats paise as Indian-grouped rupees, retaining paise when non-zero.
String formatRupees(int paise) {
  final bool negative = paise < 0;
  final int absolutePaise = paise.abs();
  final int rupees = absolutePaise ~/ 100;
  final int remainder = absolutePaise % 100;
  final String digits = rupees.toString();
  String out;
  if (digits.length <= 3) {
    out = digits;
  } else {
    final String last3 = digits.substring(digits.length - 3);
    String rest = digits.substring(0, digits.length - 3);
    final List<String> groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) {
      groups.insert(0, rest);
    }
    out = <String>[...groups, last3].join(',');
  }
  final String fraction = remainder == 0
      ? ''
      : '.${remainder.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}₹$out$fraction';
}
