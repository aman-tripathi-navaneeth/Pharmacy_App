import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { seedMember, startApp, type TestApp } from './support/app.js';

describe('Sync API (e2e)', () => {
  let ctx: TestApp;

  const userA = randomUUID();
  const userB = randomUUID();
  const shop1 = randomUUID();
  const shop2 = randomUUID();
  let tokenA: string;
  let tokenB: string;

  const http = () => request(ctx.app.getHttpServer());

  function op(over: Partial<Record<string, unknown>> = {}) {
    return {
      clientOperationId: randomUUID(),
      idempotencyKey: `idem_${randomUUID()}`,
      module: 'inventory',
      operationType: 'stock_movement',
      payload: { productId: 'paracetamol-500', quantityDelta: 10, reason: 'PURCHASE' },
      ...over,
    };
  }

  function push(token: string, operations: object[], storeId = shop1, deviceId = 'device-1') {
    return http().post('/sync/push').set('Authorization', `Bearer ${token}`).send({ storeId: storeId, deviceId, operations });
  }

  const countRows = async (sql: string, params: unknown[] = []) => Number((await ctx.q<{ n: string }>(sql, params))[0].n);
  const ledgerCount = (productId = 'paracetamol-500') =>
    countRows('select count(*) n from stock_movements where store_id = $1 and product_id = $2', [shop1, productId]);
  const balance = async (productId = 'paracetamol-500') =>
    (await ctx.q<{ quantity: number }>('select quantity from stock_balances where store_id = $1 and product_id = $2', [shop1, productId]))[0]
      ?.quantity ?? 0;

  beforeAll(async () => {
    ctx = await startApp('sync_test');
    await seedMember(ctx, { userId: userA, storeId: shop1, role: 'OWNER' });
    await seedMember(ctx, { userId: userB, storeId: shop1, role: 'STAFF' });
    await seedMember(ctx, { userId: userB, storeId: shop2, role: 'OWNER' });
    tokenA = await ctx.token(userA);
    tokenB = await ctx.token(userB);
  }, 120_000);

  afterAll(async () => ctx?.stop());

  it('rejects unauthenticated requests with the standard error shape', async () => {
    const res = await http().get('/sync/status').query({ storeId: shop1 }).expect(401);
    expect(res.body.error).toMatchObject({ code: 'AUTH_REQUIRED' });
    expect(res.body.error.requestId).toBeTruthy();
    expect(res.headers['x-request-id']).toBe(res.body.error.requestId);
  });

  it('validates the batch envelope (max 50 ops)', async () => {
    const ops = Array.from({ length: 51 }, () => op());
    const res = await push(tokenA, ops).expect(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
  });

  describe('duplicate prevention', () => {
    it('same key repeated → one ledger entry, ALREADY_PROCESSED with the original resource id', async () => {
      const o = op();
      const first = await push(tokenA, [o]).expect(200);
      expect(first.body.results[0]).toMatchObject({ status: 'SYNCED' });
      const resourceId = first.body.results[0].serverResourceId;

      // e.g. response lost to a timeout after the server committed → device retries with same key.
      const second = await push(tokenA, [o]).expect(200);
      expect(second.body.results[0]).toMatchObject({ status: 'ALREADY_PROCESSED', serverResourceId: resourceId });

      const viaRetryEndpoint = await http()
        .post(`/sync/operations/${o.clientOperationId}/retry`)
        .set('Authorization', `Bearer ${tokenA}`)
        .send({ storeId: shop1, deviceId: 'device-1' })
        .expect(200);
      expect(viaRetryEndpoint.body).toMatchObject({ status: 'ALREADY_PROCESSED', serverResourceId: resourceId });

      expect(await countRows('select count(*) n from stock_movements where movement_id = $1', [o.clientOperationId])).toBe(1);
    });

    it('concurrent submissions of the same key commit exactly once', async () => {
      const o = op({ payload: { productId: 'amoxicillin-250', quantityDelta: 5, reason: 'PURCHASE' } });
      const responses = await Promise.all(Array.from({ length: 6 }, () => push(tokenA, [o])));
      const statuses = responses.map((r) => r.body.results[0].status).sort();
      expect(statuses.filter((s) => s === 'SYNCED')).toHaveLength(1);
      expect(statuses.every((s) => s === 'SYNCED' || s === 'ALREADY_PROCESSED')).toBe(true);
      expect(await ledgerCount('amoxicillin-250')).toBe(1);
      expect(await balance('amoxicillin-250')).toBe(5);
    });

    it('same key with a different payload is rejected', async () => {
      const o = op();
      await push(tokenA, [o]).expect(200);
      const tampered = { ...o, payload: { ...o.payload, quantityDelta: 999 } };
      const res = await push(tokenA, [tampered]).expect(200);
      expect(res.body.results[0]).toMatchObject({ status: 'FAILED_PERMANENT', errorCode: 'IDEMPOTENCY_KEY_REUSED' });
    });

    it('partial batch failure does not replay successful operations', async () => {
      const before = await ledgerCount('ors-sachet');
      const ok1 = op({ payload: { productId: 'ors-sachet', quantityDelta: 3, reason: 'PURCHASE' } });
      const bad = op({ payload: { productId: 'ors-sachet', quantityDelta: -100, reason: 'SALE' } });
      const ok2 = op({ payload: { productId: 'ors-sachet', quantityDelta: -1, reason: 'SALE' } });

      const first = await push(tokenA, [ok1, bad, ok2]).expect(200);
      expect(first.body.results.map((r: { status: string }) => r.status)).toEqual(['SYNCED', 'FAILED_PERMANENT', 'SYNCED']);
      expect(first.body.results[1]).toMatchObject({ errorCode: 'INSUFFICIENT_STOCK' });
      expect(first.body.results[1].message).toMatch(/exceeds available balance/);

      const replay = await push(tokenA, [ok1, bad, ok2]).expect(200);
      expect(replay.body.results.map((r: { status: string }) => r.status)).toEqual(['ALREADY_PROCESSED', 'FAILED_PERMANENT', 'ALREADY_PROCESSED']);
      expect((await ledgerCount('ors-sachet')) - before).toBe(2);
      expect(await balance('ors-sachet')).toBe(2);
    });
  });

  describe('validation', () => {
    it('unsupported operations fail permanently with a helpful message', async () => {
      const res = await push(tokenA, [op({ module: 'payments', operationType: 'settle', payload: { amount: 10 } })]).expect(200);
      expect(res.body.results[0]).toMatchObject({ status: 'FAILED_PERMANENT', errorCode: 'UNSUPPORTED_OPERATION' });
    });

    it('invalid payloads fail permanently and nothing is written', async () => {
      const before = await countRows('select count(*) n from stock_movements');
      const res = await push(tokenA, [op({ payload: { productId: 'x', quantityDelta: 0, reason: 'GIFT' } })]).expect(200);
      expect(res.body.results[0]).toMatchObject({ status: 'FAILED_PERMANENT', errorCode: 'INVALID_PAYLOAD' });
      expect(await countRows('select count(*) n from stock_movements')).toBe(before);
    });

    it('rejects reusing a clientOperationId with a different key', async () => {
      const o = op();
      await push(tokenA, [o]).expect(200);
      const res = await push(tokenA, [{ ...o, idempotencyKey: `idem_${randomUUID()}` }]).expect(200);
      expect(res.body.results[0]).toMatchObject({ status: 'FAILED_PERMANENT', errorCode: 'OPERATION_ID_MISMATCH' });
    });
  });

  describe('dependencies', () => {
    it('a dependent op fails when its dependency failed in the same batch', async () => {
      const parent = op({ payload: { productId: 'insulin', quantityDelta: -5, reason: 'SALE' } });
      const child = op({ payload: { productId: 'insulin', quantityDelta: 1, reason: 'RETURN' }, dependsOn: [parent.clientOperationId] });
      const res = await push(tokenA, [parent, child]).expect(200);
      expect(res.body.results[1]).toMatchObject({ status: 'FAILED_PERMANENT', errorCode: 'DEPENDENCY_FAILED' });
    });

    it('a dependent op waits when its dependency has not arrived yet', async () => {
      const child = op({ dependsOn: [randomUUID()] });
      const res = await push(tokenA, [child]).expect(200);
      expect(res.body.results[0]).toMatchObject({ status: 'RETRYABLE_FAILURE', errorCode: 'DEPENDENCY_NOT_SYNCED' });
    });

    it('dependencies earlier in the batch are honoured', async () => {
      const parent = op({ payload: { productId: 'cetirizine', quantityDelta: 4, reason: 'PURCHASE' } });
      const child = op({ payload: { productId: 'cetirizine', quantityDelta: -4, reason: 'SALE' }, dependsOn: [parent.clientOperationId] });
      const res = await push(tokenA, [parent, child]).expect(200);
      expect(res.body.results.map((r: { status: string }) => r.status)).toEqual(['SYNCED', 'SYNCED']);
    });
  });

  describe('conflicts (optimistic concurrency)', () => {
    const profileOp = (baseVersion: number, fields: Record<string, string>) =>
      op({ module: 'shop', operationType: 'profile_update', baseVersion, payload: { fields } });

    it('stale edit from another device returns CONFLICT with both values and is not applied', async () => {
      const a = await push(tokenA, [profileOp(0, { phone: '+91 98000 10234', address: '12 Main Rd' })], shop1, 'device-A').expect(200);
      expect(a.body.results[0]).toMatchObject({ status: 'SYNCED', version: 1 });

      const staleOp = profileOp(0, { phone: '+91 98000 10243', address: '12 Main Road, Ward 4' });
      const b = await push(tokenB, [staleOp], shop1, 'device-B').expect(200);
      expect(b.body.results[0]).toMatchObject({
        status: 'CONFLICT',
        errorCode: 'VERSION_CONFLICT',
        conflict: {
          entity: 'shop_profile',
          serverVersion: 1,
          serverValues: { phone: '+91 98000 10234', address: '12 Main Rd' },
          clientValues: { phone: '+91 98000 10243', address: '12 Main Road, Ward 4' },
          clientBaseVersion: 0,
        },
      });
      const [profile] = await ctx.q('select phone, version from shop_profiles where store_id = $1', [shop1]);
      expect(profile).toMatchObject({ phone: '+91 98000 10234', version: 1 });

      // Retrying the conflicted op replays the same conflict (no blind overwrite).
      const again = await push(tokenB, [staleOp], shop1, 'device-B').expect(200);
      expect(again.body.results[0].status).toBe('CONFLICT');

      // "Keep this device version" = a NEW operation based on the server version.
      const resolved = await push(tokenB, [profileOp(1, { phone: '+91 98000 10243', address: '12 Main Road, Ward 4' })], shop1, 'device-B').expect(200);
      expect(resolved.body.results[0]).toMatchObject({ status: 'SYNCED', version: 2 });

      // The device closes the conflicted op in the server's audit trail.
      const closed = await http()
        .post(`/sync/operations/${staleOp.clientOperationId}/cancel`)
        .set('Authorization', `Bearer ${tokenB}`)
        .send({ storeId: shop1, deviceId: 'device-B', idempotencyKey: staleOp.idempotencyKey, module: 'shop', operationType: 'profile_update' })
        .expect(200);
      expect(closed.body.status).toBe('CANCELLED');
    });
  });

  describe('tenant isolation & revoked access', () => {
    it('rejects a storeId the user is not a member of', async () => {
      const res = await push(tokenA, [op()], shop2).expect(403);
      expect(res.body.error.code).toBe('STORE_ACCESS_DENIED');
      expect(await countRows('select count(*) n from stock_movements where store_id = $1', [shop2])).toBe(0);
    });

    it('stops syncing when membership is revoked or the shop is suspended while offline', async () => {
      await ctx.q(`update store_members set status = 'REMOVED' where user_id = $1 and store_id = $2`, [userB, shop1]);
      const removed = await push(tokenB, [op()], shop1).expect(403);
      expect(removed.body.error.code).toBe('STORE_ACCESS_DENIED');
      await ctx.q(`update store_members set status = 'ACTIVE' where user_id = $1 and store_id = $2`, [userB, shop1]);

      await ctx.q(`update stores set status = 'SUSPENDED' where id = $1`, [shop2]);
      const suspended = await push(tokenB, [op()], shop2).expect(403);
      expect(suspended.body.error.code).toBe('STORE_SUSPENDED');
      await ctx.q(`update stores set status = 'ACTIVE' where id = $1`, [shop2]);

      await ctx.q(`update users set status = 'DISABLED' where id = $1`, [userB]);
      const disabled = await push(tokenB, [op()], shop2).expect(403);
      expect(disabled.body.error.code).toBe('USER_DISABLED');
      await ctx.q(`update users set status = 'ACTIVE' where id = $1`, [userB]);
    });
  });

  describe('cancel', () => {
    it('cancels an unsent op; a late retry of it is never applied', async () => {
      const o = op({ payload: { productId: 'cancel-me', quantityDelta: 7, reason: 'PURCHASE' } });
      const res = await http()
        .post(`/sync/operations/${o.clientOperationId}/cancel`)
        .set('Authorization', `Bearer ${tokenA}`)
        .send({ storeId: shop1, deviceId: 'device-1', idempotencyKey: o.idempotencyKey, module: o.module, operationType: o.operationType })
        .expect(200);
      expect(res.body.status).toBe('CANCELLED');

      const late = await push(tokenA, [o]).expect(200);
      expect(late.body.results[0]).toMatchObject({ status: 'FAILED_PERMANENT', errorCode: 'OPERATION_CANCELLED' });
      expect(await ledgerCount('cancel-me')).toBe(0);
    });

    it('refuses to cancel a committed op', async () => {
      const o = op();
      await push(tokenA, [o]).expect(200);
      const res = await http()
        .post(`/sync/operations/${o.clientOperationId}/cancel`)
        .set('Authorization', `Bearer ${tokenA}`)
        .send({ storeId: shop1, deviceId: 'device-1', idempotencyKey: o.idempotencyKey, module: o.module, operationType: o.operationType })
        .expect(409);
      expect(res.body.error.code).toBe('ALREADY_COMMITTED');
    });
  });

  describe('pull & status', () => {
    it('pages through changes after a cursor and records the acknowledged cursor', async () => {
      const all = await http()
        .get('/sync/pull')
        .set('Authorization', `Bearer ${tokenA}`)
        .query({ storeId: shop1, deviceId: 'device-pull', limit: 500 })
        .expect(200);
      expect(all.body.hasMore).toBe(false);
      expect(all.body.changes.length).toBeGreaterThan(3);
      const seqs = all.body.changes.map((c: { seq: number }) => c.seq);
      expect(seqs).toEqual([...seqs].sort((a, b) => a - b));

      const page1 = await http()
        .get('/sync/pull')
        .set('Authorization', `Bearer ${tokenA}`)
        .query({ storeId: shop1, deviceId: 'device-pull', limit: 2 })
        .expect(200);
      expect(page1.body.changes).toHaveLength(2);
      expect(page1.body.hasMore).toBe(true);

      const cursor = all.body.nextCursor;
      await push(tokenA, [op({ payload: { productId: 'new-after-cursor', quantityDelta: 1, reason: 'PURCHASE' } })]).expect(200);
      const delta = await http()
        .get('/sync/pull')
        .set('Authorization', `Bearer ${tokenA}`)
        .query({ storeId: shop1, deviceId: 'device-pull', cursor })
        .expect(200);
      expect(delta.body.changes).toHaveLength(1);
      expect(delta.body.changes[0]).toMatchObject({ entity: 'stock_balance', entityId: 'new-after-cursor', data: { quantity: 1 } });

      // A cursor from another database (ahead of this feed) restarts from the beginning.
      const stale = await http()
        .get('/sync/pull')
        .set('Authorization', `Bearer ${tokenA}`)
        .query({ storeId: shop1, deviceId: 'device-stale', cursor: '999999', limit: 500 })
        .expect(200);
      expect(stale.body.resetCursor).toBe(true);
      expect(stale.body.changes.length).toBeGreaterThan(3);

      // Other shops never see these changes.
      const other = await http()
        .get('/sync/pull')
        .set('Authorization', `Bearer ${tokenB}`)
        .query({ storeId: shop2, deviceId: 'device-x' })
        .expect(200);
      expect(other.body.changes).toHaveLength(0);

      const [device] = await ctx.q<{ last_sync_cursor: string; last_successful_sync_at: Date }>(
        'select last_sync_cursor, last_successful_sync_at from user_devices where user_id = $1 and device_id = $2',
        [userA, 'device-pull'],
      );
      expect(device?.last_sync_cursor).toBe(cursor);
      expect(device?.last_successful_sync_at).toBeInstanceOf(Date);
    });

    it('reports per-device status counts and supported operations', async () => {
      const res = await http()
        .get('/sync/status')
        .set('Authorization', `Bearer ${tokenA}`)
        .query({ storeId: shop1, deviceId: 'device-1' })
        .expect(200);
      expect(res.body.counts.synced).toBeGreaterThan(0);
      expect(res.body.counts.failed).toBeGreaterThan(0);
      expect(res.body.counts.cancelled).toBe(1);
      expect(res.body.supportedOperations).toEqual(['inventory.stock_movement', 'shop.profile_update']);
    });

    it('reads a single operation without exposing its payload', async () => {
      const o = op();
      await push(tokenA, [o]).expect(200);
      const res = await http()
        .get(`/sync/operations/${o.clientOperationId}`)
        .set('Authorization', `Bearer ${tokenA}`)
        .query({ storeId: shop1 })
        .expect(200);
      expect(res.body).toMatchObject({ status: 'SYNCED', attemptCount: 1, module: 'inventory' });
      expect(res.body.payload).toBeUndefined();

      await http()
        .get(`/sync/operations/${o.clientOperationId}`)
        .set('Authorization', `Bearer ${tokenB}`)
        .query({ storeId: shop2 })
        .expect(404);
    });
  });
});
