import { BadRequestException, Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';
import { and, asc, desc, eq } from 'drizzle-orm';
import { readdir, readFile } from 'node:fs/promises';
import { type Db, InjectDb } from '../db/db.module.js';
import { languages, translations, userPreferences } from '../db/schema.js';
import { type CatalogFile, checkTranslation, parseCatalog } from './catalog-validation.js';

export const DEFAULT_LANGUAGE = 'en';
const CATALOG_DIR = new URL('./catalogs/', import.meta.url);
const INSERT_CHUNK = 500;

/**
 * Publishes the versioned catalogs shipped in `catalogs/*.json` and serves them.
 * English is the source of truth; other languages are validated against it and
 * missing or invalid keys fall back to English in the app (spec §8.3).
 */
@Injectable()
export class TranslationsService implements OnModuleInit {
  private readonly logger = new Logger(TranslationsService.name);
  private readonly cache = new Map<string, { version: string; messages: Record<string, string> }>();

  constructor(@InjectDb() private readonly db: Db) {}

  async onModuleInit() {
    await this.publishFromDisk();
  }

  /** Enabled launch languages (spec §18 decision). Default: en,hi,te,ta. */
  private enabledCodes(): Set<string> {
    return new Set((process.env.ENABLED_LANGUAGES ?? 'en,hi,te,ta').split(',').map((s) => s.trim()).filter(Boolean));
  }

  async publishFromDisk() {
    const files = (await readdir(CATALOG_DIR)).filter((f) => f.endsWith('.json')).sort();
    const catalogs = await Promise.all(
      files.map(async (f) => parseCatalog(JSON.parse(await readFile(new URL(f, CATALOG_DIR), 'utf8')))),
    );
    const english = catalogs.find((c) => c.locale === DEFAULT_LANGUAGE);
    if (!english) throw new Error('catalogs/en.json is required (English is the source catalog)');
    for (const c of catalogs) await this.publish(c, english);
  }

  /** Idempotent: a catalog version is written once; re-running is a no-op. */
  async publish(catalog: CatalogFile, english: CatalogFile) {
    const [current] = await this.db
      .select({ catalogVersion: languages.catalogVersion })
      .from(languages)
      .where(eq(languages.code, catalog.locale));
    if (current?.catalogVersion === catalog.version) return;

    const valid: Record<string, string> = {};
    const rejected: string[] = [];
    for (const [key, value] of Object.entries(catalog.messages)) {
      const problem = checkTranslation(english.messages[key], value);
      if (problem) {
        rejected.push(key);
        this.logger.warn(`[${catalog.locale}@${catalog.version}] ${key}: ${problem}`);
      } else {
        valid[key] = value;
      }
    }
    const englishKeys = Object.keys(english.messages);
    const missing = englishKeys.filter((k) => !(k in valid));
    const row = {
      code: catalog.locale,
      name: catalog.name,
      nativeName: catalog.nativeName,
      enabled: this.enabledCodes().has(catalog.locale),
      isDefault: catalog.locale === DEFAULT_LANGUAGE,
      catalogVersion: catalog.version,
      reviewed: catalog.reviewed,
      coverage: englishKeys.length ? (englishKeys.length - missing.length) / englishKeys.length : 1,
      missingKeys: missing,
      rejectedKeys: rejected,
      publishedAt: new Date(),
    };

    // Messages and the language row switch versions together.
    await this.db.transaction(async (tx) => {
      const entries = Object.entries(valid).map(([key, value]) => ({
        languageCode: catalog.locale,
        key,
        value,
        catalogVersion: catalog.version,
      }));
      for (let i = 0; i < entries.length; i += INSERT_CHUNK) {
        await tx.insert(translations).values(entries.slice(i, i + INSERT_CHUNK)).onConflictDoNothing();
      }
      const { code, ...rest } = row;
      await tx.insert(languages).values(row).onConflictDoUpdate({ target: languages.code, set: rest });
      void code;
    });
    this.cache.delete(catalog.locale);
    this.logger.log(
      `published ${catalog.locale}@${catalog.version}: ${Object.keys(valid).length}/${englishKeys.length} keys` +
        (rejected.length ? `, ${rejected.length} rejected` : ''),
    );
  }

  async listLanguages() {
    const rows = await this.db
      .select()
      .from(languages)
      .where(eq(languages.enabled, true))
      .orderBy(desc(languages.isDefault), asc(languages.code));
    return {
      defaultLanguage: DEFAULT_LANGUAGE,
      languages: rows.map((l) => ({
        code: l.code,
        name: l.name,
        nativeName: l.nativeName,
        isDefault: l.isDefault,
        catalogVersion: l.catalogVersion,
        reviewed: l.reviewed,
        coverage: Math.round(l.coverage * 1000) / 1000,
        missingCount: l.missingKeys.length,
      })),
    };
  }

  async catalog(code: string) {
    const [lang] = await this.db
      .select()
      .from(languages)
      .where(and(eq(languages.code, code), eq(languages.enabled, true)));
    if (!lang) throw new NotFoundException({ code: 'LANGUAGE_NOT_AVAILABLE', message: 'This language is not available.' });

    let cached = this.cache.get(code);
    if (!cached || cached.version !== lang.catalogVersion) {
      const rows = await this.db
        .select({ key: translations.key, value: translations.value })
        .from(translations)
        .where(and(eq(translations.languageCode, code), eq(translations.catalogVersion, lang.catalogVersion)));
      cached = { version: lang.catalogVersion, messages: Object.fromEntries(rows.map((r) => [r.key, r.value])) };
      this.cache.set(code, cached);
    }
    return {
      languageCode: code,
      catalogVersion: lang.catalogVersion,
      reviewed: lang.reviewed,
      coverage: lang.coverage,
      // The "translation report": what still shows in English.
      missingKeys: lang.missingKeys,
      messages: cached.messages,
    };
  }

  async userLanguage(userId: string) {
    const [pref] = await this.db.select().from(userPreferences).where(eq(userPreferences.userId, userId));
    return { languageCode: pref?.language ?? null, updatedAt: pref?.updatedAt ?? null };
  }

  async setUserLanguage(userId: string, code: string) {
    const [lang] = await this.db
      .select({ code: languages.code })
      .from(languages)
      .where(and(eq(languages.code, code), eq(languages.enabled, true)));
    if (!lang) throw new BadRequestException({ code: 'LANGUAGE_NOT_AVAILABLE', message: 'This language is not available.' });
    const now = new Date();
    const [pref] = await this.db
      .insert(userPreferences)
      .values({ userId, language: code, updatedAt: now })
      .onConflictDoUpdate({ target: userPreferences.userId, set: { language: code, updatedAt: now } })
      .returning();
    return { languageCode: pref.language, updatedAt: pref.updatedAt };
  }
}
