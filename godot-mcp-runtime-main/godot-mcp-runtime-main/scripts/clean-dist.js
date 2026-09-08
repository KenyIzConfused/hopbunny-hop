import { rmSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

// Wipe dist/ before every build so tsc never leaves orphaned .js/.d.ts output
// behind when a source file is renamed or deleted. Stale orphans otherwise keep
// their original mtime forever, which trips build-freshness checks (oldest-dist
// vs newest-src) into false "stale" positives long after a clean rebuild.
const __dirname = dirname(fileURLToPath(import.meta.url));
const dist = join(__dirname, '..', 'dist');

rmSync(dist, { recursive: true, force: true });
