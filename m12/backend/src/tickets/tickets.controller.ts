import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Patch,
  Post,
  Query,
  Res,
  StreamableFile,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import type { Response } from 'express';
import type { AuthUser } from '../common/auth/auth.guard.js';
import { CurrentUser } from '../common/auth/current-user.decorator.js';
import { MAX_ATTACHMENT_BYTES, type UploadedFile as File } from './attachments.service.js';
import { AddMessageDto, CreateTicketDto, ListTicketsDto, StoreScopeDto, UpdateStatusDto } from './dto/ticket.dto.js';
import { TicketsService } from './tickets.service.js';

@Controller('tickets')
export class TicketsController {
  constructor(private readonly tickets: TicketsService) {}

  /** POST /tickets — duplicate submits (same clientRequestId) return the original ticket with 200. */
  @Post()
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  async create(@CurrentUser() user: AuthUser, @Body() dto: CreateTicketDto, @Res({ passthrough: true }) res: Response) {
    const { ticket, duplicate } = await this.tickets.create(user.userId, dto);
    res.status(duplicate ? 200 : 201);
    return ticket;
  }

  @Get()
  list(@CurrentUser() user: AuthUser, @Query() q: ListTicketsDto) {
    return this.tickets.list(user.userId, q);
  }

  /** Upload first, then reference the returned id when creating a ticket or reply. */
  @Post('attachments')
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_ATTACHMENT_BYTES, files: 1 } }))
  upload(@CurrentUser() user: AuthUser, @Body() dto: StoreScopeDto, @UploadedFile() file: File | undefined) {
    return this.tickets.upload(user.userId, dto.storeId, file);
  }

  @Get(':id')
  get(@CurrentUser() user: AuthUser, @Param('id') id: string, @Query() q: StoreScopeDto) {
    return this.tickets.get(user.userId, id, q.storeId);
  }

  @Post(':id/messages')
  @HttpCode(200)
  @Throttle({ default: { ttl: 60_000, limit: 30 } })
  addMessage(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: AddMessageDto) {
    return this.tickets.addMessage(user.userId, id, dto);
  }

  /** Support staff move tickets through the lifecycle; the creator may close their own. */
  @Patch(':id/status')
  updateStatus(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: UpdateStatusDto) {
    return this.tickets.updateStatus(user.userId, id, dto);
  }

  @Get(':id/attachments/:attachmentId')
  async download(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Param('attachmentId') attachmentId: string,
    @Query() q: StoreScopeDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { meta, data } = await this.tickets.download(user.userId, id, q.storeId, attachmentId);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Cache-Control', 'private, no-store');
    return new StreamableFile(data, {
      type: meta.contentType,
      length: meta.size,
      disposition: `attachment; filename="${meta.fileName}"`,
    });
  }
}
