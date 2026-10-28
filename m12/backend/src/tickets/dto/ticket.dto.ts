import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsInt,
  
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Matches,
  Max,
  Min,
} from 'class-validator';
import { TICKET_CATEGORIES, TICKET_PRIORITIES, TICKET_STATUSES } from '../../db/schema.js';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export const MAX_ATTACHMENTS = 3;

export class StoreScopeDto {
  @IsUUID() storeId: string;
}

/** Spec §8.2 form rules. */
export class CreateTicketDto extends StoreScopeDto {
  @IsUUID() clientRequestId: string;

  @Transform(trim)
  @IsString()
  @Length(3, 120, { message: 'Subject must be 3–120 characters.' })
  subject: string;

  @Transform(trim)
  @IsString()
  @Length(10, 5000, { message: 'Description must be 10–5,000 characters.' })
  description: string;

  @IsIn(TICKET_CATEGORIES, { message: 'Choose a category.' }) category: string;
  @IsOptional() @IsIn(TICKET_PRIORITIES) priority?: string;

  @IsOptional() @IsUUID() relatedOperationId?: string;
  @IsOptional() @IsString() @Matches(/^[a-z][a-z0-9_]{1,39}$/) relatedModule?: string;

  @IsOptional() @IsArray() @ArrayMaxSize(MAX_ATTACHMENTS) @IsUUID('all', { each: true }) attachmentIds?: string[];
}

export class ListTicketsDto extends StoreScopeDto {
  @IsOptional() @IsIn(TICKET_STATUSES) status?: string;
  @IsOptional() @IsIn(TICKET_CATEGORIES) category?: string;
  @IsOptional() @IsIn(TICKET_PRIORITIES) priority?: string;
  @IsOptional() @Transform(trim) @IsString() @Length(1, 80) q?: string;
  @IsOptional() @IsString() @Matches(/^[A-Za-z0-9_-]{1,200}$/) cursor?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit?: number;
}

export class AddMessageDto extends StoreScopeDto {
  @IsUUID() clientRequestId: string;
  @Transform(trim) @IsString() @Length(1, 5000, { message: 'Reply must be 1–5,000 characters.' }) body: string;
  @IsOptional() @IsArray() @ArrayMaxSize(MAX_ATTACHMENTS) @IsUUID('all', { each: true }) attachmentIds?: string[];
}

export class UpdateStatusDto extends StoreScopeDto {
  @IsIn(TICKET_STATUSES) status: string;
  @IsOptional() @Transform(trim) @IsString() @Length(1, 2000) note?: string;
}
