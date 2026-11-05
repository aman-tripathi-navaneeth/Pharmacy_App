import 'dart:math';

/// Starting parameters from spec §12. Tune during the pilot.
class SyncConfig {
  const SyncConfig({
    this.batchSize = 50,
    this.backoffBase = const Duration(seconds: 2),
    this.backoffCap = const Duration(minutes: 5),
    this.maxAutoAttempts = 8,
    this.maxPayloadBytes = 256 * 1024,
    this.queueWarningCount = 100,
    this.queueWarningAge = const Duration(minutes: 15),
    this.periodicCheck = const Duration(seconds: 30),
    this.pullPageSize = 200,
    this.keepSyncedHistory = const Duration(days: 7),
  });

  final int batchSize;
  final Duration backoffBase;
  final Duration backoffCap;
  final int maxAutoAttempts;
  final int maxPayloadBytes;
  final int queueWarningCount;
  final Duration queueWarningAge;
  final Duration periodicCheck;
  final int pullPageSize;
  final Duration keepSyncedHistory;
}

/// Exponential backoff with "equal jitter": half fixed, half random, so retries
/// from many devices spread out but never collapse to zero delay.
class Backoff {
  Backoff(this.config, [Random? random]) : _random = random ?? Random();

  final SyncConfig config;
  final Random _random;

  Duration delayFor(int attempt, {Duration? retryAfter}) {
    final exp = config.backoffBase.inMilliseconds * pow(2, max(0, attempt - 1));
    final capped = min(exp.toDouble(), config.backoffCap.inMilliseconds.toDouble());
    final half = capped / 2;
    var ms = (half + _random.nextDouble() * half).round();
    if (retryAfter != null && retryAfter.inMilliseconds > ms) {
      ms = min(retryAfter.inMilliseconds, config.backoffCap.inMilliseconds);
    }
    return Duration(milliseconds: ms);
  }
}
