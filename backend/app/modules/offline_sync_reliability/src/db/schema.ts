import { sql } from 'drizzle-orm';
import {
  bigint,
  boolean,
  check,
  customType,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgSequence,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

const ts = (name: string) => timestamp(name, { withTimezone: true, mode: 'date' });
const createdAt = () => ts('created_at').notNull().defaultNow();
const updatedAt = () => ts('updated_at').notNull().defaultNow();
const bytea = customType<{ data: Buffer }>({ dataType: () => 'bytea' });

const inList = (col: string, values: readonly string[]) => sql.raw(`${col} in (${values.map((v) => `'${v}'`).join(', ')})`);

// ─────────────────────────────────────────────────────────────── shared (interim)
// Owned by the Authentication / Store-setup module. Defined here so the app runs
// end to end; the Auth owner takes these over (same names and columns).

export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  status: text('status').notNull().default('ACTIVE'),
  name: text('name'),
  /** e.g. ['SUPPORT_AGENT'] for support staff (spec §8.2). */
  roles: text('roles').array().notNull().default(sql`'{}'::text[]`),
  createdAt: createdAt(),
});

export const stores = pgTable('stores', {
  id: uuid('id').primaryKey().defaultRandom(),
  status: text('status').notNull().default('ACTIVE'),
  name: text('name'),
  createdAt: createdAt(),
});

export const storeMembers = pgTable(
  'store_members',
  {
    userId: uuid('user_id').notNull().references(() => users.id),
    storeId: uuid('store_id').notNull().references(() => stores.id),
    role: text('role').notNull(),
    status: text('status').notNull().default('ACTIVE'),
  },
  (t) => [primaryKey({ columns: [t.userId, t.storeId] })],
);

// ─────────────────────────────────────────────────────────────── sync (spec §10.1–10.3)

export const SERVER_OP_STATUSES = ['RECEIVED', 'PROCESSING', 'SYNCED', 'CONFLICT', 'FAILED', 'RETRYABLE', 'CANCELLED'] as const;
export type ServerOpStatus = (typeof SERVER_OP_STATUSES)[number];

