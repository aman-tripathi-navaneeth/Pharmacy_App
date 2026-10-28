import type { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { Test } from '@nestjs/testing';
import pg from 'pg';
import { AppModule } from '../../src/app.module.js';
import { configureApp } from '../../src/app.setup.js';
import { DB, type Db, PG_POOL } from '../../src/db/db.module.js';

/** Admin connection used only to create/drop the throwaway test databases. */
const ADMIN_URL = process.env.TEST_DATABASE_ADMIN_URL ?? 'postgres://localhost/postgres';

async function admin(sql: string) {
  const client = new pg.Client({ connectionString: ADMIN_URL });
  await client.connect();
  try {
    await client.query(sql);
  } finally {
    await client.end();
  }
}

/**
 * Boots the real app against a fresh Postgres database, migrated with the real
 * migration files (drizzle/*.sql). The database is dropped on stop().
 */
export async function startApp(name: string) {
  const dbName = `${name}_${process.pid}_${Date.now()}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');
  await admin(`create database "${dbName}"`);
  const url = new URL(ADMIN_URL);
  url.pathname = `/${dbName}`;

  process.env.DATABASE_URL = url.toString();
  process.env.DB_MIGRATE_ON_BOOT = 'true';
  process.env.JWT_SECRET = 'test-secret';
  process.env.THROTTLE_LIMIT_PER_MIN = '10000';
  process.env.THROTTLE_DISABLED = 'true';

  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  const app: INestApplication = configureApp(moduleRef.createNestApplication<NestExpressApplication>());
  await app.init();
  const db: Db = app.get(DB);
  const pool: pg.Pool = app.get(PG_POOL);
  const jwt = app.get(JwtService);

  return {
    app,
    db,
    /** Raw SQL for seeding and assertions: `await ctx.q('select … where id = $1', [id])`. */
    q: async <T = Record<string, unknown>>(text: string, params: unknown[] = []) => (await pool.query(text, params)).rows as T[],
    token: (userId: string) => jwt.signAsync({ sub: userId }),
    stop: async () => {
      await app.close();
      await admin(`drop database if exists "${dbName}" with (force)`);
    },
  };
}

export type TestApp = Awaited<ReturnType<typeof startApp>>;

/** Seeds an active user, shop and membership (the Auth module's tables). */
export async function seedMember(ctx: TestApp, opts: { userId: string; storeId: string; role?: string; roles?: string[] }) {
  await ctx.q(`insert into users (id, status, roles) values ($1, 'ACTIVE', $2) on conflict do nothing`, [opts.userId, opts.roles ?? []]);
  await ctx.q(`insert into stores (id, status) values ($1, 'ACTIVE') on conflict do nothing`, [opts.storeId]);
  await ctx.q(`insert into store_members (user_id, store_id, role, status) values ($1, $2, $3, 'ACTIVE') on conflict do nothing`, [
    opts.userId,
    opts.storeId,
    opts.role ?? 'OWNER',
  ]);
}
