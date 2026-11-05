import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, count, desc, eq, ilike, inArray, isNull, or, type SQL, sql } from 'drizzle-orm';
import { alias } from 'drizzle-orm/pg-core';
import { isUuid } from '../common/store-access/store-access.service.js';
import { type Db, InjectDb } from '../db/db.module.js';
import {
  storeMembers,
  stores,
  syncLogs,
  syncOperations,
  ticketEvents,
  tickets,
  type TicketPriority,
  type TicketStatus,
  users,
} from '../db/schema.js';
import { AttachmentsService, type UploadedFile } from '../tickets/attachments.service.js';
import { type Actor, type TicketRow, TicketsService } from '../tickets/tickets.service.js';
import type { AdminListDto, AdminReplyDto, AdminStatusDto, AssignDto, PriorityDto, QueueView } from './dto.js';

const ACTIVE: TicketStatus[] = ['OPEN', 'IN_PROGRESS', 'WAITING_FOR_USER'];
const PRIORITY_RANK = sql`case ${tickets.priority} when 'CRITICAL' then 0 when 'HIGH' then 1 when 'NORMAL' then 2 else 3 end`;
const requester = alias(users, 'requester');
const assignee = alias(users, 'assignee');

/**
 * Platform support console (cross-shop). Every write goes through TicketsService's
 * shared workflow, so lifecycle rules, audit events and duplicate protection are the
 * same as in the shop app.
 */
@Injectable()
export class SupportAdminService {
  constructor(
    @InjectDb() private readonly db: Db,
    private readonly tickets: TicketsService,
    private readonly attachments: AttachmentsService,
  ) {}

  private actor(agentId: string, t: TicketRow): Actor {
    return { userId: agentId, storeId: t.storeId, role: 'SUPPORT' };
  }

  private async ticket(id: string): Promise<TicketRow> {
    const t = isUuid(id) ? await this.tickets.loadById(id) : undefined;
    if (!t) throw new NotFoundException({ code: 'TICKET_NOT_FOUND', message: 'Ticket not found.' });
    return t;
  }

  private viewWhere(view: QueueView, agentId: string): SQL | undefined {
    switch (view) {
      // The shop spoke last and the ticket is with support.
      case 'needs_reply':
        return and(inArray(tickets.status, ['OPEN', 'IN_PROGRESS']), eq(tickets.lastActivityBy, 'USER'));
      case 'unassigned':
        return and(inArray(tickets.status, ACTIVE), isNull(tickets.assignedToUserId));
      case 'mine':
        return and(inArray(tickets.status, ACTIVE), eq(tickets.assignedToUserId, agentId));
      case 'open':
        return inArray(tickets.status, ACTIVE);
      case 'waiting_user':
        return eq(tickets.status, 'WAITING_FOR_USER');
      case 'resolved':
        return eq(tickets.status, 'RESOLVED');
      case 'closed':
        return eq(tickets.status, 'CLOSED');
      default:
        return undefined;
    }
  }

  // --------------------------------------------------------------------- queue

