import { Module, OnModuleInit } from '@nestjs/common';
import { StoreAccessModule } from '../common/store-access/store-access.module.js';
import { SyncModule } from '../sync/sync.module.js';
import { DatabaseHealthCheck } from './checks/database.check.js';
import { InventoryHealthCheck } from './checks/inventory.check.js';
import { SyncBacklogHealthCheck } from './checks/sync-backlog.check.js';
import { type HealthCheck, IntegrationHealthRegistry } from './health-check.js';
import { IntegrationsController } from './integrations.controller.js';
import { IntegrationsService } from './integrations.service.js';

@Module({
  imports: [
    SyncModule,
    StoreAccessModule,
  ],
  controllers: [IntegrationsController],
  providers: [IntegrationsService, IntegrationHealthRegistry, DatabaseHealthCheck, SyncBacklogHealthCheck, InventoryHealthCheck],
  // Domain modules import IntegrationsModule and register their own HealthCheck in onModuleInit.
  exports: [IntegrationHealthRegistry],
})
export class IntegrationsModule implements OnModuleInit {
  constructor(
    private readonly registry: IntegrationHealthRegistry,
    private readonly database: DatabaseHealthCheck,
    private readonly sync: SyncBacklogHealthCheck,
    private readonly inventory: InventoryHealthCheck,
  ) {}

  onModuleInit() {
    this.registry.register(this.database);
    this.registry.register(this.sync);
    this.registry.register(this.inventory);
    for (const check of devFakeChecks(process.env.DEV_FAKE_HEALTH)) this.registry.register(check);
  }
}

/**
 * Dev only: simulate module status so screen 6 can be built before other modules
 * exist, e.g. DEV_FAKE_HEALTH=payments:DEGRADED,notifications:UNAVAILABLE,sales:OPERATIONAL.
 * Ignored when NODE_ENV=production.
 */
function devFakeChecks(spec: string | undefined): HealthCheck[] {
  if (!spec || process.env.NODE_ENV === 'production') return [];
  return spec.split(',').flatMap((pair) => {
    const [key, status] = pair.split(':').map((s) => s.trim());
    if (!key || !['OPERATIONAL', 'DEGRADED', 'UNAVAILABLE'].includes(status)) return [];
    return [
      {
        key,
        scope: 'global' as const,
        check: async () => ({
          status: status as 'OPERATIONAL' | 'DEGRADED' | 'UNAVAILABLE',
          message: status === 'OPERATIONAL' ? undefined : 'Simulated for development.',
        }),
      },
    ];
  });
}
