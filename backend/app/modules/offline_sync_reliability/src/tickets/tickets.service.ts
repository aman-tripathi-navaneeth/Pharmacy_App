import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, desc, eq, ilike, or, type SQL, sql } from 'drizzle-orm';
import { isUuid, StoreAccessService } from '../common/store-access/store-access.service.js';
import { type Db, InjectDb } from '../db/db.module.js';
import { isUniqueViolation } from '../db/pg-errors.js';
import {
  type AuthorRole,
  ticketEvents,
  ticketNumberSeq,
  tickets,
  type TicketCategory,
  type TicketPriority,
  type TicketStatus,
} from '../db/schema.js';
import { AttachmentsService, type UploadedFile } from './attachments.service.js';
import type { AddMessageDto, CreateTicketDto, ListTicketsDto, UpdateStatusDto } from './dto/ticket.dto.js';
import { canTransition, canUserReply, statusAfterReply } from './ticket-lifecycle.js';

export type TicketRow = typeof tickets.$inferSelect;

export interface Actor {
  userId: string;
  storeId: string;
  role: AuthorRole;
}

const DEFAULT_PAGE = 20;

@Injectable()
export class TicketsService {
  constructor(
    @InjectDb() private readonly db: Db,
    private readonly attachments: AttachmentsService,
    private readonly access: StoreAccessService,
  ) {}

  /**
   * Shop members act as USER within their shop. Support staff (users.roles contains
   * SUPPORT_AGENT) may act on any shop's tickets. Who staffs support is an open
   * decision (spec §18); this role is the single switch for it.
   */
  async actor(userId: string, storeId: string): Promise<Actor> {
    if (await this.access.isSupportAgent(userId)) return { userId, storeId, role: 'SUPPORT' };
    await this.access.assertAccess(userId, storeId);
    return { userId, storeId, role: 'USER' };
  }

  // ------------------------------------------------------------------ create

  async create(userId: string, dto: CreateTicketDto) {
    const actor = await this.actor(userId, dto.storeId);
    if (actor.role !== 'USER') {
      throw new ForbiddenException({ code: 'SHOP_MEMBERS_ONLY', message: 'Tickets are created by shop members.' });
    }

    const existing = await this.findByRequest(actor, dto.clientRequestId);
    if (existing) return { ticket: await this.detail(existing, actor), duplicate: true };

    try {
      const created = await this.db.transaction(async (tx) => {
        const [t] = await tx
          .insert(tickets)
          .values({
            ticketNumber: sql`'TKT-' || nextval(${sql.raw(`'${ticketNumberSeq.seqName}'`)})`,
            storeId: actor.storeId,
            createdByUserId: actor.userId,
            clientRequestId: dto.clientRequestId,
            subject: dto.subject,
            description: dto.description,
            category: dto.category as TicketCategory,
            priority: (dto.priority ?? 'NORMAL') as TicketPriority,
            status: 'OPEN',
            relatedOperationId: dto.relatedOperationId,
            relatedModule: dto.relatedModule,
            lastActivityBy: 'USER',
          })
          .returning();
        await this.attachments.claim(dto.attachmentIds ?? [], t.id, actor.storeId, actor.userId, tx);
        await tx.insert(ticketEvents).values({
          ticketId: t.id,
          storeId: actor.storeId,
          type: 'CREATED',
          authorUserId: actor.userId,
          authorRole: 'USER',
          toStatus: 'OPEN',
        });
        return t;
      });
      return { ticket: await this.detail(created, actor), duplicate: false };
    } catch (err) {
      if (isUniqueViolation(err)) {
        // A concurrent double-submit committed first: return its ticket.
        const winner = await this.findByRequest(actor, dto.clientRequestId);
        if (winner) return { ticket: await this.detail(winner, actor), duplicate: true };
      }
      throw err;
    }
  }

