import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { seedMember, startApp, type TestApp } from './support/app.js';

const PDF = Buffer.concat([Buffer.from('%PDF-1.7\n'), Buffer.alloc(32, 1)]);

describe('Support console API (e2e)', () => {
  let ctx: TestApp;
  const owner = randomUUID();
  const otherOwner = randomUUID();
  const agent = randomUUID();
  const agent2 = randomUUID();
  const shop = randomUUID();
  const otherShop = randomUUID();
  const tk: Record<string, string> = {};
  const http = () => request(ctx.app.getHttpServer());
  const as = (t: string) => ({ Authorization: `Bearer ${t}` });

  const createTicket = (token: string, storeId: string, over: Record<string, unknown> = {}) =>
    http()
      .post('/tickets')
      .set(as(token))
      .send({
        storeId,
        clientRequestId: randomUUID(),
        subject: 'Sync stuck at 3 of 8',
        description: 'Outbox has not cleared after reconnect since yesterday.',
        category: 'SYNC',
        ...over,
      })
      .expect(201)
      .then((r) => r.body);

  beforeAll(async () => {
    ctx = await startApp('support_admin_test');
    await seedMember(ctx, { userId: owner, storeId: shop });
    await seedMember(ctx, { userId: otherOwner, storeId: otherShop });
    await ctx.q(`update users set name = 'Ravi (owner)' where id = $1`, [owner]);
    await ctx.q(`update stores set name = 'Sri Sai Medicals' where id = $1`, [shop]);
    await ctx.q(`update stores set name = 'City Pharmacy' where id = $1`, [otherShop]);
    await ctx.q(`insert into users (id, status, name, roles) values ($1, 'ACTIVE', 'Asha (support)', '{SUPPORT_AGENT}'), ($2, 'ACTIVE', 'Bala (support)', '{SUPPORT_AGENT}')`, [
      agent,
      agent2,
    ]);
    tk.owner = await ctx.token(owner);
    tk.other = await ctx.token(otherOwner);
    tk.agent = await ctx.token(agent);
    tk.agent2 = await ctx.token(agent2);
  }, 120_000);

  afterAll(async () => ctx?.stop());

  it('is support-staff only', async () => {
    const res = await http().get('/admin/tickets').set(as(tk.owner)).expect(403);
    expect(res.body.error.code).toBe('SUPPORT_ONLY');
    await http().get('/admin/tickets').expect(401);
  });

  it('queues tickets from every shop with views, counts, search and sorting', async () => {
    const a = await createTicket(tk.owner, shop, { subject: 'Printer offline', priority: 'LOW' });
    const b = await createTicket(tk.other, otherShop, { subject: 'Payment stuck pending', priority: 'CRITICAL', category: 'BUG' });

    const open = await http().get('/admin/tickets').set(as(tk.agent)).expect(200);
    expect(open.body.total).toBe(2);
    expect(open.body.tickets[0]).toMatchObject({ id: b.id, priority: 'CRITICAL', shop: { name: 'City Pharmacy' }, needsReply: true, assignee: null });
    expect(open.body.tickets[1]).toMatchObject({ id: a.id, shop: { name: 'Sri Sai Medicals' }, requesterName: 'Ravi (owner)' });

    const byShop = await http().get('/admin/tickets').set(as(tk.agent)).query({ q: 'sri sai' }).expect(200);
    expect(byShop.body.tickets.map((t: { id: string }) => t.id)).toEqual([a.id]);
    const byShopId = await http().get('/admin/tickets').set(as(tk.agent)).query({ storeId: otherShop }).expect(200);
    expect(byShopId.body.tickets.map((t: { id: string }) => t.id)).toEqual([b.id]);

    const stats = await http().get('/admin/tickets/stats').set(as(tk.agent)).expect(200);
    expect(stats.body).toMatchObject({ needs_reply: 2, unassigned: 2, mine: 0, open: 2, critical_open: 1, all: 2 });

    const agents = await http().get('/admin/agents').set(as(tk.agent)).expect(200);
    expect(agents.body.agents.map((x: { name: string }) => x.name)).toEqual(['Asha (support)', 'Bala (support)']);
  });

  it('full ticket view: shop, requester, related operation with its attempt history', async () => {
    // A failed sync operation in the shop that the ticket points to.
    const opId = randomUUID();
    await ctx.q(
      `insert into sync_operations (client_operation_id, idempotency_key, store_id, user_id, device_id, module, operation_type, status, attempt_count, last_error_code, last_error_message)
       values ($1, 'idem_x1', $2, $3, 'device-7', 'inventory', 'stock_movement', 'FAILED', 1, 'INSUFFICIENT_STOCK', 'Stock quantity exceeds available balance.')`,
      [opId, shop, owner],
    );
    await ctx.q(
      `insert into sync_logs (store_id, user_id, device_id, operation_id, action, result, error_code, duration_ms) values ($1, $2, 'device-7', $3, 'PUSH', 'FAILED_PERMANENT', 'INSUFFICIENT_STOCK', 12)`,
      [shop, owner, opId],
    );
    const t = await createTicket(tk.owner, shop, { relatedOperationId: opId, relatedModule: 'inventory' });

    const d = await http().get(`/admin/tickets/${t.id}`).set(as(tk.agent)).expect(200);
    expect(d.body).toMatchObject({
      ticketNumber: t.ticketNumber,
      shop: { id: shop, name: 'Sri Sai Medicals', status: 'ACTIVE' },
      requester: { id: owner, name: 'Ravi (owner)', role: 'OWNER' },
      assignee: null,
      canReply: true,
      relatedOperation: {
        receivedByServer: true,
        status: 'FAILED',
        lastErrorCode: 'INSUFFICIENT_STOCK',
        deviceId: 'device-7',
        attempts: [expect.objectContaining({ action: 'PUSH', result: 'FAILED_PERMANENT', errorCode: 'INSUFFICIENT_STOCK' })],
      },
    });
    expect(d.body.events[0]).toMatchObject({ type: 'CREATED', authorName: 'Ravi (owner)', visibility: 'PUBLIC' });

    await http().get(`/admin/tickets/${randomUUID()}`).set(as(tk.agent)).expect(404);
    await http().get('/admin/tickets/not-a-uuid').set(as(tk.agent)).expect(404);
  });

  it('assign, internal note, ask for info, resolve with summary — shop sees only the public parts', async () => {
    const t = await createTicket(tk.owner, shop, { subject: 'Wrong invoice total' });
    const base = `/admin/tickets/${t.id}`;

    let d = (await http().patch(`${base}/assignee`).set(as(tk.agent)).send({ assigneeUserId: agent2 }).expect(200)).body;
    expect(d.assignee).toMatchObject({ id: agent2, name: 'Bala (support)' });
    await http().patch(`${base}/assignee`).set(as(tk.agent)).send({ assigneeUserId: owner }).expect(400);

    d = (await http().patch(`${base}/priority`).set(as(tk.agent2)).send({ priority: 'HIGH' }).expect(200)).body;
    expect(d.priority).toBe('HIGH');

    d = (
      await http()
        .post(`${base}/messages`)
        .set(as(tk.agent2))
        .send({ clientRequestId: randomUUID(), body: 'Looks like a rounding bug in GST; checking with billing.', internal: true })
        .expect(201)
    ).body;
    expect(d.status).toBe('OPEN'); // notes never move the ticket
    expect(d.events.at(-1)).toMatchObject({ type: 'NOTE', visibility: 'INTERNAL', authorName: 'Bala (support)' });

    d = (await http().post(`${base}/messages`).set(as(tk.agent2)).send({ clientRequestId: randomUUID(), body: 'Which invoice number shows this?' }).expect(201)).body;
    expect(d.status).toBe('IN_PROGRESS');
    d = (await http().patch(`${base}/status`).set(as(tk.agent2)).send({ status: 'WAITING_FOR_USER' }).expect(200)).body;
    expect(d.status).toBe('WAITING_FOR_USER');

    const noSummary = await http().patch(`${base}/status`).set(as(tk.agent2)).send({ status: 'RESOLVED' }).expect(400);
    expect(JSON.stringify(noSummary.body)).toMatch(/resolution summary/);
    d = (
      await http()
        .patch(`${base}/status`)
        .set(as(tk.agent2))
        .send({ status: 'RESOLVED', note: 'Fixed the GST rounding; invoices now match the till.' })
        .expect(200)
    ).body;
    expect(d.status).toBe('RESOLVED');
    expect(d.resolvedAt).toBeTruthy();

    // The shop's view of the same ticket.
    const shopView = (await http().get(`/tickets/${t.id}`).set(as(tk.owner)).query({ storeId: shop }).expect(200)).body;
    const types = shopView.events.map((e: { type: string }) => e.type);
    expect(types).not.toContain('NOTE');
    expect(types).not.toContain('ASSIGNMENT');
    expect(types).not.toContain('PRIORITY_CHANGE');
    expect(JSON.stringify(shopView)).not.toMatch(/rounding bug|Bala|authorUserId|INTERNAL/);
    expect(shopView.events.at(-1)).toMatchObject({ type: 'STATUS_CHANGE', toStatus: 'RESOLVED', body: 'Fixed the GST rounding; invoices now match the till.' });
    expect(shopView.priority).toBe('HIGH');

    // Support can reopen; invalid jumps are refused.
    d = (await http().patch(`${base}/status`).set(as(tk.agent)).send({ status: 'IN_PROGRESS' }).expect(200)).body;
    expect(d.status).toBe('IN_PROGRESS');
    expect(d.resolvedAt).toBeNull();
    await http().patch(`${base}/status`).set(as(tk.agent)).send({ status: 'OPEN' }).expect(400);

    // Audit trail is complete for staff.
    const audit = await ctx.q<{ type: string; visibility: string }>(`select type, visibility from ticket_events where ticket_id = $1 order by seq`, [t.id]);
    expect(audit.map((e) => `${e.type}/${e.visibility}`)).toEqual([
      'CREATED/PUBLIC',
      'ASSIGNMENT/INTERNAL',
      'PRIORITY_CHANGE/INTERNAL',
      'NOTE/INTERNAL',
      'MESSAGE/PUBLIC',
      'STATUS_CHANGE/PUBLIC',
      'STATUS_CHANGE/PUBLIC',
      'STATUS_CHANGE/PUBLIC',
      'STATUS_CHANGE/PUBLIC',
    ]);

    const mine = await http().get('/admin/tickets').set(as(tk.agent2)).query({ view: 'mine' }).expect(200);
    expect(mine.body.tickets.map((x: { id: string }) => x.id)).toContain(t.id);
  });

  it('support can attach files to replies; staff and the shop can download them', async () => {
    const t = await createTicket(tk.owner, shop, { subject: 'Need the report' });
    const file = (await http().post(`/admin/tickets/${t.id}/attachments`).set(as(tk.agent)).attach('file', PDF, 'report.pdf').expect(201)).body;
    await http()
      .post(`/admin/tickets/${t.id}/messages`)
      .set(as(tk.agent))
      .send({ clientRequestId: randomUUID(), body: 'Here is the report.', attachmentIds: [file.id] })
      .expect(201);
    await http().get(`/admin/tickets/${t.id}/attachments/${file.id}`).set(as(tk.agent)).expect(200);
    await http().get(`/tickets/${t.id}/attachments/${file.id}`).set(as(tk.owner)).query({ storeId: shop }).expect(200);
  });
});
