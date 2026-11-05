import 'dart:convert';

import 'package:flutter/services.dart';

import '../../data/local/outbox_dao.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/tour_api.dart';
import '../../l10n/translations.dart' show compareVersions;
import 'tour_models.dart';

/// Tour content and progress. Progress is saved on the device first and pushed
/// to `POST /product-tour/progress` when possible, so the tour works offline.
class TourRepository {
  TourRepository({required this.dao, required this.api, AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final OutboxDao dao;
  final TourApi api;
  final AssetBundle _bundle;

  static const _defKey = 'tour_definition';
  static String _progressKey(String v) => 'tour_progress:$v';
  static String _pendingKey(String v) => 'tour_progress_pending:$v';

  /// Newest definition on the device: bundled with the app, or downloaded later.
  Future<TourDefinition> definition() async {
    // index.json is written by `npm run l10n:export` alongside the definitions.
    final index = jsonDecode(await _bundle.loadString('assets/tour/index.json')) as Map<String, dynamic>;
    TourDefinition? best;
    for (final file in (index['tours'] as List).cast<String>()) {
      final d = TourDefinition.fromJson(jsonDecode(await _bundle.loadString('assets/tour/$file')) as Map<String, dynamic>);
      if (best == null || compareVersions(d.version, best.version) > 0) best = d;
    }
    final cachedRaw = await dao.readMeta(_defKey);
    if (cachedRaw != null && cachedRaw.isNotEmpty) {
      final cached = TourDefinition.fromJson(jsonDecode(cachedRaw) as Map<String, dynamic>);
      if (best == null || compareVersions(cached.version, best.version) > 0) best = cached;
    }
    if (best == null) throw StateError('No product tour bundled (assets/tour/)');
    return best;
  }

  Future<TourProgress?> progress(String version) async {
    final raw = await dao.readMeta(_progressKey(version));
    if (raw == null || raw.isEmpty) return null;
    return TourProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Saves locally (never fails) and tries the server; a failed push is retried by [flushPending].
  Future<TourProgress> record(String version, String stepId, TourStatus status) async {
    final current = await progress(version);
    // Mirrors the server: completion is final for a version.
    final next = TourProgress(
      status: current?.status == TourStatus.completed ? TourStatus.completed : status,
      lastStepId: stepId,
    );
    await dao.writeMeta(_progressKey(version), jsonEncode(next.toJson()));
    try {
      await api.save(version: version, stepId: stepId, status: status);
      await dao.writeMeta(_pendingKey(version), '');
    } on ApiException {
      await dao.writeMeta(_pendingKey(version), jsonEncode({'stepId': stepId, 'status': status.wire}));
    }
    return next;
  }

  Future<void> flushPending(String version) async {
    final raw = await dao.readMeta(_pendingKey(version));
    if (raw == null || raw.isEmpty) return;
    final p = jsonDecode(raw) as Map<String, dynamic>;
    try {
      await api.save(version: version, stepId: p['stepId'] as String, status: TourStatus.parse(p['status'] as String));
      await dao.writeMeta(_pendingKey(version), '');
    } on ApiException {
      // Still offline.
    }
  }

  /// Downloads a newer definition and restores server progress on a new device
  /// (so someone who finished the tour elsewhere is not shown it again).
  Future<TourDefinition?> syncWithServer(String currentVersion) async {
    TourDefinition? newer;
    try {
      final latest = await api.latest();
      if (compareVersions(latest.version, currentVersion) > 0) {
        await dao.writeMeta(_defKey, jsonEncode(latest.raw));
        newer = latest;
      }
    } on ApiException {
      return null;
    }
    final version = newer?.version ?? currentVersion;
    await flushPending(version);
    if (await progress(version) == null) {
      try {
        final remote = await api.progress(version);
        if (remote != null) await dao.writeMeta(_progressKey(version), jsonEncode(remote.toJson()));
      } on ApiException {
        // Keep local state.
      }
    }
    return newer;
  }
}
