import { Module } from '@nestjs/common';
import { StoreAccessService } from './store-access.service.js';

@Module({ providers: [StoreAccessService], exports: [StoreAccessService] })
export class StoreAccessModule {}
