/** Postgres SQLSTATE of an error thrown by pg, possibly wrapped by Drizzle. */
export function pgCode(err: unknown): string | undefined {
  let e: unknown = err;
  for (let i = 0; i < 3 && e && typeof e === 'object'; i++) {
    const code = (e as { code?: unknown }).code;
    if (typeof code === 'string' && /^[0-9A-Z]{5}$/.test(code)) return code;
    e = (e as { cause?: unknown }).cause;
  }
  return undefined;
}

/** 23505: a unique index rejected the row — e.g. a duplicate idempotency key. */
export const isUniqueViolation = (err: unknown) => pgCode(err) === '23505';

/** 40001 / 40P01: serialization failure or deadlock — safe to retry the whole transaction. */
export const isTransientTxError = (err: unknown) => ['40001', '40P01'].includes(pgCode(err) ?? '');
