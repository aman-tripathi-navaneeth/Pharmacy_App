import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../data/low_stock_repository.dart';
import '../models/low_stock.dart';

enum LowStockFilter { all, outOfStock, low }

class LowStockProvider extends ChangeNotifier {
  LowStockProvider(this._repo);
  final LowStockRepository _repo;

  LowStockFilter filter = LowStockFilter.all;
  String query = '';

  LowStockSummary? summary;
  List<LowStockItem> items = [];
  int total = 0;
  int _page = 1;
  bool loading = false;
  bool loadingMore = false;
  String? error;

  bool get hasMore => items.length < total;

  int _requestId = 0;
  Timer? _debounce;
  bool _disposed = false;

  List<LowStockStatus> get _statuses => switch (filter) {
        LowStockFilter.all => const [],
        LowStockFilter.outOfStock => [LowStockStatus.outOfStock],
        LowStockFilter.low => [LowStockStatus.low],
      };

  Future<void> load() async {
    final id = ++_requestId;
    loading = true;
    error = null;
    _page = 1;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repo.summary(),
        _repo.list(statuses: _statuses, query: query, page: 1),
      ]);
      if (id != _requestId) return;
      summary = results[0] as LowStockSummary;
      final page = results[1] as LowStockPage;
      items = page.items;
      total = page.total;
    } on ApiException catch (e) {
      if (id != _requestId) return;
      error = e.message;
    } finally {
      if (id == _requestId) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore) return;
    final id = _requestId;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await _repo.list(statuses: _statuses, query: query, page: _page + 1);
      if (id != _requestId) return;
      items = [...items, ...page.items];
      total = page.total;
      _page++;
    } on ApiException {
      // Ignore: scrolling again retries.
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  void setFilter(LowStockFilter value) {
    if (value == filter) return;
    filter = value;
    items = [];
    total = 0;
    load();
  }

  void setQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (value == query) return;
      query = value;
      items = [];
      total = 0;
      load();
    });
  }

  Future<void> setReorderLevel(String productId, double level) async {
    await _repo.setReorderLevel(productId, level);
    await load();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
