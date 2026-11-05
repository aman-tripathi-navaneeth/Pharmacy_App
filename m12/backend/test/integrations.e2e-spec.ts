import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { type CheckOutcome, IntegrationHealthRegistry } from '../src/integrations/health-check.js';
import { seedMember, startApp, type TestApp } from './support/app.js';

describe('Integration Health API (e2e)', () => {
  let ctx: TestApp;
  let token: string;
  let outsiderToken: string;

  const user = randomUUID();
  const outsider = randomUUID();
  const shop = randomUUID();

  let payments: CheckOutcome = { status: 'DEGRADED', message: 'Provider confirmations are delayed.' };

  const http = () => request(ctx.app.getHttpServer());
  const getHealth = (t = token) =>
    http().get('/integrations/health').set('Authorization', `Bearer ${t}`).query({ storeId: shop });
  const recheck = (key: string) =>
    http()
      .post(`/integrations/health/${key}/check`)
      .set('Authorization', `Bearer ${token}`)
      .send({ storeId: shop });
  const mod = (body: { modules: { key: string }[] }, key: string) => body.modules.find((m) => m.key === key) as any;

  beforeAll(async () => {
    ctx = await startApp('health_test');

    // Simulated domain checks, registered the same way module owners will.
    const registry = ctx.app.get(IntegrationHealthRegistry);
    registry.register({ key: 'payments', scope: 'global', check: async () => payments });
    registry.register({ key: 'notifications', scope: 'global', check: () => new Promise(() => undefined) });
    registry.register({
      key: 'procurement',
      scope: 'global',
      check: async () => {
        throw new Error('connect ECONNREFUSED https://user:s3cret@supplier.internal:8443/health');
      },
    });

    await seedMember(ctx, { userId: user, storeId: shop });
    await ctx.q(`insert into users (id, status) values ($1, 'ACTIVE')`, [outsider]);

    // One change stuck retrying for 20 minutes in this shop.
    await ctx.q(
      `insert into sync_operations (client_operation_id, idempotency_key, store_id, user_id, device_id, module, operation_type, status, created_at)
       values ($1, 'idem_stuck_op', $2, $3, 'd1', 'inventory', 'stock_movement', 'RETRYABLE', now() - interval '20 minutes')`,
      [randomUUID(), shop, user],
    );

    token = await ctx.token(user);
    outsiderToken = await ctx.token(outsider);
  }, 120_000);

  afterAll(async () => ctx?.stop());

  it('requires authentication and shop membership', async () => {
    await http().get('/integrations/health').query({ storeId: shop }).expect(401);
    const res = await getHealth(outsiderToken).expect(403);
    expect(res.body.error.code).toBe('STORE_ACCESS_DENIED');
  });

  it('reports every catalog module with honest status, guidance and timestamps', async () => {
    const res = await getHealth().expect(200);
    const body = res.body;

    expect(body.refreshAfterSec).toBe(300);
    expect(body.overall).toBe('UNAVAILABLE');
    expect(body.modules.map((m: { key: string }) => m.key)).toEqual([
      'inventory',
      'sales',
      'payments',
      'procurement',
      'customers',
      'notifications',
      'sync',
      'database',
    ]);

    expect(mod(body, 'inventory')).toMatchObject({ status: 'OPERATIONAL', guidance: null });
    expect(mod(body, 'inventory').lastOkAt).toBeTruthy();
    expect(mod(body, 'database')).toMatchObject({ status: 'OPERATIONAL' });

    expect(mod(body, 'payments')).toMatchObject({ status: 'DEGRADED', label: 'Payments' });
    expect(mod(body, 'payments').guidance).toMatch(/Do not take the payment again/);

    expect(mod(body, 'notifications')).toMatchObject({ status: 'UNAVAILABLE', message: 'Did not respond in time.' });
    expect(mod(body, 'notifications').guidance).toMatch(/queue on the server/);

    expect(mod(body, 'sync')).toMatchObject({ status: 'DEGRADED' });
    expect(mod(body, 'sync').message).toMatch(/1 change has been retrying/);

    // Modules without a registered check are never shown as OK.
    expect(mod(body, 'sales')).toMatchObject({ status: 'NOT_CONNECTED', lastCheckedAt: null });
  }, 20_000);

  it('never leaks internal error details', async () => {
    const res = await getHealth().expect(200);
    expect(mod(res.body, 'procurement')).toMatchObject({ status: 'UNAVAILABLE', message: 'The last check failed.' });
    const raw = JSON.stringify(res.body);
    expect(raw).not.toMatch(/s3cret|supplier\.internal|ECONNREFUSED|https?:\/\//);
  });

  it('serves cached results within the TTL and throttles rechecks', async () => {
    payments = { status: 'OPERATIONAL' };
    expect(mod((await getHealth().expect(200)).body, 'payments').status).toBe('DEGRADED'); // cached

    const tooSoon = await recheck('payments').expect(200);
    expect(tooSoon.body.module.status).toBe('DEGRADED'); // < 10 s since last run

    const real = Date.now;
    const spy = vi.spyOn(Date, 'now').mockImplementation(() => real() + 11_000);
    try {
      const fresh = await recheck('payments').expect(200);
      expect(fresh.body.module).toMatchObject({ status: 'OPERATIONAL', guidance: null, consecutiveFailures: 0 });
    } finally {
      spy.mockRestore();
    }
  });

  it('persists lastOkAt so an outage can show "last known operational"', async () => {
    const [before] = await ctx.q<{ last_ok_at: Date }>(`select last_ok_at from integration_health where key = 'payments' and scope = 'global'`);
    expect(before?.last_ok_at).toBeInstanceOf(Date);

    payments = { status: 'UNAVAILABLE', message: 'Provider is down.' };
    const real = Date.now;
    const spy = vi.spyOn(Date, 'now').mockImplementation(() => real() + 30_000);
    try {
      const res = await recheck('payments').expect(200);
      expect(res.body.module).toMatchObject({ status: 'UNAVAILABLE', consecutiveFailures: 1 });
      expect(new Date(res.body.module.lastOkAt).getTime()).toBe(before!.last_ok_at.getTime());
    } finally {
      spy.mockRestore();
    }
  });

  it('validates the module key', async () => {
    await recheck('Bad-Key!').expect(400);
    const res = await recheck('unknown_module').expect(404);
    expect(res.body.error.code).toBe('MODULE_NOT_FOUND');
  });
});
