import type { CheckOutcome, HealthCheck } from '../health-check.js';

/**
 * Adapter for modules or providers exposed over HTTP (e.g. a payment provider's
 * status endpoint, a WhatsApp gateway). The URL stays server-side; only the
 * curated messages below ever reach the app.
 *
 *   registry.register(new HttpHealthCheck('payments', process.env.PAYMENTS_HEALTH_URL!));
 */
export class HttpHealthCheck implements HealthCheck {
  readonly scope = 'global' as const;

  constructor(
    readonly key: string,
    private readonly url: string,
    private readonly options: { slowMs?: number; headers?: Record<string, string> } = {},
  ) {}

  async check(): Promise<CheckOutcome> {
    const started = Date.now();
    const res = await fetch(this.url, { headers: this.options.headers, redirect: 'error' });
    const ms = Date.now() - started;
    if (res.status >= 500 || res.status === 404) {
      return { status: 'UNAVAILABLE', message: 'The service is not responding normally.' };
    }
    if (!res.ok || ms > (this.options.slowMs ?? 2_000)) {
      return { status: 'DEGRADED', message: 'The service is responding slowly.' };
    }
    return { status: 'OPERATIONAL' };
  }
}