export const syncOperations = pgTable(
  'sync_operations',
  {
    id: bigint('id', { mode: 'number' }).primaryKey().generatedAlwaysAsIdentity(),
    clientOperationId: uuid('client_operation_id').notNull(),
    idempotencyKey: text('idempotency_key').notNull(),
    storeId: uuid('store_id').notNull(),
    userId: uuid('user_id').notNull(),
    deviceId: text('device_id').notNull(),
    module: text('module').notNull(),
    operationType: text('operation_type').notNull(),
    payload: jsonb('payload').$type<Record<string, unknown>>(),
    payloadHash: text('payload_hash'),
    entityId: text('entity_id'),
    baseVersion: integer('base_version'),
    dependsOn: uuid('depends_on').array().notNull().default(sql`'{}'::uuid[]`),
    status: text('status').$type<ServerOpStatus>().notNull(),
    serverResourceId: text('server_resource_id'),
    attemptCount: integer('attempt_count').notNull().default(0),
    lastErrorCode: text('last_error_code'),
    lastErrorMessage: text('last_error_message'),
    clientCreatedAt: ts('client_created_at'),
    processedAt: ts('processed_at'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    uniqueIndex('sync_operations_store_client_op_uq').on(t.storeId, t.clientOperationId),
    index('sync_operations_store_status_created_idx').on(t.storeId, t.status, t.createdAt),
    index('sync_operations_store_device_status_idx').on(t.storeId, t.deviceId, t.status),
    check('sync_operations_status_ck', inList('status', SERVER_OP_STATUSES)),
  ],
);

export const IDEMPOTENCY_OUTCOMES = ['SYNCED', 'CONFLICT', 'FAILED_PERMANENT', 'CANCELLED'] as const;
export type IdempotencyOutcome = (typeof IDEMPOTENCY_OUTCOMES)[number];

export const idempotencyRecords = pgTable(
  'idempotency_records',
  {
    id: bigint('id', { mode: 'number' }).primaryKey().generatedAlwaysAsIdentity(),
    storeId: uuid('store_id').notNull(),
    /** `${module}.${operationType}` — keys are scoped by store + action + key (spec §5). */
    scopeKey: text('scope_key').notNull(),
    idempotencyKey: text('idempotency_key').notNull(),
    userId: uuid('user_id').notNull(),
    clientOperationId: uuid('client_operation_id').notNull(),
    /** Null for a cancellation recorded before the payload ever arrived. */
    requestHash: text('request_hash'),
    outcome: text('outcome').$type<IdempotencyOutcome>().notNull(),
    resultBody: jsonb('result_body').$type<Record<string, unknown>>().notNull().default({}),
    resourceId: text('resource_id'),
    createdAt: createdAt(),
    /**
     * Deliberately never set: expiring a key while a delayed retry could still arrive
     * would allow a duplicate sale/payment (spec §10.6).
     */
    expiresAt: ts('expires_at'),
  },
  (t) => [
    uniqueIndex('idempotency_scope_key_uq').on(t.storeId, t.scopeKey, t.idempotencyKey),
    check('idempotency_outcome_ck', inList('outcome', IDEMPOTENCY_OUTCOMES)),
  ],
);

/** Audit trail of every sync attempt. Never store payloads, tokens or patient data here. */
export const syncLogs = pgTable(
  'sync_logs',
  {
    id: bigint('id', { mode: 'number' }).primaryKey().generatedAlwaysAsIdentity(),
    storeId: uuid('store_id').notNull(),
    userId: uuid('user_id').notNull(),
    deviceId: text('device_id').notNull(),
    operationId: text('operation_id').notNull(),
    action: text('action').$type<'PUSH' | 'RETRY' | 'CANCEL'>().notNull(),
    result: text('result').notNull(),
    errorCode: text('error_code'),
    durationMs: integer('duration_ms'),
    requestId: text('request_id'),
    timestamp: ts('timestamp').notNull().defaultNow(),
  },
  (t) => [index('sync_logs_store_ts_idx').on(t.storeId, t.timestamp), index('sync_logs_store_op_idx').on(t.storeId, t.operationId)],
);

/**
 * Per-store change feed read by `/sync/pull`. `seq` comes from `sync_counters` inside the
 * same transaction as the domain write; the counter row lock serialises writers per store,
 * so commits happen in `seq` order and a cursor never skips a change.
 * Deletions are tombstones (`deleted = true`).
 */
export const syncChanges = pgTable(
  'sync_changes',
  {
    storeId: uuid('store_id').notNull(),
    seq: bigint('seq', { mode: 'number' }).notNull(),
    entity: text('entity').notNull(),
    entityId: text('entity_id').notNull(),
    version: integer('version').notNull(),
    deleted: boolean('deleted').notNull().default(false),
    data: jsonb('data').$type<Record<string, unknown>>(),
    sourceOperationId: text('source_operation_id'),
    changedAt: ts('changed_at').notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.storeId, t.seq] })],
);

export const syncCounters = pgTable('sync_counters', {
  storeId: uuid('store_id').primaryKey(),
  seq: bigint('seq', { mode: 'number' }).notNull().default(0),
});

export const userDevices = pgTable(
  'user_devices',
  {
    userId: uuid('user_id').notNull(),
    storeId: uuid('store_id').notNull(),
    deviceId: text('device_id').notNull(),
    platform: text('platform'),
    appVersion: text('app_version'),
    lastActiveAt: ts('last_active_at').notNull().defaultNow(),
    /** Last cursor the device acknowledged as applied. */
    lastSyncCursor: text('last_sync_cursor'),
    lastSuccessfulSyncAt: ts('last_successful_sync_at'),
    createdAt: createdAt(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.deviceId, t.storeId] })],
);

// ─────────────────────────────────────────────────────────────── reference domain tables
// Used by the reference handlers (Inventory, Shop profile). Owners adopt or replace them.

export const stockMovements = pgTable(
  'stock_movements',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    storeId: uuid('store_id').notNull(),
    /** = clientOperationId: one ledger row per logical action, ever. */
    movementId: uuid('movement_id').notNull(),
    productId: text('product_id').notNull(),
    batchNo: text('batch_no'),
    quantityDelta: integer('quantity_delta').notNull(),
    reason: text('reason').notNull(),
    referenceId: text('reference_id'),
    note: text('note'),
    createdBy: uuid('created_by').notNull(),
    deviceId: text('device_id').notNull(),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex('stock_movements_store_movement_uq').on(t.storeId, t.movementId), check('stock_movements_nonzero_ck', sql`quantity_delta <> 0`)],
);

export const stockBalances = pgTable(
  'stock_balances',
  {
    storeId: uuid('store_id').notNull(),
    productId: text('product_id').notNull(),
    quantity: integer('quantity').notNull().default(0),
    version: integer('version').notNull().default(0),
    updatedAt: updatedAt(),
  },
  (t) => [primaryKey({ columns: [t.storeId, t.productId] }), check('stock_balances_nonneg_ck', sql`quantity >= 0`)],
);

