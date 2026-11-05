import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Max,
  Min,
  ValidateIf,
} from 'class-validator';
import { TICKET_CATEGORIES, TICKET_PRIORITIES, TICKET_STATUSES } from '../db/schema.js';
import { MAX_ATTACHMENTS } from '../tickets/dto/ticket.dto.js';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

/** Queue views shown in the console's sidebar. */
export const QUEUE_VIEWS = ['needs_reply', 'unassigned', 'mine', 'open', 'waiting_user', 'resolved', 'closed', 'all'] as const;
export type QueueView = (typeof QUEUE_VIEWS)[number];
export const QUEUE_SORTS = ['priority', 'oldest', 'newest'] as const;
export type QueueSort = (typeof QUEUE_SORTS)[number];

export class AdminListDto {
  @IsOptional() @IsIn(QUEUE_VIEWS) view?: QueueView;
  @IsOptional() @IsIn(TICKET_STATUSES) status?: string;
  @IsOptional() @IsIn(TICKET_PRIORITIES) priority?: string;
  @IsOptional() @IsIn(TICKET_CATEGORIES) category?: string;
  @IsOptional() @IsUUID() storeId?: string;
  @IsOptional() @Transform(trim) @IsString() @Length(1, 80) q?: string;
  @IsOptional() @IsIn(QUEUE_SORTS) sort?: QueueSort;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(10_000) page?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(5) @Max(100) pageSize?: number;
}

export class AdminReplyDto {
  @IsUUID() clientRequestId: string;
  @Transform(trim) @IsString() @Length(1, 5000, { message: 'Message must be 1–5,000 characters.' }) body: string;
  /** true = internal note, never shown to the shop. */
  @IsOptional() @IsBoolean() internal?: boolean;
  @IsOptional() @IsArray() @ArrayMaxSize(MAX_ATTACHMENTS) @IsUUID('all', { each: true }) attachmentIds?: string[];
}

export class AdminStatusDto {
  @IsIn(TICKET_STATUSES) status: string;
  /** Required when resolving: the summary the shop sees. */
  @ValidateIf((o: AdminStatusDto) => o.status === 'RESOLVED' || o.note !== undefined)
  @Transform(trim)
  @IsString()
  @Length(5, 2000, { message: 'Write a resolution summary (at least 5 characters).' })
  note?: string;
}

export class AssignDto {
  /** null to unassign. */
  @ValidateIf((o: AssignDto) => o.assigneeUserId !== null) @IsUUID() assigneeUserId: string | null;
}

export class PriorityDto {
  @IsIn(TICKET_PRIORITIES) priority: string;
}
