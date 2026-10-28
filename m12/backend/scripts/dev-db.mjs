// Local dev database: creates `medical_store_dev` on your local Postgres (if missing),
// applies migrations, seeds one shop, its owner, a support agent and sample data,
// and prints the env values for the API and the app.
//   npm run dev:db            (safe to re-run; seeding is idempotent)
//   DEV_DB_RESET=true npm run dev:db   (drop and recreate first)
import { JwtService } from '@nestjs/jwt';
import { drizzle } from 'drizzle-orm/node-postgres';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const adminUrl = process.env.DEV_DB_ADMIN_URL ?? 'postgres://localhost/postgres';
const dbName = process.env.DEV_DB_NAME ?? 'medical_store_dev';
const secret = process.env.JWT_SECRET ?? 'dev-secret';

const admin = new pg.Client({ connectionString: adminUrl });
await admin.connect();
if (process.env.DEV_DB_RESET === 'true') await admin.query(`drop database if exists "${dbName}" with (force)`);
const exists = (await admin.query('select 1 from pg_database where datname = $1', [dbName])).rowCount;
if (!exists) await admin.query(`create database "${dbName}"`);
await admin.end();

const url = new URL(adminUrl);
url.pathname = `/${dbName}`;
const pool = new pg.Pool({ connectionString: url.toString() });
await migrate(drizzle(pool), { migrationsFolder: fileURLToPath(new URL('../drizzle', import.meta.url)) });

const userId = '00000000-0000-4000-8000-000000000001';
const agentId = '00000000-0000-4000-8000-000000000099';
const storeId = '00000000-0000-4000-9000-000000000001';
// A second shop so the support console shows cross-shop queues.
const user2Id = '00000000-0000-4000-8000-000000000002';
const store2Id = '00000000-0000-4000-9000-000000000002';
const q = (text, params) => pool.query(text, params);
await q(`insert into users (id, status, name) values ($1, 'ACTIVE', 'Dev Owner') on conflict do nothing`, [userId]);
// Support staff can read and answer any shop's tickets (spec §8.2).
await q(`insert into users (id, status, name, roles) values ($1, 'ACTIVE', 'Dev Support', '{SUPPORT_AGENT}') on conflict do nothing`, [agentId]);
await q(`insert into users (id, status, name) values ($1, 'ACTIVE', 'City Pharmacy Owner') on conflict do nothing`, [user2Id]);
await q(`insert into stores (id, status, name) values ($1, 'ACTIVE', 'City Pharmacy') on conflict do nothing`, [store2Id]);
await q(`insert into store_members (user_id, store_id, role, status) values ($1, $2, 'OWNER', 'ACTIVE') on conflict do nothing`, [user2Id, store2Id]);
await q(`insert into stores (id, status, name) values ($1, 'ACTIVE', 'Dev Pharmacy') on conflict do nothing`, [storeId]);
await q(`insert into store_members (user_id, store_id, role, status) values ($1, $2, 'OWNER', 'ACTIVE') on conflict do nothing`, [userId, storeId]);
await q(
  `insert into shop_profiles (store_id, name, phone, address, version) values ($1, 'Dev Pharmacy', '+91 98000 10234', '12 Main Rd', 1) on conflict do nothing`,
  [storeId],
);
await q(`insert into stock_balances (store_id, product_id, quantity, version) values ($1, 'paracetamol-500', 40, 1) on conflict do nothing`, [storeId]);
await pool.end();

const jwt = new JwtService({ secret });
const token = await jwt.signAsync({ sub: userId }, { expiresIn: '30d' });
const supportToken = await jwt.signAsync({ sub: agentId }, { expiresIn: '30d' });
const token2 = await jwt.signAsync({ sub: user2Id }, { expiresIn: '30d' });

console.log(`
Database: ${url.toString()}
API:    DATABASE_URL='${url.toString()}' JWT_SECRET='${secret}' npm run start:dev
Mobile: flutter run --dart-define=API_BASE_URL=http://localhost:3000 \\
          --dart-define=STORE_ID=${storeId} \\
          --dart-define=DEV_TOKEN=${token}
Support console (Dev Support):
  flutter build web -t lib/main_admin.dart -o build/admin_web --dart-define=ADMIN_TOKEN=${supportToken}
SUPPORT_TOKEN=${supportToken}
Second shop (City Pharmacy, store ${store2Id}) owner token:
SHOP2_TOKEN=${token2}`);
