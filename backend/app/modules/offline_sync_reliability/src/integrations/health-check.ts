import { Injectable } from '@nestjs/common';

export const HEALTH_STATUSES = ['OPERATIONAL', 'DEGRADED', 'UNAVAILABLE', 'NOT_CONNECTED'] as const;
export type HealthStatus = (typeof HEALTH_STATUSES)[number];

export interface CheckContext {
  /** Present for store-scoped checks (e.g. this shop's sync backlog). */
  storeId: string;
}

export interface CheckOutcome {
  status: Exclude<HealthStatus, 'NOT_CONNECTED'>;
  /**
   * Short, user-safe explanation. NEVER include URLs, hostnames, credentials,
   * stack traces or raw provider errors (spec §7 screen 6: "no secrets").
   */
  message?: string;
}

/**
 * Contract each domain module owner implements so screen 6 can show their status.
 * Register it in your module's `onModuleInit` via `IntegrationHealthRegistry.register`.
 */
export interface HealthCheck {
  /** Must match a key in MODULE_CATALOG (or be a new platform key). */
  readonly key: string;
  /** `store` checks are cached per shop; `global` checks are shared. */
  readonly scope: 'global' | 'store';
  check(ctx: CheckContext): Promise<CheckOutcome>;
}

export interface ModuleInfo {
  key: string;
  label: string;
  /** What the shop user should do / expect, per non-operational status. */
  guidance: { degraded: string; unavailable: string };
}

const DEFAULT_GUIDANCE = {
  degraded: 'Some actions may be slow. Your changes are saved and sync automatically.',
  unavailable: 'This module can\'t be reached right now. Work that needs it waits safely; nothing is lost.',
};

/**
 * Modules shown on Integration Health (spec §14). A module whose owner has not
 * registered a check yet is reported honestly as NOT_CONNECTED, never as OK.
 */
export const MODULE_CATALOG: ModuleInfo[] = [
  {
    key: 'inventory',
    label: 'Inventory',
    guidance: {
      degraded: 'Stock updates are delayed. Movements are saved and applied in order; don\'t record them twice.',
      unavailable: 'Stock can\'t be updated on the server. Movements queue on this device and sync when restored.',
    },
  },
  {
    key: 'sales',
    label: 'Sales',
    guidance: {
      degraded: 'Sales are confirming slowly. Each sale has a fixed ID, so retries never create a duplicate.',
      unavailable: 'Sales can\'t be confirmed right now. Bills stay pending until the server accepts them.',
    },
  },
  {
    key: 'payments',
    label: 'Payments',
    guidance: {
      degraded: 'Confirmations are delayed. Payments stay pending until the provider confirms. Do not take the payment again.',
      unavailable: 'Payments can\'t be confirmed. Record the payment intent; it is settled only after the provider confirms.',
    },
  },
  { key: 'procurement', label: 'Procurement', guidance: DEFAULT_GUIDANCE },
  { key: 'customers', label: 'Customers', guidance: DEFAULT_GUIDANCE },
  {
    key: 'notifications',
    label: 'Notifications / WhatsApp',
    guidance: {
      degraded: 'Messages are sending slowly. Each message has an ID, so customers won\'t get duplicates.',
      unavailable: 'Notifications queue on the server and send when restored.',
    },
  },
  {
    key: 'sync',
    label: 'Offline sync',
    guidance: {
      degraded: 'Some changes are taking longer than usual to sync. They are saved and retry automatically.',
      unavailable: 'Sync is paused on the server. Changes stay saved on your devices.',
    },
  },
  {
    key: 'database',
    label: 'Server database',
    guidance: {
      degraded: 'The server is responding slowly. Changes are saved and retry automatically.',
      unavailable: 'The server can\'t store changes right now. Everything stays queued on your device.',
    },
  },
];

@Injectable()
export class IntegrationHealthRegistry {
  private readonly checks = new Map<string, HealthCheck>();

  register(check: HealthCheck) {
    if (this.checks.has(check.key)) throw new Error(`Duplicate health check for ${check.key}`);
    this.checks.set(check.key, check);
  }

  get(key: string) {
    return this.checks.get(key);
  }

  modules(): ModuleInfo[] {
    const known = new Set(MODULE_CATALOG.map((m) => m.key));
    const extra = [...this.checks.keys()]
      .filter((k) => !known.has(k))
      .map((key) => ({ key, label: key[0].toUpperCase() + key.slice(1), guidance: DEFAULT_GUIDANCE }));
    return [...MODULE_CATALOG, ...extra];
  }
}
