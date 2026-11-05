/**
 * Catalog messages use ICU MessageFormat: `{name}` placeholders and
 * `{count, plural, one{# change} other{# changes}}`. A translation is only
 * published when it is well-formed and uses exactly the same arguments as the
 * English source — otherwise the app falls back to English for that key.
 */

const ARG = /\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,}]/g;

export function argumentNames(message: string): Set<string> {
  return new Set([...message.matchAll(ARG)].map((m) => m[1]));
}

export function bracesBalanced(message: string): boolean {
  let depth = 0;
  for (const ch of message) {
    if (ch === '{') depth++;
    else if (ch === '}' && --depth < 0) return false;
  }
  return depth === 0;
}

export type Problem = 'UNKNOWN_KEY' | 'EMPTY' | 'UNBALANCED_BRACES' | 'ARGUMENT_MISMATCH' | 'MISSING_PLURAL_OTHER';

export function checkTranslation(english: string | undefined, translated: string): Problem | null {
  if (english === undefined) return 'UNKNOWN_KEY';
  if (!translated.trim()) return 'EMPTY';
  if (!bracesBalanced(translated)) return 'UNBALANCED_BRACES';
  const a = argumentNames(english);
  const b = argumentNames(translated);
  if (a.size !== b.size || [...a].some((x) => !b.has(x))) return 'ARGUMENT_MISMATCH';
  if (/,\s*(plural|select)\s*,/.test(translated) && !/\bother\s*\{/.test(translated)) return 'MISSING_PLURAL_OTHER';
  return null;
}

export interface CatalogFile {
  locale: string;
  name: string;
  nativeName: string;
  version: string;
  reviewed: boolean;
  messages: Record<string, string>;
}

/** Splits `@@meta` entries from messages. */
export function parseCatalog(raw: Record<string, unknown>): CatalogFile {
  const messages: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw)) if (!k.startsWith('@@') && typeof v === 'string') messages[k] = v;
  return {
    locale: String(raw['@@locale']),
    name: String(raw['@@name']),
    nativeName: String(raw['@@nativeName'] ?? raw['@@name']),
    version: String(raw['@@version']),
    reviewed: raw['@@reviewed'] === true,
    messages,
  };
}
