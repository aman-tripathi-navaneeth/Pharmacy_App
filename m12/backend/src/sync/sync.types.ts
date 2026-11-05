import type { ConflictDetails } from './handlers/operation-handler.js';

/** Per-operation result contract shared with the Flutter sync manager (spec §3). */
export type SyncResultStatus = 'SYNCED' | 'ALREADY_PROCESSED' | 'CONFLICT' | 'FAILED_PERMANENT' | 'RETRYABLE_FAILURE';

export interface OperationResult {
  clientOperationId: string;
  status: SyncResultStatus;
  serverResourceId?: string;
  version?: number;
  errorCode?: string;
  /** Human-readable, safe to show to the shop user. */
  message?: string;
  conflict?: ConflictDetails;
  /** Hint for RETRYABLE_FAILURE; the client still applies its own capped backoff. */
  retryAfterMs?: number;
}

export const ERR = {
  UNSUPPORTED_OPERATION: 'UNSUPPORTED_OPERATION',
  INVALID_PAYLOAD: 'INVALID_PAYLOAD',
  PAYLOAD_TOO_LARGE: 'PAYLOAD_TOO_LARGE',
  IDEMPOTENCY_KEY_REUSED: 'IDEMPOTENCY_KEY_REUSED',
  OPERATION_ID_MISMATCH: 'OPERATION_ID_MISMATCH',
  OPERATION_CANCELLED: 'OPERATION_CANCELLED',
  DEPENDENCY_NOT_SYNCED: 'DEPENDENCY_NOT_SYNCED',
  DEPENDENCY_FAILED: 'DEPENDENCY_FAILED',
  TRANSIENT_ERROR: 'TRANSIENT_ERROR',
} as const;
