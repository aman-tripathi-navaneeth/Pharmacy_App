import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/outbox_dao.dart';
import 'tour_models.dart';
import 'tour_repository.dart';

/// Overridden in `main()` (and tests).
final tourRepositoryProvider = Provider<TourRepository>((ref) => throw UnimplementedError());

class TourState {
  const TourState({required this.definition, this.progress});

  final TourDefinition definition;
  final TourProgress? progress;

  int get total => definition.steps.length;

  /// Started on this version but neither finished nor skipped.
  bool get resumable => progress?.status == TourStatus.inProgress;

  int get resumeIndex => resumable ? definition.indexOf(progress!.lastStepId) : 0;
}

final tourProvider = AsyncNotifierProvider<TourController, TourState>(TourController.new);

class TourController extends AsyncNotifier<TourState> {
  TourRepository get _repo => ref.read(tourRepositoryProvider);

  @override
  Future<TourState> build() async {
    final def = await _repo.definition();
    return TourState(definition: def, progress: await _repo.progress(def.version));
  }

  Future<void> record(int stepIndex, TourStatus status) async {
    final s = state.value ?? await future;
    final step = s.definition.steps[stepIndex];
    final p = await _repo.record(s.definition.version, step.id, status);
    state = AsyncData(TourState(definition: s.definition, progress: p));
  }

  /// Newer content and progress from another device, without blocking the UI.
  Future<void> syncInBackground() async {
    final s = await future;
    final newer = await _repo.syncWithServer(s.definition.version);
    final def = newer ?? s.definition;
    state = AsyncData(TourState(definition: def, progress: await _repo.progress(def.version)));
  }
}

/// Auto-launch only for a tour version the user has never started, and never on
/// top of work that needs attention (spec §8.4: "never block urgent work").
bool shouldAutoLaunch(TourState tour, SyncCounts counts) => tour.progress == null && counts.needsAttention == 0;

/// Auto-launch at most once per app session.
final tourAutoLaunchedProvider = NotifierProvider<_Flag, bool>(_Flag.new);

class _Flag extends Notifier<bool> {
  @override
  bool build() => false;
  void set() => state = true;
}