export const shopProfiles = pgTable('shop_profiles', {
  storeId: uuid('store_id').primaryKey(),
  name: text('name'),
  phone: text('phone'),
  address: text('address'),
  email: text('email'),
  version: integer('version').notNull().default(0),
  updatedAt: updatedAt(),
  updatedBy: uuid('updated_by'),
});

// ─────────────────────────────────────────────────────────────── integration health

export const integrationHealth = pgTable(
  'integration_health',
  {
    key: text('key').notNull(),
    /** 'global', or the store id for store-scoped checks. */
    scope: text('scope').notNull(),
    status: text('status').$type<'OPERATIONAL' | 'DEGRADED' | 'UNAVAILABLE'>().notNull(),
    message: text('message'),
    lastCheckedAt: ts('last_checked_at').notNull(),
    lastOkAt: ts('last_ok_at'),
    lastChangedAt: ts('last_changed_at'),
    consecutiveFailures: integer('consecutive_failures').notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.key, t.scope] })],
);

// ─────────────────────────────────────────────────────────────── tickets (spec §10.4)

export const TICKET_STATUSES = ['OPEN', 'IN_PROGRESS', 'WAITING_FOR_USER', 'RESOLVED', 'CLOSED'] as const;
export type TicketStatus = (typeof TICKET_STATUSES)[number];
export const TICKET_PRIORITIES = ['LOW', 'NORMAL', 'HIGH', 'CRITICAL'] as const;
export type TicketPriority = (typeof TICKET_PRIORITIES)[number];
export const TICKET_CATEGORIES = ['BUG', 'FEATURE_REQUEST', 'ACCOUNT', 'SYNC', 'DATA_CONFLICT', 'OTHER'] as const;
export type TicketCategory = (typeof TICKET_CATEGORIES)[number];
export type AuthorRole = 'USER' | 'SUPPORT';
export const TICKET_EVENT_TYPES = ['CREATED', 'MESSAGE', 'NOTE', 'STATUS_CHANGE', 'ASSIGNMENT', 'PRIORITY_CHANGE'] as const;
export type TicketEventType = (typeof TICKET_EVENT_TYPES)[number];

export const ticketNumberSeq = pgSequence('ticket_number_seq', { startWith: 1001 });

export const tickets = pgTable(
  'tickets',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    ticketNumber: text('ticket_number').notNull(),
    storeId: uuid('store_id').notNull(),
    createdByUserId: uuid('created_by_user_id').notNull(),
    clientRequestId: uuid('client_request_id').notNull(),
    subject: text('subject').notNull(),
    description: text('description').notNull(),
    category: text('category').$type<TicketCategory>().notNull(),
    priority: text('priority').$type<TicketPriority>().notNull().default('NORMAL'),
    status: text('status').$type<TicketStatus>().notNull().default('OPEN'),
    relatedOperationId: uuid('related_operation_id'),
    relatedModule: text('related_module'),
    assignedToUserId: uuid('assigned_to_user_id'),
    lastActivityAt: ts('last_activity_at').notNull().defaultNow(),
    lastActivityBy: text('last_activity_by').$type<AuthorRole>().notNull(),
    resolvedAt: ts('resolved_at'),
    closedAt: ts('closed_at'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    uniqueIndex('tickets_number_uq').on(t.ticketNumber),
    uniqueIndex('tickets_request_uq').on(t.storeId, t.createdByUserId, t.clientRequestId),
    index('tickets_store_status_updated_idx').on(t.storeId, t.status, t.updatedAt),
    index('tickets_store_updated_idx').on(t.storeId, t.updatedAt, t.id),
    // Support console queues are cross-shop.
    index('tickets_status_activity_idx').on(t.status, t.lastActivityAt),
    index('tickets_assignee_status_idx').on(t.assignedToUserId, t.status),
    check('tickets_status_ck', inList('status', TICKET_STATUSES)),
    check('tickets_priority_ck', inList('priority', TICKET_PRIORITIES)),
    check('tickets_category_ck', inList('category', TICKET_CATEGORIES)),
  ],
);

