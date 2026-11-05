import { Module } from '@nestjs/common';
import { StoreAccessModule } from '../common/store-access/store-access.module.js';
import { TicketsModule } from '../tickets/tickets.module.js';
import { SupportAdminController } from './support-admin.controller.js';
import { SupportAdminService } from './support-admin.service.js';
import { SupportAgentGuard } from './support-agent.guard.js';

@Module({
  imports: [TicketsModule, StoreAccessModule],
  controllers: [SupportAdminController],
  providers: [SupportAdminService, SupportAgentGuard],
})
export class SupportAdminModule {}
