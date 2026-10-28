import { Injectable } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import type { Tx } from '../../db/db.module.js';

export interface ChangeInput {
  entity: string;
  entityId: string;
  version: number;
  data?: Record<string, unknown>;
  deleted?: boolean;
}

export interface OperationContext {
  /** All writes MUST use this transaction; it commits atomically with the idempotency record. */
  tx: Tx;
  storeId: string;
  userId: string;
  deviceId: string;
  clientOperationId: string;
  entityId?: string;
  baseVersion?: number;
  /** Publish a canonical change to the store's pull feed (same transaction). */
  emitChange(change: ChangeInput): Promise<void>;
}

export interface HandlerResult {
  /** Canonical server id of the record created/updated (e.g. ledger movement id, sale id). */
  resourceId: string;
  version?: number;
}

export interface ConflictDetails {
  entity: string;
  entityId: string;
  serverVersion: number;
  serverUpdatedAt?: string;
  /** Current server values of the fields the client tried to change. */
  serverValues: Record<string, unknown>;
  clientValues: Record<string, unknown>;
  clientBaseVersion?: number;
}

/** Competing update: client must review and resolve; never blindly overwritten (spec §6). */
export class DomainConflictError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly conflict: ConflictDetails,
  ) {
    super(message);
  }
}

/** Validation/permission/business failure: retrying the same operation will not succeed. */
export class DomainRejectedError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

/**
 * Contract each domain module (Inventory, Sales, Procurement, Payments, …) implements to accept
 * offline operations. Handlers must be deterministic for a given payload and must only write
 * through `ctx.tx`. Never mark a payment settled from an offline intent (spec §5).
 */
export interface OperationHandler<P extends object = object> {
  readonly module: string;
  readonly operationType: string;
  /** class-validator DTO for the payload; validated before `handle` runs. */
  readonly payloadType: new () => P;
  handle(ctx: OperationContext, payload: P): Promise<HandlerResult>;
}

@Injectable()
export class OperationHandlerRegistry {
  private readonly handlers = new Map<string, OperationHandler>();

  register(handler: OperationHandler<any>) {
    const key = `${handler.module}.${handler.operationType}`;
    if (this.handlers.has(key)) throw new Error(`Duplicate sync handler for ${key}`);
    this.handlers.set(key, handler);
  }

  get(module: string, operationType: string): OperationHandler | undefined {
    return this.handlers.get(`${module}.${operationType}`);
  }

  supported(): string[] {
    return [...this.handlers.keys()].sort();
  }

  /** Returns a typed payload or human-readable validation messages. */
  async parse(handler: OperationHandler, payload: unknown): Promise<{ value?: object; errors: string[] }> {
    const value = plainToInstance(handler.payloadType, payload ?? {});
    const errors = await validate(value as object, { whitelist: true, forbidNonWhitelisted: true });
    const messages = errors.flatMap((e) => flatten(e));
    return messages.length ? { errors: messages } : { value, errors: [] };
  }
}

function flatten(e: import('class-validator').ValidationError, prefix = ''): string[] {
  const path = prefix ? `${prefix}.${e.property}` : e.property;
  const own = Object.values(e.constraints ?? {}).map((m) => (m.startsWith(e.property) ? m.replace(e.property, path) : `${path}: ${m}`));
  return [...own, ...(e.children ?? []).flatMap((c) => flatten(c, path))];
}