/** Timeline: messages and status changes. Also the audit trail of ticket state (spec §13). */
export const ticketEvents = pgTable(
  'ticket_events',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    ticketId: uuid('ticket_id')
      .notNull()
      .references(() => tickets.id),
    storeId: uuid('store_id').notNull(),
    type: text('type').$type<TicketEventType>().notNull(),
    /** INTERNAL events (staff notes, assignment) are never shown to the shop. */
    visibility: text('visibility').$type<'PUBLIC' | 'INTERNAL'>().notNull().default('PUBLIC'),
    authorUserId: uuid('author_user_id').notNull(),
    authorRole: text('author_role').$type<AuthorRole>().notNull(),
    body: text('body'),
    fromStatus: text('from_status').$type<TicketStatus>(),
    toStatus: text('to_status').$type<TicketStatus>(),
    attachmentIds: uuid('attachment_ids').array().notNull().default(sql`'{}'::uuid[]`),
    /** Details for ASSIGNMENT / PRIORITY_CHANGE events, e.g. { from, to }. */
    meta: jsonb('meta').$type<Record<string, unknown>>(),
    /** Unique per author per ticket; NULLs (system events) never collide. */
    clientRequestId: uuid('client_request_id'),
    seq: bigint('seq', { mode: 'number' }).generatedAlwaysAsIdentity(),
    createdAt: createdAt(),
  },
  (t) => [
    index('ticket_events_ticket_idx').on(t.ticketId, t.seq),
    uniqueIndex('ticket_events_request_uq').on(t.ticketId, t.authorUserId, t.clientRequestId),
    check('ticket_events_visibility_ck', inList('visibility', ['PUBLIC', 'INTERNAL'])),
    check('ticket_events_type_ck', inList('type', TICKET_EVENT_TYPES)),
  ],
);

export const ticketAttachments = pgTable(
  'ticket_attachments',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    storeId: uuid('store_id').notNull(),
    uploadedByUserId: uuid('uploaded_by_user_id').notNull(),
    fileName: text('file_name').notNull(),
    contentType: text('content_type').notNull(),
    size: integer('size').notNull(),
    /** Set when attached to a ticket or reply; an upload can be used once. */
    ticketId: uuid('ticket_id').references(() => tickets.id),
    createdAt: createdAt(),
  },
  (t) => [index('ticket_attachments_ticket_idx').on(t.ticketId)],
);

/** File bytes, kept apart from metadata. Swap for object storage behind FileStore when chosen (spec §18). */
export const ticketAttachmentBlobs = pgTable('ticket_attachment_blobs', {
  attachmentId: uuid('attachment_id')
    .primaryKey()
    .references(() => ticketAttachments.id, { onDelete: 'cascade' }),
  data: bytea('data').notNull(),
});

// ─────────────────────────────────────────────────────────────── languages (spec §10.5)

export const languages = pgTable('languages', {
  code: text('code').primaryKey(),
  name: text('name').notNull(),
  nativeName: text('native_name').notNull(),
  enabled: boolean('enabled').notNull().default(true),
  isDefault: boolean('is_default').notNull().default(false),
  catalogVersion: text('catalog_version').notNull(),
  reviewed: boolean('reviewed').notNull().default(false),
  coverage: doublePrecision('coverage').notNull(),
  missingKeys: text('missing_keys').array().notNull().default(sql`'{}'::text[]`),
  rejectedKeys: text('rejected_keys').array().notNull().default(sql`'{}'::text[]`),
  publishedAt: ts('published_at').notNull(),
});

export const translations = pgTable(
  'translations',
  {
    languageCode: text('language_code').notNull(),
    key: text('key').notNull(),
    value: text('value').notNull(),
    catalogVersion: text('catalog_version').notNull(),
    updatedAt: updatedAt(),
  },
  (t) => [primaryKey({ columns: [t.languageCode, t.key, t.catalogVersion] })],
);

export const userPreferences = pgTable('user_preferences', {
  userId: uuid('user_id').primaryKey(),
  language: text('language'),
  updatedAt: updatedAt(),
});

// ─────────────────────────────────────────────────────────────── product tour

export const TOUR_STATUSES = ['IN_PROGRESS', 'COMPLETED', 'SKIPPED'] as const;
export type TourStatus = (typeof TOUR_STATUSES)[number];

/** Spec §8.4: completion stored by user and tour version. */
export const tourProgress = pgTable(
  'tour_progress',
  {
    userId: uuid('user_id').notNull(),
    tourVersion: text('tour_version').notNull(),
    status: text('status').$type<TourStatus>().notNull(),
    lastStepId: text('last_step_id').notNull(),
    stepsSeen: text('steps_seen').array().notNull().default(sql`'{}'::text[]`),
    completedAt: ts('completed_at'),
    skippedAt: ts('skipped_at'),
    restarts: integer('restarts').notNull().default(0),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.tourVersion] }), check('tour_progress_status_ck', inList('status', TOUR_STATUSES))],
);
