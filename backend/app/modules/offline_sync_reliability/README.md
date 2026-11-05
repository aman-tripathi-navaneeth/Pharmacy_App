# Medical Store App: Offline Sync (Member 12)

This is the reliability layer from the *Offline Sync, Integration & Reliability* spec. It lets other modules queue work while the device is offline and syncs it later, so a sale, purchase or stock movement is never applied twice.

```
backend/   NestJS + PostgreSQL (Drizzle): /sync, /integrations, /tickets, translation and product-tour APIs, idempotency, audit logs
mobile/    Flutter: Drift outbox, sync manager, l10n runtime, screens 1–11 (Figma rows A–K)
```

## How it works

1. **Queue.** A module calls `SyncRepository.enqueue(...)`. The operation gets a `clientOperationId` and an idempotency key, which never change afterwards. It is written to SQLite before the UI says "saved on this device".
2. **Push.** `SyncManager` sends batches of up to 50 operations in insertion order. An operation waits until everything in its `dependsOn` list has synced or appears earlier in the same batch.
3. **Process once.** For each operation, the server writes the idempotency record, runs the domain handler, adds a change-feed entry and records the operation status, all in one Postgres transaction. The idempotency row is inserted first, so a concurrent submission of the same key waits on its unique index and then gets the stored result. If the same key arrives again later, the server returns the stored result instead of applying the change a second time. The same key with a different payload is rejected.
4. **Results.** Each operation gets its own result: `SYNCED`, `ALREADY_PROCESSED`, `CONFLICT`, `FAILED_PERMANENT` or `RETRYABLE_FAILURE`. Retryable failures back off exponentially with jitter (2 s base, 5 min cap) and stop after 8 automatic attempts, after which the operation shows as "Needs attention".
5. **Pull.** The device then reads `/sync/pull?cursor=` until `hasMore` is false. Each page and its cursor are saved in one SQLite transaction.

A timeout does **not** mean the request failed. The device always retries with the same key, and if the server had already committed it returns `ALREADY_PROCESSED`.

## For other module owners: adding an offline operation

**Server:** implement `OperationHandler` (see `backend/src/sync/handlers/operation-handler.ts`) and register it:

```ts
@Injectable()
export class SaleCreateHandler implements OperationHandler<SaleDto>, OnModuleInit {
  readonly module = 'sales';
  readonly operationType = 'sale_create';
  readonly payloadType = SaleDto;            // class-validator DTO
  constructor(private registry: OperationHandlerRegistry) {}
  onModuleInit() { this.registry.register(this); }
  async handle(ctx: OperationContext, p: SaleDto) {
    // write ONLY through ctx.session; throw DomainRejectedError / DomainConflictError
    await ctx.emitChange({ entity: 'sale', entityId, version, data });
    return { resourceId, version };
  }
}
```

**Client:** add an `OfflineOperationSpec` to `OfflineCatalog.standard` (`mobile/lib/features/sync/domain/offline_catalog.dart`), then call `ref.read(syncRepositoryProvider).enqueue(...)`.

Rules from spec §5–6:
- Stock is an append-only ledger. Never send a stock balance from the device.
- An offline payment is only an *intent*. Only the server or payment provider can mark it paid.
- Profile-style records use `baseVersion`. A stale edit returns `CONFLICT`, and the user chooses which version to keep.

The two handlers in `handlers/reference/` (`inventory.stock_movement` and `shop.profile_update`) are examples for the Inventory and Shop owners to adopt or replace.

## For other module owners: reporting health (screen 6)

Implement `HealthCheck` (`backend/src/integrations/health-check.ts`) and register it:

```ts
@Injectable()
export class PaymentsHealthCheck implements HealthCheck, OnModuleInit {
  readonly key = 'payments';          // must match MODULE_CATALOG
  readonly scope = 'global';          // or 'store' for per-shop checks
  constructor(private registry: IntegrationHealthRegistry) {}
  onModuleInit() { this.registry.register(this); }
  async check() {
    // return OPERATIONAL | DEGRADED | UNAVAILABLE with a short, user-safe message
    return { status: 'OPERATIONAL' as const };
  }
}
```

For a provider that's exposed over HTTP, use `new HttpHealthCheck('payments', process.env.PAYMENTS_HEALTH_URL)`. The URL stays on the server.

How checks run:
- Each check has a 5 s timeout and its result is cached for 60 s. "Retry check" re-runs a single module at most once every 10 s.
- If a check throws or times out, the module shows as `UNAVAILABLE` with a generic message. The error details only go to the server logs.
- A module with no registered check shows as **Not set up**, never as OK.
- The guidance text for each module and status (for example "Do not take the payment again") lives in `MODULE_CATALOG`.
- In dev, `DEV_FAKE_HEALTH=payments:DEGRADED,notifications:UNAVAILABLE` simulates statuses. It is ignored when `NODE_ENV=production`.

## Support tickets (screens 7–9)

