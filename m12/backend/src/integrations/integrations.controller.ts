import { Body, Controller, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { IsUUID } from 'class-validator';
import type { AuthUser } from '../common/auth/auth.guard.js';
import { CurrentUser } from '../common/auth/current-user.decorator.js';
import { ModuleKeyPipe } from './module-key.pipe.js';
import { IntegrationsService } from './integrations.service.js';

class StoreQueryDto {
  @IsUUID() storeId: string;
}

@Controller('integrations')
export class IntegrationsController {
  constructor(private readonly integrations: IntegrationsService) {}

  /** GET /integrations/health — safe module status summary (spec §9). */
  @Get('health')
  health(@CurrentUser() user: AuthUser, @Query() q: StoreQueryDto) {
    return this.integrations.health(user.userId, q.storeId);
  }

  /** "Retry check" on screen 6. Re-runs one check (at most every 10 s per module). */
  @Post('health/:key/check')
  @HttpCode(200)
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  recheck(@CurrentUser() user: AuthUser, @Param('key', ModuleKeyPipe) key: string, @Body() body: StoreQueryDto) {
    return this.integrations.recheck(user.userId, body.storeId, key);
  }
}
