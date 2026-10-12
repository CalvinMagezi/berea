// Checks the site's JavaScript reference check against fixture.json, which the Dart harness
// wrote (packages/harness/bin/export_site.dart). Exits 1 on any disagreement.
import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { create } = require('./check.js');
const data = new URL('../data/', import.meta.url);
const read = (path) => JSON.parse(fs.readFileSync(new URL(path, data), 'utf8'));
const FIELDS = ['text', 'verified', 'unverified', 'unknownBooks', 'badQuotes', 'corrected'];

const checker = create(read('books.json'), read('index.json'));
const loadBook = async (id) => read(`bible/${id}.json`);
const fixture = read('fixture.json');
let mismatches = 0;
for (const c of fixture) {
  const got = await checker.check(c.input, loadBook);
  for (const f of FIELDS) {
    if (JSON.stringify(got[f]) === JSON.stringify(c[f])) continue;
    mismatches++;
    console.log(`MISMATCH ${f} for ${JSON.stringify(c.input)}\n  dart: ${JSON.stringify(c[f])}\n  js:   ${JSON.stringify(got[f])}`);
  }
}
console.log(`${fixture.length} cases, ${mismatches} mismatches`);
process.exit(mismatches ? 1 : 0);