- **Creating a ticket.** `POST /tickets` takes a `clientRequestId`. If the same id is sent again, for example a double tap or a retry after a timeout, the server returns the original ticket with 200 instead of creating another. The form saves a draft on the device, and the draft keeps its `clientRequestId`.
- **Lifecycle.** OPEN → IN_PROGRESS → WAITING_FOR_USER → RESOLVED → CLOSED, enforced by the server (`backend/src/tickets/ticket-lifecycle.ts`).
  - When the shop replies to a WAITING_FOR_USER ticket, it moves back to IN_PROGRESS.
  - A reply within 14 days of RESOLVED reopens the ticket. CLOSED is final.
  - Shop members can only close their own tickets. Support staff move tickets through the rest of the lifecycle.
- **Who sees what.** Only members of the creator's shop and support staff (users with `roles: ['SUPPORT_AGENT']`) can see a ticket. For anyone else, a ticket in another shop returns 404.
- **Audit.** Every status change and message is recorded in `ticket_events`.
- **Attachments.** `POST /tickets/attachments` accepts multipart PDF, JPG or PNG, checked by the file's actual bytes, 10 MB maximum and 3 per ticket. File bytes are stored in Postgres (`ticket_attachment_blobs`, kept separate from the metadata) behind `AttachmentsService`, so object storage can replace it later. An upload can be attached to only one ticket or reply. Downloads require auth and are always served as file downloads.
- **Dev.** `npm run dev:db` also prints a support-agent token, so you can reply or change a ticket's status with curl.

## Support console (platform admin)

A separate web app for support staff: `mobile/lib/main_admin.dart`, with code under `mobile/lib/admin/`. It is backed by `/admin/*` endpoints (`backend/src/support-admin/`). Every admin endpoint requires a user whose `roles` include `SUPPORT_AGENT`; anyone else gets 403 `SUPPORT_ONLY`.

- **Queue (all shops).** Views: Needs reply, Unassigned, Assigned to me, All open, Waiting for shop, Resolved, Closed, All. Each view shows a live count, and a banner appears while critical tickets are open. You can filter by priority and category, and sort by priority-then-oldest, oldest or newest. Search matches ticket number, subject or shop name. `GET /admin/tickets`, `GET /admin/tickets/stats`.
- **Full ticket.** `GET /admin/tickets/:id` returns:
  - the conversation, internal notes, and the audit trail (assignment, priority and status changes);
  - the shop (name and status) and the requester (name and role);
  - attachments;
  - the **related sync operation**: its server status, last error, device, and the last 20 attempts from `sync_logs`. This lets support see exactly why an offline action failed.
- **Resolving.**
  - Reply to the shop, or add an **internal note**. Notes are visible to support only and never shown to the shop. (`POST /admin/tickets/:id/messages`, `internal: true`)
  - Assign the ticket, or use "Assign to me" (`PATCH …/assignee`). A first public reply auto-assigns the ticket.
  - Change priority (`PATCH …/priority`).
  - Change status (`PATCH …/status`): Ask shop for info (WAITING_FOR_USER), Mark in progress, **Resolve** (a resolution summary is required and is shown to the shop), Reopen, and Close.
  - Attach files (`POST …/attachments`).
- **Shop view stays clean.** The shop app shows only public events: creation, replies, and status changes including the resolution summary. Notes and assignment or priority changes are stored with `visibility = INTERNAL` (migration `0001_support_console.sql`).
- **Run it (dev).**

  ```bash
  cd mobile && flutter build web -t lib/main_admin.dart -o build/admin_web \
    --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=ADMIN_TOKEN=<SUPPORT_TOKEN from dev:db> --dart-define=ADMIN_NAME='Dev Support'
  ```

  Then serve `build/admin_web`, for example with `python3 -m http.server 5174`, and add its origin to `CORS_ORIGINS`. Deep links use `/#/tickets/<id>`.

  The dev token is a stand-in. Sign-in for support staff belongs to the Auth module owner.

## Languages & translation (screen 10)

- **Where text lives.** English, Hindi, Telugu and Tamil catalogs are in `backend/src/translations/catalogs/*.json`, using ICU MessageFormat for placeholders and plurals. English is the source of truth.
- **Publishing.** The server publishes each catalog version once, at startup. Any translation whose placeholders don't match the English text, or whose plural syntax is broken, is rejected. Each language's coverage and list of missing keys is recorded; this is the "translation report" from `GET /translations/:language`.
- **In the app.** Every app-owned string goes through `tr('key', {args})`. A key the chosen language doesn't have shows in English and is counted. The app bundles a copy of each catalog for offline use (`npm run l10n:export` refreshes it) and downloads newer catalog versions using an ETag.
- **Never translated:** medicine names, prescriptions, licence details, and user data such as operation labels and ticket text.
- **Saving the choice.** The user's language is saved on the device and in `PATCH /users/me/language`, and restored on a new device. If the device is offline, the profile copy is saved once it's back online.
- **Status today:** Hindi covers 100% of keys; Telugu (~27%) and Tamil (~21%) are partial first passes. **All three are machine-drafted (`"@@reviewed": false`) and need review by a native speaker** before launch (spec §18).
- **To add or fix a string:** edit `en.json` and the other catalogs, bump `@@version`, then run `npm run l10n:export`. A Flutter test fails if the code uses a key that isn't in `en.json`.

