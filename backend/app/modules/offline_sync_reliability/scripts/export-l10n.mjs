// Copies the published catalogs and product tours into the Flutter app as bundled assets, so the app
// works offline and English (the fallback) always matches what the server publishes.
//   npm run l10n:export          (run after editing src/translations/catalogs/*.json)
import { copyFile, mkdir, readdir, writeFile } from 'node:fs/promises';

const src = new URL('../src/translations/catalogs/', import.meta.url);
const dest = new URL('../../mobile/assets/l10n/', import.meta.url);
await mkdir(dest, { recursive: true });
const files = (await readdir(src)).filter((f) => f.endsWith('.json'));
for (const f of files) await copyFile(new URL(f, src), new URL(f, dest));
console.log(`exported ${files.join(', ')} → mobile/assets/l10n/`);

// Product tour definitions ship with the app too (offline first launch).
const tourSrc = new URL('../src/product-tour/tours/', import.meta.url);
const tourDest = new URL('../../mobile/assets/tour/', import.meta.url);
await mkdir(tourDest, { recursive: true });
const tours = (await readdir(tourSrc)).filter((f) => f.endsWith('.json') && f !== 'index.json');
for (const f of tours) await copyFile(new URL(f, tourSrc), new URL(f, tourDest));
await writeFile(new URL('index.json', tourDest), JSON.stringify({ tours }, null, 2) + '\n');
console.log(`exported tours ${tours.join(', ')} → mobile/assets/tour/`);
