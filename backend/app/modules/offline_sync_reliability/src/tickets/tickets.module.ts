import { Module } from '@nestjs/common';
import { StoreAccessModule } from '../common/store-access/store-access.module.js';
import { AttachmentsService } from './attachments.service.js';
import { TicketsController } from './tickets.controller.js';
import { TicketsService } from './tickets.service.js';

@Module({
  imports: [StoreAccessModule],
  controllers: [TicketsController],
  providers: [TicketsService, AttachmentsService],
  exports: [TicketsService, AttachmentsService],
})
export class TicketsModule {}