  async list(agentId: string, q: AdminListDto) {
    const where: SQL[] = [];
    const view = this.viewWhere(q.view ?? 'open', agentId);
    if (view) where.push(view);
    if (q.status) where.push(eq(tickets.status, q.status as TicketStatus));
    if (q.priority) where.push(eq(tickets.priority, q.priority as TicketPriority));
    if (q.category) where.push(eq(tickets.category, q.category as typeof tickets.$inferSelect.category));
    if (q.storeId) where.push(eq(tickets.storeId, q.storeId));
    if (q.q) {
      const pattern = `%${q.q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
      where.push(or(ilike(tickets.subject, pattern), ilike(tickets.ticketNumber, pattern), ilike(stores.name, pattern))!);
    }
    const filter = where.length ? and(...where) : undefined;
    const pageSize = q.pageSize ?? 25;
    const page = q.page ?? 1;
    const order =
      q.sort === 'newest'
        ? [desc(tickets.updatedAt)]
        : q.sort === 'oldest'
          ? [asc(tickets.lastActivityAt)]
          : [asc(PRIORITY_RANK), asc(tickets.lastActivityAt)];

    const [rows, [{ total }]] = await Promise.all([
      this.db
        .select({
          t: tickets,
          storeName: stores.name,
          requesterName: requester.name,
          assigneeName: assignee.name,
        })
        .from(tickets)
        .leftJoin(stores, eq(stores.id, tickets.storeId))
        .leftJoin(requester, eq(requester.id, tickets.createdByUserId))
        .leftJoin(assignee, eq(assignee.id, tickets.assignedToUserId))
        .where(filter)
        .orderBy(...order, asc(tickets.id))
        .limit(pageSize)
        .offset((page - 1) * pageSize),
      this.db.select({ total: count() }).from(tickets).leftJoin(stores, eq(stores.id, tickets.storeId)).where(filter),
    ]);

    return {
      tickets: rows.map((r) => ({
        id: r.t.id,
        ticketNumber: r.t.ticketNumber,
        subject: r.t.subject,
        status: r.t.status,
        priority: r.t.priority,
        category: r.t.category,
        shop: { id: r.t.storeId, name: r.storeName },
        requesterName: r.requesterName,
        assignee: r.t.assignedToUserId ? { id: r.t.assignedToUserId, name: r.assigneeName } : null,
        lastActivityAt: r.t.lastActivityAt,
        lastActivityBy: r.t.lastActivityBy,
        needsReply: r.t.lastActivityBy === 'USER' && (r.t.status === 'OPEN' || r.t.status === 'IN_PROGRESS'),
        createdAt: r.t.createdAt,
        updatedAt: r.t.updatedAt,
      })),
      page,
      pageSize,
      total: Number(total),
    };
  }

  /** Sidebar counters, one query. */
  async stats(agentId: string) {
    const c = (cond: SQL | undefined) => sql<number>`count(*) filter (where ${cond ?? sql`true`})`.mapWith(Number);
    const [row] = await this.db
      .select({
        needs_reply: c(this.viewWhere('needs_reply', agentId)),
        unassigned: c(this.viewWhere('unassigned', agentId)),
        mine: c(this.viewWhere('mine', agentId)),
        open: c(this.viewWhere('open', agentId)),
        waiting_user: c(this.viewWhere('waiting_user', agentId)),
        resolved: c(this.viewWhere('resolved', agentId)),
        closed: c(this.viewWhere('closed', agentId)),
        all: count(),
        critical_open: c(and(inArray(tickets.status, ACTIVE), eq(tickets.priority, 'CRITICAL'))),
      })
      .from(tickets);
    return row;
  }

  async agents() {
    const rows = await this.db
      .select({ id: users.id, name: users.name })
      .from(users)
      .where(and(eq(users.status, 'ACTIVE'), sql`'SUPPORT_AGENT' = any(${users.roles})`))
      .orderBy(asc(users.name));
    return { agents: rows };
  }

  // -------------------------------------------------------------------- detail

  async detail(agentId: string, id: string) {
    const t = await this.ticket(id);
    const base = await this.tickets.detail(t, this.actor(agentId, t));

    const [[shop], [req], authorNames, related] = await Promise.all([
      this.db.select({ id: stores.id, name: stores.name, status: stores.status }).from(stores).where(eq(stores.id, t.storeId)),
      this.db
        .select({ id: users.id, name: users.name, role: storeMembers.role })
        .from(users)
        .leftJoin(storeMembers, and(eq(storeMembers.userId, users.id), eq(storeMembers.storeId, t.storeId)))
        .where(eq(users.id, t.createdByUserId)),
      this.names([...new Set(base.events.map((e) => (e as { authorUserId?: string }).authorUserId).filter((x): x is string => !!x)), ...(t.assignedToUserId ? [t.assignedToUserId] : [])]),
      this.relatedOperation(t),
    ]);

    return {
      ...base,
      shop: shop ?? { id: t.storeId, name: null, status: null },
      requester: req ? { id: req.id, name: req.name, role: req.role } : { id: t.createdByUserId, name: null, role: null },
      assignee: t.assignedToUserId ? { id: t.assignedToUserId, name: authorNames.get(t.assignedToUserId) ?? null } : null,
      relatedOperation: related,
      events: base.events.map((e) => ({ ...e, authorName: authorNames.get((e as { authorUserId?: string }).authorUserId ?? '') ?? null })),
    };
  }

  private async names(ids: string[]) {
    if (!ids.length) return new Map<string, string | null>();
    const rows = await this.db.select({ id: users.id, name: users.name }).from(users).where(inArray(users.id, ids));
    return new Map(rows.map((r) => [r.id, r.name]));
  }

  /** The operation the shop linked, with its live server status and attempt history. */
  private async relatedOperation(t: TicketRow) {
    if (!t.relatedOperationId) return null;
    const [op] = await this.db
      .select()
      .from(syncOperations)
      .where(and(eq(syncOperations.storeId, t.storeId), eq(syncOperations.clientOperationId, t.relatedOperationId)));
    if (!op) return { clientOperationId: t.relatedOperationId, module: t.relatedModule, receivedByServer: false, attempts: [] };
    const attempts = await this.db
      .select({
        action: syncLogs.action,
        result: syncLogs.result,
        errorCode: syncLogs.errorCode,
        durationMs: syncLogs.durationMs,
        requestId: syncLogs.requestId,
        timestamp: syncLogs.timestamp,
      })
      .from(syncLogs)
      .where(and(eq(syncLogs.storeId, t.storeId), eq(syncLogs.operationId, op.clientOperationId)))
      .orderBy(desc(syncLogs.timestamp))
      .limit(20);
    return {
      clientOperationId: op.clientOperationId,
      module: op.module,
      operationType: op.operationType,
      receivedByServer: true,
      status: op.status,
      serverResourceId: op.serverResourceId,
      attemptCount: op.attemptCount,
      lastErrorCode: op.lastErrorCode,
      lastErrorMessage: op.lastErrorMessage,
      deviceId: op.deviceId,
      createdAt: op.createdAt,
      processedAt: op.processedAt,
      attempts,
    };
  }

  // -------------------------------------------------------------------- writes

  async reply(agentId: string, id: string, dto: AdminReplyDto) {
    const t = await this.ticket(id);
    await this.tickets.replyAs(this.actor(agentId, t), t, dto);
    return this.detail(agentId, id);
  }

  async setStatus(agentId: string, id: string, dto: AdminStatusDto) {
    const t = await this.ticket(id);
    await this.tickets.changeStatusAs(this.actor(agentId, t), t, dto.status as TicketStatus, dto.note);
    return this.detail(agentId, id);
  }

  async assign(agentId: string, id: string, dto: AssignDto) {
    const t = await this.ticket(id);
    const to = dto.assigneeUserId;
    if (to) {
      const [agent] = await this.db
        .select({ id: users.id })
        .from(users)
        .where(and(eq(users.id, to), eq(users.status, 'ACTIVE'), sql`'SUPPORT_AGENT' = any(${users.roles})`));
      if (!agent) throw new BadRequestException({ code: 'NOT_AN_AGENT', message: 'Tickets can only be assigned to support staff.' });
    }
    if ((t.assignedToUserId ?? null) !== to) {
      await this.db.transaction(async (tx) => {
        await tx.update(tickets).set({ assignedToUserId: to, updatedAt: new Date() }).where(eq(tickets.id, t.id));
        await tx.insert(ticketEvents).values({
          ticketId: t.id,
          storeId: t.storeId,
          type: 'ASSIGNMENT',
          visibility: 'INTERNAL',
          authorUserId: agentId,
          authorRole: 'SUPPORT',
          meta: { from: t.assignedToUserId ?? null, to },
        });
      });
    }
    return this.detail(agentId, id);
  }

  async setPriority(agentId: string, id: string, dto: PriorityDto) {
    const t = await this.ticket(id);
    const to = dto.priority as TicketPriority;
    if (t.status === 'CLOSED') throw new BadRequestException({ code: 'TICKET_CLOSED', message: 'This ticket is closed.' });
    if (t.priority !== to) {
      await this.db.transaction(async (tx) => {
        await tx.update(tickets).set({ priority: to, updatedAt: new Date() }).where(eq(tickets.id, t.id));
        await tx.insert(ticketEvents).values({
          ticketId: t.id,
          storeId: t.storeId,
          type: 'PRIORITY_CHANGE',
          visibility: 'INTERNAL',
          authorUserId: agentId,
          authorRole: 'SUPPORT',
          meta: { from: t.priority, to },
        });
      });
    }
    return this.detail(agentId, id);
  }

  // --------------------------------------------------------------- attachments

  async upload(agentId: string, id: string, file: UploadedFile | undefined) {
    const t = await this.ticket(id);
    return this.attachments.store(file, t.storeId, agentId);
  }

  async download(id: string, attachmentId: string) {
    const t = await this.ticket(id);
    return this.attachments.open(t.id, attachmentId);
  }
}
