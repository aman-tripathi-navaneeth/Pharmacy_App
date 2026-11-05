import { BadRequestException, Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';
import { and, eq } from 'drizzle-orm';
import { readdir, readFile } from 'node:fs/promises';
import { type Db, InjectDb } from '../db/db.module.js';
import { tourProgress, type TourStatus } from '../db/schema.js';
import { compareVersions } from './versions.js';

type TourProgressRow = typeof tourProgress.$inferSelect;

const TOURS_DIR = new URL('./tours/', import.meta.url);
const EN_CATALOG = new URL('../translations/catalogs/en.json', import.meta.url);

const STEP_TYPES = ['info', 'syncStates', 'finish'] as const;
const ICONS = ['storefront', 'dashboard', 'cloud_off', 'support', 'sync', 'check', 'translate'];
const TONES = ['neutral', 'info', 'success', 'warning', 'error'];

export interface TourStep {
  id: string;
  type: (typeof STEP_TYPES)[number];
  icon: string;
  titleKey: string;
  bodyKey?: string;
  items?: { labelKey: string; descriptionKey: string; tone: string }[];
}

export interface TourDefinition {
  version: string;
  steps: TourStep[];
}

/**
 * Serves versioned tour content (`tours/<version>.json`) and per-user progress.
 * Step text is translation keys, so the tour follows the user's language. A
 * definition that references an unknown key fails at startup, not on a phone.
 */
@Injectable()
export class ProductTourService implements OnModuleInit {
  private readonly logger = new Logger(ProductTourService.name);
  private tours = new Map<string, TourDefinition>();
  private latest: string;

  constructor(@InjectDb() private readonly db: Db) {}

  async onModuleInit() {
    const english = JSON.parse(await readFile(EN_CATALOG, 'utf8')) as Record<string, string>;
    const files = (await readdir(TOURS_DIR)).filter((f) => f.endsWith('.json'));
    for (const f of files) {
      const def = JSON.parse(await readFile(new URL(f, TOURS_DIR), 'utf8')) as TourDefinition;
      validateTour(def, english);
      this.tours.set(def.version, def);
    }
    if (!this.tours.size) throw new Error('No product tour definitions found');
    this.latest = [...this.tours.keys()].sort(compareVersions).at(-1)!;
    this.logger.log(`product tours: ${[...this.tours.keys()].join(', ')} (latest ${this.latest})`);
  }

  tour(version: string): TourDefinition {
    const def = this.tours.get(version === 'latest' ? this.latest : version);
    if (!def) throw new NotFoundException({ code: 'TOUR_NOT_FOUND', message: 'This tour version does not exist.' });
    return def;
  }

  private key(userId: string, version: string) {
    return and(eq(tourProgress.userId, userId), eq(tourProgress.tourVersion, version));
  }

  async getProgress(userId: string, version: string) {
    const def = this.tour(version);
    const [p] = await this.db.select().from(tourProgress).where(this.key(userId, def.version));
    return { tourVersion: def.version, progress: p ? toDto(p) : null };
  }

  /**
   * Records a step view, a skip or a completion. Idempotent and monotonic:
   * once a version is COMPLETED it stays completed (a restart only counts).
   * The row is locked for the read-decide-write, so concurrent posts can't race.
   */
  async saveProgress(userId: string, body: { tourVersion: string; stepId: string; status: TourStatus }) {
    const def = this.tour(body.tourVersion);
    if (!def.steps.some((s) => s.id === body.stepId)) {
      throw new BadRequestException({ code: 'UNKNOWN_STEP', message: 'Unknown tour step.' });
    }
    const saved = await this.db.transaction(async (tx) => {
      const [existing] = await tx.select().from(tourProgress).where(this.key(userId, def.version)).for('update');
      const now = new Date();
      const restarting =
        !!existing && body.status === 'IN_PROGRESS' && body.stepId === def.steps[0].id && existing.lastStepId !== body.stepId;
      const status = nextStatus(existing?.status, body.status, restarting);
      const values = {
        status,
        lastStepId: body.stepId,
        stepsSeen: existing ? [...new Set([...existing.stepsSeen, body.stepId])] : [body.stepId],
        completedAt: body.status === 'COMPLETED' && !existing?.completedAt ? now : (existing?.completedAt ?? null),
        skippedAt: body.status === 'SKIPPED' && existing?.status !== 'COMPLETED' ? now : (existing?.skippedAt ?? null),
        restarts: (existing?.restarts ?? 0) + (restarting ? 1 : 0),
        updatedAt: now,
      };
      const [row] = existing
        ? await tx.update(tourProgress).set(values).where(this.key(userId, def.version)).returning()
        : await tx
            .insert(tourProgress)
            .values({ userId, tourVersion: def.version, ...values })
            // A concurrent first insert wins; this request's update then applies on its row.
            .onConflictDoUpdate({ target: [tourProgress.userId, tourProgress.tourVersion], set: values })
            .returning();
      return row;
    });
    return { tourVersion: def.version, progress: toDto(saved) };
  }
}

/**
 * COMPLETED is final for a version. A SKIPPED tour only becomes IN_PROGRESS again
 * when the user explicitly restarts it from step 1 — a late, out-of-order step
 * update from an offline device must not revive a tour the user skipped.
 */
export function nextStatus(current: TourStatus | undefined, requested: TourStatus, restarting: boolean): TourStatus {
  if (current === 'COMPLETED') return 'COMPLETED';
  if (current === 'SKIPPED' && requested === 'IN_PROGRESS' && !restarting) return 'SKIPPED';
  return requested;
}

function toDto(p: TourProgressRow) {
  return {
    status: p.status,
    lastStepId: p.lastStepId,
    stepsSeen: p.stepsSeen,
    completedAt: p.completedAt ?? null,
    skippedAt: p.skippedAt ?? null,
    restarts: p.restarts,
    updatedAt: p.updatedAt,
  };
}

export function validateTour(def: TourDefinition, english: Record<string, string>) {
  const fail = (msg: string) => {
    throw new Error(`Invalid product tour ${def.version}: ${msg}`);
  };
  if (!/^\d+(\.\d+)+$/.test(def.version ?? '')) fail('version must look like 2026.10.1');
  if (!Array.isArray(def.steps) || def.steps.length < 2 || def.steps.length > 8) fail('a tour has 2–8 steps (spec §12: 5–8)');
  const ids = new Set<string>();
  for (const s of def.steps) {
    if (!/^[a-zA-Z][a-zA-Z0-9]*$/.test(s.id) || ids.has(s.id)) fail(`bad or duplicate step id "${s.id}"`);
    ids.add(s.id);
    if (!STEP_TYPES.includes(s.type)) fail(`step ${s.id}: unknown type ${s.type}`);
    if (!ICONS.includes(s.icon)) fail(`step ${s.id}: unknown icon ${s.icon}`);
    const keys = [s.titleKey, s.bodyKey, ...(s.items ?? []).flatMap((i) => [i.labelKey, i.descriptionKey])].filter(
      (k): k is string => k !== undefined,
    );
    for (const k of keys) if (!(k in english)) fail(`step ${s.id}: translation key "${k}" missing from en.json`);
    for (const i of s.items ?? []) if (!TONES.includes(i.tone)) fail(`step ${s.id}: unknown tone ${i.tone}`);
    if (s.type === 'syncStates' && !s.items?.length) fail(`step ${s.id}: syncStates needs items`);
  }
  if (def.steps.at(-1)!.type !== 'finish') fail('the last step must be the finish step');
}