## Product tour (screen 11)

- **Content.** Each tour version is a definition file in `backend/src/product-tour/tours/<version>.json`, served by `GET /product-tour/:version` (or `latest`). Steps contain translation keys, not text, so the tour follows the user's language. The server refuses to start if a step references a key that isn't in `en.json`, a step type or icon is unknown, or the tour doesn't end with a finish step.
- **Progress.** `POST /product-tour/progress` stores progress per user and tour version (`IN_PROGRESS`, `SKIPPED` or `COMPLETED`).
  - Once a version is completed it stays completed; replaying it only counts a restart.
  - A skip is only undone when the user explicitly restarts from step 1, so a stale update from an offline phone can't bring back a tour the user skipped.
  - The app saves progress on the device first and pushes it when online. On a new device it restores progress from the server, so someone who already finished isn't shown the tour again.
- **Never blocks work.** The tour opens by itself only once, for a tour version the user has never started, and not while sync items need attention. Skip is available on every step. If the user leaves part-way, Home shows "Continue the quick tour". Help (⋮ → Product tour) restarts it.
- **Changing the tour.** Add a new version file, add its strings to the catalogs, then run `npm run l10n:export`. That also copies tours into `mobile/assets/tour/`, so the first launch works offline.

## Database (PostgreSQL)

- **Schema** is defined in `backend/src/db/schema.ts` (Drizzle). Migrations are plain SQL files in `backend/drizzle/`. After changing the schema, run `npm run db:generate` and commit the new SQL file.
- **Deploying:** set `DATABASE_URL` (and `DATABASE_SSL=true` for managed databases), then run `npm run db:migrate` as a release step. For local dev and tests, `DB_MIGRATE_ON_BOOT=true` applies migrations at startup.
- **Database-enforced rules:**
  - unique constraints back idempotency keys, operation IDs, ticket request IDs and ledger movement IDs;
  - check constraints keep statuses valid and stock balances non-negative;
  - stock and profile writes take a row lock (`SELECT … FOR UPDATE`), so concurrent sales of the same product can't oversell;
  - each shop's change-feed counter row serialises writers, so pull cursors never skip a committed change.
- **Tests** need a local Postgres (`TEST_DATABASE_ADMIN_URL`, default `postgres://localhost/postgres`).

## Integration points this module expects

| From | What | Where |
|---|---|---|
| Auth module | JWT with `sub` = user id, signed with `JWT_SECRET` | `common/auth/auth.guard.ts` |
| Auth / Store setup | Tables `users (id, status, roles)`, `stores (id, status)`, `store_members (user_id, store_id, role, status)`. They are defined in `backend/src/db/schema.ts` as an interim schema for the Auth owner to take over. | `common/store-access/store-access.service.ts` |
| Auth module (mobile) | Real `AuthSession` (token + active storeId) | `mobile/lib/core/auth_session.dart` |

Membership is checked again on every sync request, so a user who was disabled, a shop that was suspended, or a membership that was removed while the device was offline cannot sync.

## Running

```bash
# backend
cd backend && cp .env.example .env   # set DATABASE_URL + JWT_SECRET
npm install
npm run dev:db                        # local Postgres: create, migrate and seed medical_store_dev; prints tokens
npm run start:dev
npm run test:e2e                      # each test file runs in its own throwaway Postgres database

# mobile
cd mobile && flutter pub get && dart run build_runner build
flutter test
flutter run --dart-define=API_BASE_URL=http://localhost:3000 \
            --dart-define=DEV_TOKEN=<jwt> --dart-define=STORE_ID=<shop uuid>
```

In debug builds the Home screen has a **Developer tools** card. Use it to simulate offline mode, queue stock movements, force a permanent failure (oversell), and create a profile conflict (stale edit).

## Spec coverage

| Spec | Status |
|---|---|
| §3 workflow, §4 states, §5 idempotency, §6 conflicts (stock, profile) | ✅ |
| §7 screens 1–5 (Indicator, Sync Status, Pending, Details, Conflict) | ✅ |
| §9 `/sync/status`, `/sync/push`, `/sync/pull`, `/sync/operations/:id` (+ `/retry`, `/cancel`) | ✅ |
| §10.1–10.3 + `user_devices`, indexes | ✅ |
| §12 parameters (batch 50, backoff 2 s → 5 min, 8 attempts, 256 KB, queue warning 100 / 15 min) | ✅ |
| §15 tests: durability, reconnect, duplicates, key misuse, conflict, tenant isolation, revoked access, partial batch | ✅ |
| §7 screen 6 Integration Health (F1–F3), §9 `GET /integrations/health` (+ `POST /integrations/health/:key/check`) | ✅ |
| §7 screens 7–9 Support tickets (G1–G4, H1–H5, I1–I2), §9 `/tickets` endpoints, §10.4 | ✅ |
| §7 screen 10 Language & Translation (J1–J3), §8.3, §9 `/languages`, `/translations/:language`, `/users/me/language` | ✅ |
| §7 screen 11 Product tour (K1–K3), §8.4, §9 `/product-tour/:version`, `/product-tour/progress` | ✅ |
