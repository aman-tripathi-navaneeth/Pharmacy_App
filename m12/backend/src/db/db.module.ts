import { Global, Inject, Module, OnApplicationShutdown } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { drizzle, type NodePgDatabase } from 'drizzle-orm/node-postgres';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import * as schema from './schema.js';

export const DB = Symbol('DB');
export const PG_POOL = Symbol('PG_POOL');

export type Db = NodePgDatabase<typeof schema>;
/** A transaction handle; has the same query API as [Db]. */
export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];
export type Executor = Db | Tx;

/** `backend/drizzle` — the same relative path from `src/db` and `dist/db`. */
export const MIGRATIONS_DIR = fileURLToPath(new URL('../../drizzle', import.meta.url));

export async function runMigrations(db: Db) {
  await migrate(db, { migrationsFolder: MIGRATIONS_DIR });
}

export const InjectDb = () => Inject(DB);

@Global()
@Module({
  providers: [
    {
      provide: PG_POOL,
      inject: [ConfigService],
      useFactory: (config: ConfigService) =>
        new Pool({
          connectionString: config.getOrThrow<string>('DATABASE_URL'),
          max: Number(config.get('DATABASE_POOL_MAX') ?? 10),
          ssl: config.get('DATABASE_SSL') === 'true' ? { rejectUnauthorized: true } : undefined,
        }),
    },
    {
      provide: DB,
      inject: [PG_POOL, ConfigService],
      useFactory: async (pool: Pool, config: ConfigService) => {
        const db = drizzle(pool, { schema });
        // Dev/test convenience; deployments run `npm run db:migrate` as a release step.
        if (config.get('DB_MIGRATE_ON_BOOT') === 'true') await runMigrations(db);
        return db;
      },
    },
  ],
  exports: [DB, PG_POOL],
})
export class DbModule implements OnApplicationShutdown {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async onApplicationShutdown() {
    await this.pool.end();
  }
}
