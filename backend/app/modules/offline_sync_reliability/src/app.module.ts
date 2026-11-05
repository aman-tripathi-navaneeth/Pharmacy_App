import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { JwtAuthGuard } from './common/auth/auth.guard.js';
import { DbModule } from './db/db.module.js';
import { HttpExceptionFilter } from './common/http/http-exception.filter.js';
import { RequestIdMiddleware } from './common/http/request-id.middleware.js';
import { IntegrationsModule } from './integrations/integrations.module.js';
import { SyncModule } from './sync/sync.module.js';
import { SupportAdminModule } from './support-admin/support-admin.module.js';
import { TicketsModule } from './tickets/tickets.module.js';
import { ProductTourModule } from './product-tour/product-tour.module.js';
import { TranslationsModule } from './translations/translations.module.js';

@Module({
  imports: [
    // Tests configure themselves; a developer's local .env must not leak in.
    ConfigModule.forRoot({ isGlobal: true, ignoreEnvFile: process.env.NODE_ENV === 'test' }),
    DbModule,
    JwtModule.registerAsync({
      global: true,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({ secret: config.getOrThrow<string>('JWT_SECRET') }),
    }),
    ThrottlerModule.forRoot({
      throttlers: [{ ttl: 60_000, limit: Number(process.env.THROTTLE_LIMIT_PER_MIN ?? 120) }],
      // Test-only escape hatch; never set in deployed environments.
      skipIf: () => process.env.NODE_ENV === 'test' && process.env.THROTTLE_DISABLED === 'true',
    }),
    SyncModule,
    IntegrationsModule,
    TicketsModule,
    SupportAdminModule,
    TranslationsModule,
    ProductTourModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_FILTER, useClass: HttpExceptionFilter },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestIdMiddleware).forRoutes('*');
  }
}
