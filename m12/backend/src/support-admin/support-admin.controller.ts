import { Body, Controller, Get, Param, Patch, Post, Query, Res, StreamableFile, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Response } from 'express';
import type { AuthUser } from '../common/auth/auth.guard.js';
import { CurrentUser } from '../common/auth/current-user.decorator.js';
import { MAX_ATTACHMENT_BYTES, type UploadedFile as File } from '../tickets/attachments.service.js';
import { AdminListDto, AdminReplyDto, AdminStatusDto, AssignDto, PriorityDto } from './dto.js';
import { SupportAdminService } from './support-admin.service.js';
import { SupportAgentGuard } from './support-agent.guard.js';

/** Platform support console API — cross-shop, SUPPORT_AGENT only. */
@Controller('admin')
@UseGuards(SupportAgentGuard)
export class SupportAdminController {
  constructor(private readonly support: SupportAdminService) {}

  @Get('tickets')
  list(@CurrentUser() user: AuthUser, @Query() q: AdminListDto) {
    return this.support.list(user.userId, q);
  }

  @Get('tickets/stats')
  stats(@CurrentUser() user: AuthUser) {
    return this.support.stats(user.userId);
  }

  @Get('agents')
  agents() {
    return this.support.agents();
  }

  @Get('tickets/:id')
  detail(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.support.detail(user.userId, id);
  }

  /** Public reply, or an internal note when `internal: true`. */
  @Post('tickets/:id/messages')
  reply(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: AdminReplyDto) {
    return this.support.reply(user.userId, id, dto);
  }

  /** Lifecycle change; resolving requires a summary (`note`) the shop sees. */
  @Patch('tickets/:id/status')
  status(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: AdminStatusDto) {
    return this.support.setStatus(user.userId, id, dto);
  }

  @Patch('tickets/:id/assignee')
  assign(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: AssignDto) {
    return this.support.assign(user.userId, id, dto);
  }

  @Patch('tickets/:id/priority')
  priority(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: PriorityDto) {
    return this.support.setPriority(user.userId, id, dto);
  }

  @Post('tickets/:id/attachments')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_ATTACHMENT_BYTES, files: 1 } }))
  upload(@CurrentUser() user: AuthUser, @Param('id') id: string, @UploadedFile() file: File | undefined) {
    return this.support.upload(user.userId, id, file);
  }

  @Get('tickets/:id/attachments/:attachmentId')
  async download(@Param('id') id: string, @Param('attachmentId') attachmentId: string, @Res({ passthrough: true }) res: Response) {
    const { meta, data } = await this.support.download(id, attachmentId);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Cache-Control', 'private, no-store');
    return new StreamableFile(data, { type: meta.contentType, length: meta.size, disposition: `attachment; filename="${meta.fileName}"` });
  }
}
