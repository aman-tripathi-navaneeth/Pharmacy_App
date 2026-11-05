import { BadRequestException, Injectable, NotFoundException, PayloadTooLargeException } from '@nestjs/common';
import { and, eq, inArray, isNull } from 'drizzle-orm';
import { isUuid } from '../common/store-access/store-access.service.js';
import { type Db, InjectDb, type Tx } from '../db/db.module.js';
import { ticketAttachmentBlobs, ticketAttachments } from '../db/schema.js';

export const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;

/** Allowlist by actual file signature, not by the client-declared type or extension (spec §8.2, §13). */
const SIGNATURES: { contentType: string; ext: string[]; magic: number[] }[] = [
  { contentType: 'application/pdf', ext: ['pdf'], magic: [0x25, 0x50, 0x44, 0x46, 0x2d] }, // %PDF-
  { contentType: 'image/png', ext: ['png'], magic: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] },
  { contentType: 'image/jpeg', ext: ['jpg', 'jpeg'], magic: [0xff, 0xd8, 0xff] },
];

export interface UploadedFile {
  originalname: string;
  size: number;
  buffer: Buffer;
}

type AttachmentRow = typeof ticketAttachments.$inferSelect;

/**
 * Stores ticket files in Postgres (`ticket_attachment_blobs`, separate from metadata so
 * listings never load bytes). Files are only served through the authorized download
 * endpoint, as downloads, never inline. Object storage and virus scanning are open
 * decisions (spec §18); swap them in here when chosen.
 */
@Injectable()
export class AttachmentsService {
  constructor(@InjectDb() private readonly db: Db) {}

  async store(file: UploadedFile | undefined, storeId: string, userId: string) {
    if (!file?.buffer?.length) {
      throw new BadRequestException({ code: 'FILE_REQUIRED', message: 'Choose a file to upload.' });
    }
    if (file.size > MAX_ATTACHMENT_BYTES) {
      throw new PayloadTooLargeException({ code: 'FILE_TOO_LARGE', message: 'Files must be 10 MB or smaller.' });
    }
    const sig = SIGNATURES.find((s) => s.magic.every((b, i) => file.buffer[i] === b));
    if (!sig) {
      throw new BadRequestException({ code: 'FILE_TYPE_NOT_ALLOWED', message: 'Only PDF, JPG and PNG files can be attached.' });
    }

    const row = await this.db.transaction(async (tx) => {
      const [meta] = await tx
        .insert(ticketAttachments)
        .values({
          storeId,
          uploadedByUserId: userId,
          fileName: safeFileName(file.originalname, sig.ext[0]),
          contentType: sig.contentType,
          size: file.size,
        })
        .returning();
      await tx.insert(ticketAttachmentBlobs).values({ attachmentId: meta.id, data: file.buffer });
      return meta;
    });
    return toAttachmentDto(row);
  }

  /**
   * Binds uploads to a ticket inside the caller's transaction. Each id must be an
   * unused upload by the same user in the same shop, or the whole request fails.
   */
  async claim(ids: string[], ticketId: string, storeId: string, userId: string, tx: Tx) {
    const unique = [...new Set(ids)];
    if (!unique.length) return [];
    const claimed = await tx
      .update(ticketAttachments)
      .set({ ticketId })
      .where(
        and(
          inArray(ticketAttachments.id, unique),
          eq(ticketAttachments.storeId, storeId),
          eq(ticketAttachments.uploadedByUserId, userId),
          isNull(ticketAttachments.ticketId),
        ),
      )
      .returning({ id: ticketAttachments.id });
    if (claimed.length !== unique.length) {
      throw new BadRequestException({ code: 'ATTACHMENT_INVALID', message: 'An attachment is missing or was already used. Upload it again.' });
    }
    return unique;
  }

  async forTicket(ticketId: string) {
    const rows = await this.db.select().from(ticketAttachments).where(eq(ticketAttachments.ticketId, ticketId));
    return rows.map(toAttachmentDto);
  }

  async open(ticketId: string, attachmentId: string) {
    if (!isUuid(attachmentId)) throw notFound();
    const [row] = await this.db
      .select({ meta: ticketAttachments, data: ticketAttachmentBlobs.data })
      .from(ticketAttachments)
      .innerJoin(ticketAttachmentBlobs, eq(ticketAttachmentBlobs.attachmentId, ticketAttachments.id))
      .where(and(eq(ticketAttachments.id, attachmentId), eq(ticketAttachments.ticketId, ticketId)))
      .limit(1);
    if (!row) throw notFound();
    return { meta: row.meta, data: row.data };
  }
}

const notFound = () => new NotFoundException({ code: 'ATTACHMENT_NOT_FOUND', message: 'Attachment not found.' });

function safeFileName(name: string, ext: string): string {
  const base = (name || 'attachment')
    .replace(/\.[^.]*$/, '')
    .replace(/[^A-Za-z0-9 _-]/g, '')
    .trim()
    .slice(0, 80);
  return `${base || 'attachment'}.${ext}`;
}

export function toAttachmentDto(a: AttachmentRow) {
  return { id: a.id, fileName: a.fileName, contentType: a.contentType, size: a.size };
}
