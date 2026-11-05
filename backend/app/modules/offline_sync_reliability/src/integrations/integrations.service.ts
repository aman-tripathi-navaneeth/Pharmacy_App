import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { sql } from 'drizzle-orm';
import { type Db, InjectDb } from '../db/db.module.js';
import { integrationHealth } from '../db/schema.js';
import { StoreAccessService } from '../common/store-access/store-access.service.js';
import { type CheckOutcome, type HealthStatus, IntegrationHealthRegistry, type ModuleInfo } from './health-check.js';

type IntegrationHealth = typeof integrationHealth.$inferSelect;
const GLOBAL = 'global';

export const CHECK_TIMEOUT_MS = 5_000;
export const CACHE_TTL_MS = 60_000;
/** "Retry check" cannot hammer a struggling dependency. */
export const MIN_RECHECK_MS = 10_000;
/** Client auto-refresh interval (wireframe F1: "Auto-refresh every 5 min"). */
export const REFRESH_AFTER_SEC = 300;

export interface ModuleHealth {
  key: string;
  label: string;
  status: HealthStatus;
  message: string | null;
  /** What to do / expect; only for DEGRADED and UNAVAILABLE. */
  guidance: string | null;
  lastCheckedAt: Date | null;
  lastOkAt: Date | null;
  consecutiveFailures: number;
}

const NOT_CONNECTED_MESSAGE = 'Not connected yet. This module has not published a health check.';

class CheckTimeout extends Error {}

@Injectable()
export class IntegrationsService {
  private readonly logger = new Logger(IntegrationsService.name);
  private readonly cache = new Map<string, { at: number; row: IntegrationHealth }>();
  private readonly inFlight = new Map<string, Promise<IntegrationHealth>>();

  constructor(
    private readonly registry: IntegrationHealthRegistry,
    private readonly access: StoreAccessService,
    @InjectDb() private readonly db: Db,
  ) {}

  async health(userId: string, storeId: string) {
    await this.access.assertAccess(userId, storeId);
    const sid = storeId;
    const modules = await Promise.all(this.registry.modules().map((m) => this.moduleHealth(m, sid, false)));
    return this.envelope(modules);
  }

  async recheck(userId: string, storeId: string, key: string) {
    await this.access.assertAccess(userId, storeId);
    const info = this.registry.modules().find((m) => m.key === key);
    if (!info) throw new NotFoundException({ code: 'MODULE_NOT_FOUND', message: 'Unknown module.' });
    const module = await this.moduleHealth(info, storeId, true);
    return { module, checkedAt: new Date().toISOString() };
  }

  private envelope(modules: ModuleHealth[]) {
    const rank: Record<HealthStatus, number> = { OPERATIONAL: 0, NOT_CONNECTED: 0, DEGRADED: 1, UNAVAILABLE: 2 };
    const worst = modules.reduce((w, m) => (rank[m.status] > rank[w] ? m.status : w), 'OPERATIONAL' as HealthStatus);
    const checked = modules.map((m) => m.lastCheckedAt?.getTime() ?? 0).filter(Boolean);
    return {
      overall: worst,
      checkedAt: checked.length ? new Date(Math.min(...checked)).toISOString() : new Date().toISOString(),
      refreshAfterSec: REFRESH_AFTER_SEC,
      modules,
    };
  }

  private async moduleHealth(info: ModuleInfo, storeId: string, force: boolean): Promise<ModuleHealth> {
    const check = this.registry.get(info.key);
    if (!check) {
      return {
        key: info.key,
        label: info.label,
        status: 'NOT_CONNECTED',
        message: NOT_CONNECTED_MESSAGE,
        guidance: null,
        lastCheckedAt: null,
        lastOkAt: null,
        consecutiveFailures: 0,
      };
    }
    const row = await this.run(info.key, check.scope === 'store' ? storeId : GLOBAL, force);
    return {
      key: info.key,
      label: info.label,
      status: row.status,
      message: row.message ?? null,
      guidance:
        row.status === 'DEGRADED' ? info.guidance.degraded : row.status === 'UNAVAILABLE' ? info.guidance.unavailable : null,
      lastCheckedAt: row.lastCheckedAt,
      lastOkAt: row.lastOkAt ?? null,
      consecutiveFailures: row.consecutiveFailures,
    };
  }

  /** Cached, single-flight execution of one check. */
  private async run(key: string, scope: string, force: boolean): Promise<IntegrationHealth> {
    const cacheKey = `${key}:${scope}`;
    const cached = this.cache.get(cacheKey);
    const age = cached ? Date.now() - cached.at : Infinity;
    if (cached && (age < MIN_RECHECK_MS || (!force && age < CACHE_TTL_MS))) return cached.row;

    const pending = this.inFlight.get(cacheKey);
    if (pending) return pending;

    const job = this.execute(key, scope).finally(() => this.inFlight.delete(cacheKey));
    this.inFlight.set(cacheKey, job);
    const row = await job;
    this.cache.set(cacheKey, { at: Date.now(), row });
    return row;
  }

  private async execute(key: string, scope: string): Promise<IntegrationHealth> {
    const check = this.registry.get(key)!;
    let outcome: CheckOutcome;
    try {
      // Global checks get a placeholder store id they must not use.
      outcome = await withTimeout(check.check({ storeId: scope === GLOBAL ? '' : scope }), CHECK_TIMEOUT_MS);
    } catch (err) {
      // Details stay in server logs; the app only sees a curated message.
      this.logger.warn(`health check "${key}" failed: ${err instanceof Error ? err.message : err}`);
      outcome = {
        status: 'UNAVAILABLE',
        message: err instanceof CheckTimeout ? 'Did not respond in time.' : 'The last check failed.',
      };
    }

    const now = new Date();
    const ok = outcome.status === 'OPERATIONAL';
    const fallback: IntegrationHealth = {
      key,
      scope,
      status: outcome.status,
      message: outcome.message ?? null,
      lastCheckedAt: now,
      lastOkAt: ok ? now : (this.cache.get(`${key}:${scope}`)?.row.lastOkAt ?? null),
      lastChangedAt: null,
      consecutiveFailures: ok ? 0 : 1,
    };
    try {
      const t = integrationHealth;
      const [row] = await this.db
        .insert(t)
        .values({ ...fallback, lastChangedAt: now })
        .onConflictDoUpdate({
          target: [t.key, t.scope],
          set: {
            status: outcome.status,
            message: outcome.message ?? null,
            lastCheckedAt: now,
            lastOkAt: ok ? now : sql`${t.lastOkAt}`,
            lastChangedAt: sql`case when ${t.status} <> ${outcome.status} then ${now.toISOString()}::timestamptz else ${t.lastChangedAt} end`,
            consecutiveFailures: ok ? 0 : sql`${t.consecutiveFailures} + 1`,
          },
        })
        .returning();
      return row ?? fallback;
    } catch (err) {
      // The database itself may be the failing dependency; still report the result.
      this.logger.warn(`could not persist health for "${key}": ${err instanceof Error ? err.message : err}`);
      return fallback;
    }
  }
}

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  let timer: NodeJS.Timeout;
  return Promise.race([
    p,
    new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new CheckTimeout()), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}
