import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { nextStatus, validateTour } from '../src/product-tour/product-tour.service.js';
import { startApp } from './support/app.js';

describe('tour definition validation', () => {
  const en = { 'a.title': 'A', 'a.body': 'B', 'z.title': 'Z' };
  const ok = {
    version: '1.0',
    steps: [
      { id: 'a', type: 'info' as const, icon: 'storefront', titleKey: 'a.title', bodyKey: 'a.body' },
      { id: 'z', type: 'finish' as const, icon: 'check', titleKey: 'z.title' },
    ],
  };

  it('accepts a well-formed tour', () => expect(() => validateTour(ok, en)).not.toThrow());

  it('rejects unknown translation keys, bad icons and a missing finish step', () => {
    expect(() => validateTour({ ...ok, steps: [{ ...ok.steps[0], bodyKey: 'nope' }, ok.steps[1]] }, en)).toThrow(/"nope" missing/);
    expect(() => validateTour({ ...ok, steps: [{ ...ok.steps[0], icon: 'rocket' }, ok.steps[1]] }, en)).toThrow(/unknown icon/);
    expect(() => validateTour({ ...ok, steps: [ok.steps[0], { ...ok.steps[0], id: 'b' }] }, en)).toThrow(/finish step/);
    expect(() => validateTour({ ...ok, steps: [ok.steps[0], ok.steps[0], ok.steps[1]] }, en)).toThrow(/duplicate/);
  });

  it('status rules: completed is final, a skip is only undone by an explicit restart', () => {
    expect(nextStatus('COMPLETED', 'IN_PROGRESS', true)).toBe('COMPLETED');
    expect(nextStatus('SKIPPED', 'IN_PROGRESS', false)).toBe('SKIPPED');
    expect(nextStatus('SKIPPED', 'IN_PROGRESS', true)).toBe('IN_PROGRESS');
    expect(nextStatus(undefined, 'SKIPPED', false)).toBe('SKIPPED');
  });
});

describe('Product tour API (e2e)', () => {
  let ctx: Awaited<ReturnType<typeof startApp>>;
  const user = randomUUID();
  const other = randomUUID();
  const tk: Record<string, string> = {};
  const http = () => request(ctx.app.getHttpServer());
  const save = (stepId: string, status: string, as = tk.user, tourVersion = '2026.10.1') =>
    http().post('/product-tour/progress').set('Authorization', `Bearer ${as}`).send({ tourVersion, stepId, status });
  const get = (as = tk.user) =>
    http().get('/product-tour/progress').set('Authorization', `Bearer ${as}`).query({ version: '2026.10.1' });

  beforeAll(async () => {
    ctx = await startApp('tour_test');
    await ctx.q(`insert into users (id, status) values ($1, 'ACTIVE'), ($2, 'ACTIVE')`, [user, other]);
    tk.user = await ctx.token(user);
    tk.other = await ctx.token(other);
  }, 120_000);

  afterAll(async () => ctx?.stop());

  it('serves the shipped 6-step tour (public), by version or as latest', async () => {
    const latest = await http().get('/product-tour/latest').expect(200);
    expect(latest.body.version).toBe('2026.10.1');
    expect(latest.body.steps.map((s: { id: string }) => s.id)).toEqual(['welcome', 'dashboard', 'offline', 'help', 'syncStatus', 'finish']);
    expect(latest.body.steps[4].items).toHaveLength(5);
    await http().get('/product-tour/2026.10.1').expect(200);
    await http().get('/product-tour/9.9').expect(404);
    await http().get('/product-tour/..%2Fetc').expect(404);
  });

  it('tracks progress per user and version; completion is final; restarts are counted', async () => {
    await http().get('/product-tour/progress').query({ version: '2026.10.1' }).expect(401);
    expect((await get().expect(200)).body.progress).toBeNull();

    await save('welcome', 'IN_PROGRESS').expect(201);
    await save('dashboard', 'IN_PROGRESS').expect(201);
    let p = (await get()).body.progress;
    expect(p).toMatchObject({ status: 'IN_PROGRESS', lastStepId: 'dashboard', stepsSeen: ['welcome', 'dashboard'] });

    await save('finish', 'COMPLETED').expect(201);
    p = (await get()).body.progress;
    expect(p.status).toBe('COMPLETED');
    expect(p.completedAt).toBeTruthy();

    // Restart from Help: still completed, restart counted.
    const r = await save('welcome', 'IN_PROGRESS').expect(201);
    expect(r.body.progress).toMatchObject({ status: 'COMPLETED', lastStepId: 'welcome', restarts: 1 });

    // Another user is independent.
    expect((await get(tk.other)).body.progress).toBeNull();
  });

  it('a skip is not undone by a late offline update, only by an explicit restart', async () => {
    await save('welcome', 'IN_PROGRESS', tk.other).expect(201);
    await save('dashboard', 'SKIPPED', tk.other).expect(201);
    await save('offline', 'IN_PROGRESS', tk.other).expect(201); // stale update arriving late
    expect((await get(tk.other)).body.progress.status).toBe('SKIPPED');

    await save('welcome', 'IN_PROGRESS', tk.other).expect(201); // restart from Help
    expect((await get(tk.other)).body.progress.status).toBe('IN_PROGRESS');
  });

  it('validates input', async () => {
    await save('rocket', 'IN_PROGRESS').expect(400);
    await save('welcome', 'DONE').expect(400);
    await save('welcome', 'IN_PROGRESS', tk.user, '9.9').expect(404);
    await http().post('/product-tour/progress').send({ tourVersion: '2026.10.1', stepId: 'welcome', status: 'IN_PROGRESS' }).expect(401);
  });
});
