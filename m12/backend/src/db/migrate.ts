// Release step: `npm run db:migrate` (applies drizzle/*.sql in order, once).
import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import { runMigrations } from './db.module.js';
import * as schema from './schema.js';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
await runMigrations(drizzle(pool, { schema }));
await pool.end();
console.log('migrations applied');
