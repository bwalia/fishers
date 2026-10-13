#!/usr/bin/env node
/**
 * The Swift converter's twin, for Compose. Same rule: exact matches only, so
 * the words do not change — only where they come from. See convert-swift.mjs.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const appDir = join(repoRoot, "android", "app", "src", "main", "kotlin");

const { en } = await import(join(repoRoot, "web", "src", "lib", "i18n", "en.ts"));
// Typographic in the dictionary, straight in the source — see convert-swift.mjs.
const plain = (s) => s.replace(/[\u2018\u2019]/g, "'").replace(/[\u201C\u201D]/g, '"');
const keyFor = new Map();
for (const key of Object.keys(en).sort((a, b) => a.length - b.length || a.localeCompare(b))) {
  if (typeof en[key] === "string" && !keyFor.has(plain(en[key]))) keyFor.set(plain(en[key]), key);
}

const files = execSync(`find "${appDir}" -name '*.kt'`, { encoding: "utf8" })
  .split("\n").filter(Boolean).filter((f) => !f.includes("/i18n/"));

const dry = process.argv.includes("--dry");
let replaced = 0, changed = 0;
const skipped = new Set();

for (const file of files) {
  const before = readFileSync(file, "utf8");
  // Compose interpolates with `$`, so a literal containing one is a sentence
  // built at runtime and needs a key with a placeholder — a wording decision,
  // not a substitution.
  let after = before.replace(/\bText\(\s*"([^"\\$]{2,})"/g, (whole, text) => {
    const key = keyFor.get(plain(text));
    if (!key) { skipped.add(text); return whole; }
    replaced += 1;
    return `Text(t(${JSON.stringify(key)})`;
  });
  if (after !== before) {
    // The call has to be in scope.
    if (!/^import com\.fishers\.app\.i18n\.t$/m.test(after)) {
      after = after.replace(/^(package [^\n]+\n)/, `$1\nimport com.fishers.app.i18n.t\n`);
    }
    changed += 1;
    if (!dry) writeFileSync(file, after);
    console.log(`  ${dry ? "would change" : "changed"}  ${relative(repoRoot, file)}`);
  }
}
console.log(`\n${replaced} literal(s) in ${changed} file(s) mapped to existing keys.`);
console.log(`${skipped.size} distinct literal(s) have no exact match and were left alone.`);
if (process.argv.includes("--list")) for (const s of skipped) console.log("   ", JSON.stringify(s));
