import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { argumentNames, checkTranslation } from '../src/translations/catalog-validation.js';
import { TranslationsService } from '../src/translations/translations.service.js';
import { startApp } from './support/app.js';

describe('catalog validation', () => {
  it('extracts ICU argument names, including plural selectors and nested args', () => {
    expect([...argumentNames('Syncing {done} of {total} · {last}')].sort()).toEqual(['done', 'last', 'total']);
    expect([...argumentNames('{count, plural, one{# change} other{# changes by {name}}}')].sort()).toEqual(['count', 'name']);
  });

  it('rejects translations that would break formatting', () => {
    expect(checkTranslation('Hello {name}', 'नमस्ते {name}')).toBeNull();
    expect(checkTranslation('Hello {name}', 'नमस्ते {naam}')).toBe('ARGUMENT_MISMATCH');
    expect(checkTranslation('Hello {name}', 'नमस्ते')).toBe('ARGUMENT_MISMATCH');
    expect(checkTranslation('Hello {name}', 'नमस्ते {name')).toBe('UNBALANCED_BRACES');
    expect(checkTranslation('{n, plural, one{# a} other{# b}}', '{n, plural, one{# क}}')).toBe('MISSING_PLURAL_OTHER');
    expect(checkTranslation(undefined, 'x')).toBe('UNKNOWN_KEY');
    expect(checkTranslation('Hi', '   ')).toBe('EMPTY');
  });
});

describe('Translations API (e2e)', () => {
  let ctx: Awaited<ReturnType<typeof startApp>>;
  const user = randomUUID();
  let token: string;
  const http = () => request(ctx.app.getHttpServer());

  beforeAll(async () => {
    ctx = await startApp('l10n_test');
    await ctx.q(`insert into users (id, status) values ($1, 'ACTIVE')`, [user]);
    token = await ctx.token(user);
  }, 120_000);

  afterAll(async () => ctx?.stop());

  it('lists launch languages without sign-in, with honest coverage and review status', async () => {
    const res = await http().get('/languages').expect(200);
    expect(res.body.defaultLanguage).toBe('en');
    const by = Object.fromEntries(res.body.languages.map((l: { code: string }) => [l.code, l]));
    expect(Object.keys(by).sort()).toEqual(['en', 'hi', 'ta', 'te']);
    expect(res.body.languages[0].code).toBe('en'); // default first
    expect(by.en).toMatchObject({ isDefault: true, coverage: 1, reviewed: true, missingCount: 0 });
    expect(by.hi).toMatchObject({ coverage: 1, reviewed: false, nativeName: 'हिन्दी' });
    expect(by.te.coverage).toBeGreaterThan(0.2);
    expect(by.te.coverage).toBeLessThan(1);
    expect(by.te.missingCount).toBeGreaterThan(0);
  });

  it('serves a versioned catalog with a translation report and ETag caching', async () => {
    const res = await http().get('/translations/te').expect(200);
    expect(res.body).toMatchObject({ languageCode: 'te', reviewed: false });
    expect(res.body.messages['sync.status.title']).toBe('సింక్ స్థితి');
    expect(res.body.missingKeys).toContain('ticket.form.submit');
    expect(res.body.messages['ticket.form.submit']).toBeUndefined(); // app falls back to English

    const etag = res.headers.etag;
    expect(etag).toBe(`"te@${res.body.catalogVersion}"`);
    await http().get('/translations/te').set('If-None-Match', etag).expect(304);

    await http().get('/translations/fr').expect(404);
    await http().get('/translations/../../etc').expect(404);
  });

  it('publishing drops invalid translations, keeps coverage honest, and is idempotent', async () => {
    const svc = ctx.app.get(TranslationsService);
    const english = { locale: 'en', name: 'English', nativeName: 'English', version: 'x', reviewed: true, messages: { a: 'Hi {name}', b: 'Bye', c: 'Count' } };
    const broken = {
      locale: 'zz',
      name: 'Test',
      nativeName: 'Test',
      version: '1',
      reviewed: false,
      messages: { a: 'Hallo {naam}', b: 'Tschüss', extra: 'nope' },
    };
    await svc.publish(broken, english);
    const [lang] = await ctx.q(`select enabled, coverage, rejected_keys, missing_keys from languages where code = 'zz'`);
    expect(lang).toMatchObject({ enabled: false, coverage: 1 / 3, rejected_keys: ['a', 'extra'], missing_keys: ['a', 'c'] });
    const countZz = async () => Number((await ctx.q<{ n: string }>(`select count(*) n from translations where language_code = 'zz'`))[0].n);
    const before = await countZz();
    expect(before).toBe(1);

    await svc.publish(broken, english); // same version → no-op
    expect(await countZz()).toBe(1);

    // Not an enabled launch language → not served.
    await http().get('/translations/zz').expect(404);
  });

  it('stores the user’s preferred language on their profile', async () => {
    await http().get('/users/me/language').expect(401);
    expect((await http().get('/users/me/language').set('Authorization', `Bearer ${token}`).expect(200)).body.languageCode).toBeNull();

    await http().patch('/users/me/language').set('Authorization', `Bearer ${token}`).send({ languageCode: 'fr' }).expect(400);
    await http().patch('/users/me/language').set('Authorization', `Bearer ${token}`).send({ languageCode: 'te; drop' }).expect(400);

    const saved = await http().patch('/users/me/language').set('Authorization', `Bearer ${token}`).send({ languageCode: 'te' }).expect(200);
    expect(saved.body.languageCode).toBe('te');
    expect((await http().get('/users/me/language').set('Authorization', `Bearer ${token}`)).body.languageCode).toBe('te');
  });
});
