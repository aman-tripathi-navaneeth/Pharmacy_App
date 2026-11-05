import { ValidationPipe } from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';

export function configureApp(app: NestExpressApplication) {
  // 50 ops × 256 KB per-op cap (spec §12) plus envelope.
  app.useBodyParser('json', { limit: '14mb' });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  // Native apps don't need CORS; only list browser origins (e.g. Flutter web in dev).
  const origins = process.env.CORS_ORIGINS?.split(',').map((o) => o.trim()).filter(Boolean);
  if (origins?.length) app.enableCors({ origin: origins, exposedHeaders: ['x-request-id', 'retry-after'] });
  app.enableShutdownHooks();
  return app;
}
