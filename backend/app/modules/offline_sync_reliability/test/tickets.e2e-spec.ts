import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { seedMember, startApp } from './support/app.js';

const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(64, 7)]);
const PDF = Buffer.concat([Buffer.from('%PDF-1.7\n'), Buffer.alloc(32, 1)]);

describe('Support tickets API (e2e)', () => {
  let ctx: Awaited<ReturnType<typeof startApp>>;
  const owner = randomUUID();
  const staff = randomUUID();
  const otherShopUser = randomUUID();
  const agent = randomUUID();
  const shop = randomUUID();
  const otherShop = randomUUID();
  const tk: Record<string, string> = {};

  const http = () => request(ctx.app.getHttpServer());
  const countTickets = async (subject: string) =>
    Number((await ctx.q<{ n: string }>('select count(*) n from tickets where subject = $1', [subject]))[0].n);
  const sid = shop;

  const newTicket = (over: Record<string, unknown> = {}) => ({
    storeId: sid,
    clientRequestId: randomUUID(),
    subject: 'Sync stuck at 3 of 8',
    description: 'Outbox has not cleared after reconnect since yesterday evening.',
    category: 'SYNC',
    ...over,
  });
  const create = (body: object, as = tk.owner) => http().post('/tickets').set('Authorization', `Bearer ${as}`).send(body);
  const reply = (id: string, body: string, as = tk.owner, clientRequestId = randomUUID(), storeId = sid) =>
    http().post(`/tickets/${id}/messages`).set('Authorization', `Bearer ${as}`).send({ storeId, clientRequestId, body });
  const setStatus = (id: string, status: string, as = tk.agent) =>
    http().patch(`/tickets/${id}/status`).set('Authorization', `Bearer ${as}`).send({ storeId: sid, status });
  const upload = (buf: Buffer, name: string, as = tk.owner, storeId = sid) =>
    http().post('/tickets/attachments').set('Authorization', `Bearer ${as}`).field('storeId', storeId).attach('file', buf, name);

  beforeAll(async () => {
    ctx = await startApp('tickets_test');
    await seedMember(ctx, { userId: owner, storeId: shop, role: 'OWNER' });
    await seedMember(ctx, { userId: staff, storeId: shop, role: 'STAFF' });
    await seedMember(ctx, { userId: otherShopUser, storeId: otherShop, role: 'OWNER' });
    await ctx.q(`insert into users (id, status, roles) values ($1, 'ACTIVE', '{SUPPORT_AGENT}')`, [agent]);
    tk.owner = await ctx.token(owner);
    tk.staff = await ctx.token(staff);
    tk.other = await ctx.token(otherShopUser);
    tk.agent = await ctx.token(agent);
  }, 120_000);

  afterAll(async () => ctx?.stop());

  describe('create', () => {
    it('creates an OPEN ticket with a number, default priority and a CREATED event', async () => {
      const res = await create(newTicket({ relatedOperationId: randomUUID(), relatedModule: 'inventory' })).expect(201);
      expect(res.body).toMatchObject({ status: 'OPEN', priority: 'NORMAL', category: 'SYNC', relatedModule: 'inventory', canReply: true, canClose: true });
      expect(res.body.ticketNumber).toMatch(/^TKT-\d{4,}$/);
      expect(res.body.events).toHaveLength(1);
      expect(res.body.events[0]).toMatchObject({ type: 'CREATED', authorRole: 'USER', byViewer: true, toStatus: 'OPEN' });
    });

    it('double submit returns the same ticket instead of a duplicate', async () => {
      const body = newTicket({ subject: 'Double tap' });
      const [a, b, c] = await Promise.all([create(body), create(body), create(body)]);
      const ids = new Set([a.body.id, b.body.id, c.body.id]);
      expect(ids.size).toBe(1);
      expect([a.status, b.status, c.status].sort()).toEqual([200, 200, 201]);
      expect(await countTickets('Double tap')).toBe(1);
    });

    it('validates the form like spec §8.2 (trimmed)', async () => {
      const res = await create(newTicket({ subject: '  Hi  ', description: 'Broken', category: undefined })).expect(400);
      const details: string[] = res.body.error.details;
      expect(details).toEqual(
        expect.arrayContaining(['Subject must be 3–120 characters.', 'Description must be 10–5,000 characters.', 'Choose a category.']),
      );
      await create(newTicket({ priority: 'URGENT' })).expect(400);
    });

    it('support staff cannot open tickets on behalf of a shop', async () => {
      const res = await create(newTicket(), tk.agent).expect(403);
      expect(res.body.error.code).toBe('SHOP_MEMBERS_ONLY');
    });
  });

  describe('visibility', () => {
    it('lists only the shop’s tickets, with filters, search and paging', async () => {
      await create(newTicket({ subject: 'Login page slow', category: 'BUG', priority: 'LOW' })).expect(201);
      await create(newTicket({ subject: 'Wrong invoice total', category: 'DATA_CONFLICT', priority: 'HIGH' }), tk.staff).expect(201);
      await create({ ...newTicket({ subject: 'Other shop issue' }), storeId: otherShop }, tk.other).expect(201);

      const all = await http().get('/tickets').set('Authorization', `Bearer ${tk.owner}`).query({ storeId: sid }).expect(200);
      expect(all.body.tickets.map((t: { subject: string }) => t.subject)).not.toContain('Other shop issue');
      expect(all.body.tickets[0].subject).toBe('Wrong invoice total'); // most recently updated first

      const bugs = await http().get('/tickets').set('Authorization', `Bearer ${tk.owner}`).query({ storeId: sid, category: 'BUG' }).expect(200);
      expect(bugs.body.tickets.map((t: { subject: string }) => t.subject)).toEqual(['Login page slow']);

      const search = await http().get('/tickets').set('Authorization', `Bearer ${tk.owner}`).query({ storeId: sid, q: 'login (' }).expect(200);
      expect(search.body.tickets).toHaveLength(0); // regex characters are escaped, not interpreted
      const byNumber = await http()
        .get('/tickets')
        .set('Authorization', `Bearer ${tk.owner}`)
        .query({ storeId: sid, q: all.body.tickets[1].ticketNumber })
        .expect(200);
      expect(byNumber.body.tickets).toHaveLength(1);

      const page1 = await http().get('/tickets').set('Authorization', `Bearer ${tk.owner}`).query({ storeId: sid, limit: 2 }).expect(200);
      expect(page1.body.tickets).toHaveLength(2);
      const page2 = await http()
        .get('/tickets')
        .set('Authorization', `Bearer ${tk.owner}`)
        .query({ storeId: sid, limit: 2, cursor: page1.body.nextCursor })
        .expect(200);
      const ids = [...page1.body.tickets, ...page2.body.tickets].map((t: { id: string }) => t.id);
      expect(new Set(ids).size).toBe(ids.length);
    });

    it('other shops get 403 for the store and 404 for the ticket; support can read any shop', async () => {
      const t = (await create(newTicket({ subject: 'Private to shop' })).expect(201)).body;
      const denied = await http().get('/tickets').set('Authorization', `Bearer ${tk.other}`).query({ storeId: sid }).expect(403);
      expect(denied.body.error.code).toBe('STORE_ACCESS_DENIED');
      await http()
        .get(`/tickets/${t.id}`)
        .set('Authorization', `Bearer ${tk.other}`)
        .query({ storeId: otherShop })
        .expect(404);
      await http().get(`/tickets/${t.id}`).set('Authorization', `Bearer ${tk.staff}`).query({ storeId: sid }).expect(200);
      await http().get(`/tickets/${t.id}`).set('Authorization', `Bearer ${tk.agent}`).query({ storeId: sid }).expect(200);
    });
  });

  describe('lifecycle', () => {
    it('OPEN → IN_PROGRESS → WAITING_FOR_USER → IN_PROGRESS → RESOLVED → reopened → CLOSED', async () => {
      const t = (await create(newTicket({ subject: 'Lifecycle' })).expect(201)).body;

      let r = await reply(t.id, 'We are checking the outbox on your device.', tk.agent).expect(200);
      expect(r.body.status).toBe('IN_PROGRESS');
      expect(r.body.events.at(-2)).toMatchObject({ type: 'MESSAGE', authorRole: 'SUPPORT', byViewer: true });

      r = await setStatus(t.id, 'WAITING_FOR_USER').expect(200);
      expect(r.body.status).toBe('WAITING_FOR_USER');

      const key = randomUUID();
      r = await reply(t.id, 'It still says 3 of 8.', tk.owner, key).expect(200);
      expect(r.body.status).toBe('IN_PROGRESS');
      await reply(t.id, 'It still says 3 of 8.', tk.owner, key).expect(200); // double send
      const msgs = (await http().get(`/tickets/${t.id}`).set('Authorization', `Bearer ${tk.owner}`).query({ storeId: sid })).body.events.filter(
        (e: { type: string; authorRole: string }) => e.type === 'MESSAGE' && e.authorRole === 'USER',
      );
      expect(msgs).toHaveLength(1);

      r = await setStatus(t.id, 'RESOLVED').expect(200);
      expect(r.body.resolvedAt).toBeTruthy();

      r = await reply(t.id, 'It happened again today.').expect(200);
      expect(r.body.status).toBe('OPEN'); // reopened within the window

      const bad = await setStatus(t.id, 'IN_PROGRESS', tk.owner).expect(400);
      expect(bad.body.error.code).toBe('INVALID_STATUS_TRANSITION');

      const notOwner = await setStatus(t.id, 'CLOSED', tk.staff).expect(403);
      expect(notOwner.body.error.code).toBe('NOT_TICKET_OWNER');

      r = await setStatus(t.id, 'CLOSED', tk.owner).expect(200);
      expect(r.body).toMatchObject({ status: 'CLOSED', canReply: false, canClose: false });

      const closed = await reply(t.id, 'One more thing').expect(409);
      expect(closed.body.error.code).toBe('TICKET_CLOSED');
      await setStatus(t.id, 'OPEN').expect(400);

      const audit = await ctx.q<{ from_status: string; to_status: string }>(
        `select from_status, to_status from ticket_events where ticket_id = $1 and type = 'STATUS_CHANGE' order by seq`,
        [t.id],
      );
      expect(audit.map((e) => `${e.from_status}>${e.to_status}`)).toEqual([
        'OPEN>IN_PROGRESS',
        'IN_PROGRESS>WAITING_FOR_USER',
        'WAITING_FOR_USER>IN_PROGRESS',
        'IN_PROGRESS>RESOLVED',
        'RESOLVED>OPEN',
        'OPEN>CLOSED',
      ]);
    });

    it('a resolved ticket past the reopen window cannot be replied to', async () => {
      const t = (await create(newTicket({ subject: 'Old resolved' })).expect(201)).body;
      await setStatus(t.id, 'RESOLVED').expect(200);
      await ctx.q(`update tickets set resolved_at = now() - interval '30 days' where id = $1`, [t.id]);
      const r = await reply(t.id, 'Still broken').expect(409);
      expect(r.body.error.message).toMatch(/Create a new ticket/);
    });
  });

  describe('attachments', () => {
    it('accepts real PDF/PNG files, rejects disguised or oversized ones', async () => {
      const png = await upload(PNG, '../../etc/screen shot!.png').expect(201);
      expect(png.body).toMatchObject({ contentType: 'image/png', fileName: 'screen shot.png', size: PNG.length });
      await upload(PDF, 'invoice.pdf').expect(201);

      const fake = await upload(Buffer.from('#!/bin/sh\nrm -rf /'), 'photo.png').expect(400);
      expect(fake.body.error.code).toBe('FILE_TYPE_NOT_ALLOWED');

      const big = Buffer.concat([PNG, Buffer.alloc(10 * 1024 * 1024)]);
      await upload(big, 'big.png').expect(413);
    });

    it('attaches once, downloads only within the shop, as a download', async () => {
      const file = (await upload(PDF, 'invoice.pdf').expect(201)).body;
      const t = (await create(newTicket({ subject: 'With file', attachmentIds: [file.id] })).expect(201)).body;
      expect(t.attachments).toEqual([expect.objectContaining({ id: file.id, fileName: 'invoice.pdf' })]);

      const reused = await create(newTicket({ subject: 'Reuse', attachmentIds: [file.id] })).expect(400);
      expect(reused.body.error.code).toBe('ATTACHMENT_INVALID');
      expect(await countTickets('Reuse')).toBe(0); // rolled back

      const someoneElses = (await upload(PNG, 'x.png', tk.staff).expect(201)).body;
      await create(newTicket({ subject: 'Steal', attachmentIds: [someoneElses.id] })).expect(400);

      const dl = await http()
        .get(`/tickets/${t.id}/attachments/${file.id}`)
        .set('Authorization', `Bearer ${tk.staff}`)
        .query({ storeId: sid })
        .buffer(true)
        .parse((res, cb) => {
          const chunks: Buffer[] = [];
          res.on('data', (c: Buffer) => chunks.push(c));
          res.on('end', () => cb(null, Buffer.concat(chunks)));
        })
        .expect(200);
      expect(Buffer.compare(dl.body as Buffer, PDF)).toBe(0);
      expect(dl.headers['content-disposition']).toBe('attachment; filename="invoice.pdf"');
      expect(dl.headers['x-content-type-options']).toBe('nosniff');

      await http()
        .get(`/tickets/${t.id}/attachments/${file.id}`)
        .set('Authorization', `Bearer ${tk.other}`)
        .query({ storeId: otherShop })
        .expect(404);
    });
  });
});
