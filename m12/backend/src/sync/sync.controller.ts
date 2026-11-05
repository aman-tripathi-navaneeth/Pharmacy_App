import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import type { AuthUser } from '../common/auth/auth.guard.js';
import { CurrentUser, RequestId } from '../common/auth/current-user.decorator.js';
import { CancelOperationDto, DeviceScopeDto, PullQueryDto, PushDto, StoreScopeDto } from './dto/sync.dto.js';
import { SyncService } from './sync.service.js';

@Controller('sync')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Get('status')
  status(@CurrentUser() user: AuthUser, @Query() q: StoreScopeDto) {
    return this.sync.status(user.userId, q);
  }

  @Post('push')
  @HttpCode(200)
  push(@CurrentUser() user: AuthUser, @Body() dto: PushDto, @RequestId() requestId: string) {
    return this.sync.push(user.userId, dto, requestId);
  }

  @Get('pull')
  pull(@CurrentUser() user: AuthUser, @Query() q: PullQueryDto, @RequestId() requestId: string) {
    return this.sync.pull(user.userId, q, requestId);
  }

  @Get('operations/:id')
  operation(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Query() q: StoreScopeDto) {
    return this.sync.getOperation(user.userId, id, q);
  }

  @Post('operations/:id/retry')
  @HttpCode(200)
  retry(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DeviceScopeDto,
    @RequestId() requestId: string,
  ) {
    return this.sync.retry(user.userId, id, dto, requestId);
  }

  @Post('operations/:id/cancel')
  @HttpCode(200)
  cancel(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CancelOperationDto,
    @RequestId() requestId: string,
  ) {
    return this.sync.cancel(user.userId, id, dto, requestId);
  }
}