  private async findByRequest(actor: Actor, clientRequestId: string): Promise<TicketRow | undefined> {
    const [t] = await this.db
      .select()
      .from(tickets)
      .where(
        and(eq(tickets.storeId, actor.storeId), eq(tickets.createdByUserId, actor.userId), eq(tickets.clientRequestId, clientRequestId)),
      )
      .limit(1);
    return t;
  }

  // -------------------------------------------------------------------- read

  async list(userId: string, q: ListTicketsDto) {
    const actor = await this.actor(userId, q.storeId);
    const where: SQL[] = [eq(tickets.storeId, actor.storeId)];
    if (q.status) where.push(eq(tickets.status, q.status as TicketStatus));
    if (q.category) where.push(eq(tickets.category, q.category as TicketCategory));
    if (q.priority) where.push(eq(tickets.priority, q.priority as TicketPriority));
    if (q.q) {
      const pattern = `%${q.q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
      where.push(or(ilike(tickets.subject, pattern), ilike(tickets.ticketNumber, pattern))!);
    }
    if (q.cursor) {
      const c = decodeCursor(q.cursor);
      where.push(sql`(${tickets.updatedAt}, ${tickets.id}) < (${c.at}::timestamptz, ${c.id}::uuid)`);
    }
    const limit = q.limit ?? DEFAULT_PAGE;
    const rows = await this.db
      .select({ t: tickets, cursorAt: sql<string>`${tickets.updatedAt}::text` })
      .from(tickets)
      .where(and(...where))
      .orderBy(desc(tickets.updatedAt), desc(tickets.id))
      .limit(limit + 1);
    const page = rows.slice(0, limit);
    const last = page[page.length - 1];
    return {
      tickets: page.map((r) => this.summary(r.t)),
      nextCursor: rows.length > limit && last ? encodeCursor(last.cursorAt, last.t.id) : null,
    };
  }

  async get(userId: string, ticketId: string, storeId: string) {
    const actor = await this.actor(userId, storeId);
    return this.detail(await this.load(actor, ticketId), actor);
  }

  // ------------------------------------------------------------------ update

  async addMessage(userId: string, ticketId: string, dto: AddMessageDto) {
    const actor = await this.actor(userId, dto.storeId);
    return this.replyAs(actor, await this.load(actor, ticketId), dto);
  }

  /**
   * Adds a reply (or, for support, an internal note) and applies the automatic
   * status change. Shared by the shop API and the support console.
   */
  async replyAs(
    actor: Actor,
    ticket: TicketRow,
    dto: { clientRequestId: string; body: string; attachmentIds?: string[]; internal?: boolean },
  ) {
    const internal = actor.role === 'SUPPORT' && dto.internal === true;
    const [dup] = await this.db
      .select({ id: ticketEvents.id })
      .from(ticketEvents)
      .where(
        and(
          eq(ticketEvents.ticketId, ticket.id),
          eq(ticketEvents.authorUserId, actor.userId),
          eq(ticketEvents.clientRequestId, dto.clientRequestId),
        ),
      )
      .limit(1);
    if (dup) return this.detail(ticket, actor);

    if (actor.role === 'USER' && !canUserReply(ticket.status, ticket.resolvedAt ?? undefined)) {
      throw new ConflictException({
        code: 'TICKET_CLOSED',
        message: 'This ticket is closed. Create a new ticket and mention this one.',
      });
    }
    if (actor.role === 'SUPPORT' && ticket.status === 'CLOSED' && !internal) {
      throw new ConflictException({ code: 'TICKET_CLOSED', message: 'This ticket is closed.' });
    }

    // Internal notes never move the ticket or count as activity the shop can see.
    const next = internal ? null : statusAfterReply(actor.role, ticket.status, ticket.resolvedAt ?? undefined);
    try {
      await this.db.transaction(async (tx) => {
        const refs = await this.attachments.claim(dto.attachmentIds ?? [], ticket.id, ticket.storeId, actor.userId, tx);
        await tx.insert(ticketEvents).values({
          ticketId: ticket.id,
          storeId: ticket.storeId,
          type: internal ? 'NOTE' : 'MESSAGE',
          visibility: internal ? 'INTERNAL' : 'PUBLIC',
          authorUserId: actor.userId,
          authorRole: actor.role,
          body: dto.body,
          attachmentIds: refs,
          clientRequestId: dto.clientRequestId,
        });
        if (next) {
          await tx.insert(ticketEvents).values({
            ticketId: ticket.id,
            storeId: ticket.storeId,
            type: 'STATUS_CHANGE',
            authorUserId: actor.userId,
            authorRole: actor.role,
            fromStatus: ticket.status,
            toStatus: next,
          });
        }
        const now = new Date();
        await tx
          .update(tickets)
          .set({
            updatedAt: now,
            ...(internal ? {} : { lastActivityAt: now, lastActivityBy: actor.role }),
            ...(next ? { status: next } : {}),
            ...(next === 'OPEN' ? { resolvedAt: null } : {}),
            ...(actor.role === 'SUPPORT' && !internal && !ticket.assignedToUserId ? { assignedToUserId: actor.userId } : {}),
          })
          .where(eq(tickets.id, ticket.id));
      });
    } catch (err) {
      if (!isUniqueViolation(err)) throw err; // concurrent double-send of the same reply
    }
    return this.detail((await this.loadById(ticket.id))!, actor);
  }

  async updateStatus(userId: string, ticketId: string, dto: UpdateStatusDto) {
    const actor = await this.actor(userId, dto.storeId);
    return this.changeStatusAs(actor, await this.load(actor, ticketId), dto.status as TicketStatus, dto.note);
  }

  /** Validated lifecycle transition with an audit event. Shared with the support console. */
  async changeStatusAs(actor: Actor, ticket: TicketRow, to: TicketStatus, note?: string) {
    if (ticket.status === to) return this.detail(ticket, actor);

    if (actor.role === 'USER' && ticket.createdByUserId !== actor.userId) {
      throw new ForbiddenException({ code: 'NOT_TICKET_OWNER', message: 'Only the person who created this ticket can close it.' });
    }
    if (!canTransition(actor.role, ticket.status, to)) {
      throw new BadRequestException({
        code: 'INVALID_STATUS_TRANSITION',
        message: `A ticket can't move from ${ticket.status} to ${to}.`,
      });
    }

    const now = new Date();
    await this.db.transaction(async (tx) => {
      const changed = await tx
        .update(tickets)
        .set({
          status: to,
          lastActivityAt: now,
          lastActivityBy: actor.role,
          updatedAt: now,
          ...(to === 'RESOLVED' ? { resolvedAt: now } : {}),
          ...(to === 'CLOSED' ? { closedAt: now } : {}),
          ...(to === 'IN_PROGRESS' && ticket.status === 'RESOLVED' ? { resolvedAt: null } : {}),
          ...(actor.role === 'SUPPORT' && !ticket.assignedToUserId ? { assignedToUserId: actor.userId } : {}),
        })
        // Optimistic: no change if someone moved the ticket meanwhile.
        .where(and(eq(tickets.id, ticket.id), eq(tickets.status, ticket.status)))
        .returning({ id: tickets.id });
      if (changed.length !== 1) {
        throw new ConflictException({ code: 'TICKET_CHANGED', message: 'This ticket was updated by someone else. Refresh and try again.' });
      }
      await tx.insert(ticketEvents).values({
        ticketId: ticket.id,
        storeId: ticket.storeId,
        type: 'STATUS_CHANGE',
        authorUserId: actor.userId,
        authorRole: actor.role,
        fromStatus: ticket.status,
        toStatus: to,
        body: note,
      });
    });
    return this.detail((await this.loadById(ticket.id))!, actor);
  }

  // ------------------------------------------------------------- attachments

  async upload(userId: string, storeId: string, file: UploadedFile | undefined) {
    const actor = await this.actor(userId, storeId);
    return this.attachments.store(file, actor.storeId, actor.userId);
  }

  async download(userId: string, ticketId: string, storeId: string, attachmentId: string) {
    const actor = await this.actor(userId, storeId);
    const ticket = await this.load(actor, ticketId);
    return this.attachments.open(ticket.id, attachmentId);
  }

  // ----------------------------------------------------------------- helpers

  /** Tickets outside the caller's shop are reported as not found, never as forbidden. */
  private async load(actor: Actor, ticketId: string): Promise<TicketRow> {
    if (!isUuid(ticketId)) throw ticketNotFound();
    const [t] = await this.db
      .select()
      .from(tickets)
      .where(and(eq(tickets.id, ticketId), eq(tickets.storeId, actor.storeId)))
      .limit(1);
    if (!t) throw ticketNotFound();
    return t;
  }

  async loadById(id: string) {
    const [t] = await this.db.select().from(tickets).where(eq(tickets.id, id)).limit(1);
    return t;
  }

  private summary(t: TicketRow) {
    return {
      id: t.id,
      ticketNumber: t.ticketNumber,
      subject: t.subject,
      category: t.category,
      priority: t.priority,
      status: t.status,
      relatedOperationId: t.relatedOperationId ?? null,
      lastActivityBy: t.lastActivityBy,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
    };
  }

  async detail(t: TicketRow, actor?: Actor) {
    const [all, attachments] = await Promise.all([
      this.db.select().from(ticketEvents).where(eq(ticketEvents.ticketId, t.id)).orderBy(asc(ticketEvents.seq)),
      this.attachments.forTicket(t.id),
    ]);
    // Shops see only the public conversation; staff notes and assignment stay internal.
    const events =
      actor?.role === 'SUPPORT'
        ? all
        : all.filter((e) => e.visibility === 'PUBLIC' && ['CREATED', 'MESSAGE', 'STATUS_CHANGE'].includes(e.type));
    const viewer = actor?.userId;
    return {
      ...this.summary(t),
      description: t.description,
      relatedModule: t.relatedModule ?? null,
      resolvedAt: t.resolvedAt ?? null,
      closedAt: t.closedAt ?? null,
      canReply: actor?.role === 'SUPPORT' ? t.status !== 'CLOSED' : canUserReply(t.status, t.resolvedAt ?? undefined),
      canClose: t.status !== 'CLOSED' && (actor?.role === 'SUPPORT' || (!!viewer && t.createdByUserId === viewer)),
      attachments,
      events: events.map((e) => ({
        id: e.id,
        type: e.type,
        authorRole: e.authorRole,
        // Staff identities are not exposed to shops; the app shows "You" / a teammate / "Support".
        byViewer: !!viewer && e.authorUserId === viewer,
        body: e.body ?? null,
        fromStatus: e.fromStatus ?? null,
        toStatus: e.toStatus ?? null,
        attachmentIds: e.attachmentIds,
        ...(actor?.role === 'SUPPORT' ? { visibility: e.visibility, meta: e.meta ?? null, authorUserId: e.authorUserId } : {}),
        createdAt: e.createdAt,
      })),
    };
  }
}

const ticketNotFound = () => new NotFoundException({ code: 'TICKET_NOT_FOUND', message: 'Ticket not found.' });

/** Cursor carries Postgres' full-precision timestamp text, so rows sharing a millisecond are never skipped. */
function encodeCursor(at: string, id: string) {
  return Buffer.from(`${at}|${id}`).toString('base64url');
}

function decodeCursor(cursor: string): { at: string; id: string } {
  const [at, id] = Buffer.from(cursor, 'base64url').toString().split('|');
  if (!at || !id || !isUuid(id) || Number.isNaN(Date.parse(at.replace(' ', 'T')))) {
    throw new BadRequestException({ code: 'INVALID_CURSOR', message: 'Invalid page cursor.' });
  }
  return { at, id };
}
