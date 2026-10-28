/// Local lifecycle of an outbox operation (spec §4).
///
/// Only a server acknowledgement moves an operation to [synced]; the UI never
/// infers success on its own.
enum OpState {
  /// Saved locally; not sent yet.
  queued,

  /// Submitted; awaiting the server's per-operation result.
  inFlight,

  /// Server confirmed processing (or prior processing of the same key).
  synced,

  /// Temporary failure; retried automatically with backoff using the same key.
  retryWait,

  /// Competing/incompatible update; the user must review it.
  conflict,

  /// Validation, permission or business failure; retrying will not help.
  failedPermanent,

  /// Cancelled before commit (or resolved by keeping the server version).
  cancelled;

  String get wireName => switch (this) {
        queued => 'QUEUED',
        inFlight => 'IN_FLIGHT',
        synced => 'SYNCED',
        retryWait => 'RETRY_WAIT',
        conflict => 'CONFLICT',
        failedPermanent => 'FAILED_PERMANENT',
        cancelled => 'CANCELLED',
      };

  bool get isTerminal => this == synced || this == cancelled;

  /// Still owed to the server (counts toward "pending").
  bool get isPending => this == queued || this == inFlight || this == retryWait;
}
