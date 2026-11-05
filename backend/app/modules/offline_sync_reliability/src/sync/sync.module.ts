import { Module, OnModuleInit } from '@nestjs/common';
import { StoreAccessModule } from '../common/store-access/store-access.module.js';
import { IdempotencyModule } from '../idempotency/idempotency.module.js';
import { OperationHandlerRegistry } from './handlers/operation-handler.js';
import { ShopProfileHandler } from './handlers/reference/shop-profile.handler.js';
import { StockMovementHandler } from './handlers/reference/stock-movement.handler.js';
import { SyncController } from './sync.controller.js';
import { SyncProcessor } from './sync.processor.js';
import { SyncService } from './sync.service.js';

@Module({
  imports: [
    IdempotencyModule,
    StoreAccessModule,
  ],
  controllers: [SyncController],
  providers: [SyncService, SyncProcessor, OperationHandlerRegistry, StockMovementHandler, ShopProfileHandler],
  // Domain modules import SyncModule and call registry.register(handler) in their own onModuleInit.
  exports: [OperationHandlerRegistry],
})
export class SyncModule implements OnModuleInit {
  constructor(
    private readonly registry: OperationHandlerRegistry,
    private readonly stock: StockMovementHandler,
    private readonly profile: ShopProfileHandler,
  ) {}

  onModuleInit() {
    this.registry.register(this.stock);
    this.registry.register(this.profile);
  }
}
