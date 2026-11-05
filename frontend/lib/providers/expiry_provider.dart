import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../data/expiry_repository.dart';
import '../models/expiry.dart';

enum ExpiryTab { expired, expiringSoon, all }

class ExpiryProvider extends ChangeNotifier {
  ExpiryProvider(this._repo);
  final ExpiryRepository _repo;

  ExpiryTab tab = ExpiryTab.expired;
  final Set<ExpiryStatus> allTabFilter = {};
  String query = '';

  ExpirySummary? summary;
  List<ExpiryBatch> items = [];
  int total = 0;
  int _page = 1;
  bool loading = false;
  bool loadingMore = false;
  String? error;

  bool get hasMore => items.length < total;

  int _requestId = 0;
  Timer? _debounce;
  bool _disposed = false;

  List<ExpiryStatus> get _statuses => switch (tab) {
        ExpiryTab.expired => [ExpiryStatus.expired],
        ExpiryTab.expiringSoon => [ExpiryStatus.critical, ExpiryStatus.warning],
        ExpiryTab.all => allTabFilter.toList(),
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
      summary = results[0] as ExpirySummary;
      final page = results[1] as ExpiryPage;
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

  void setTab(ExpiryTab value) {
    if (value == tab) return;
    tab = value;
    items = [];
    total = 0;
    load();
  }

  void toggleFilter(ExpiryStatus status) {
    allTabFilter.contains(status) ? allTabFilter.remove(status) : allTabFilter.add(status);
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
