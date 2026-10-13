#!/usr/bin/env node
/**
 * Put the app's English literals onto dictionary keys.
 *
 *   node tools/i18n/convert-swift.mjs --dry    what it would change
 *   node tools/i18n/convert-swift.mjs          change it
 *
 * Only exact matches. A literal is replaced when its text is, character for
 * character, a string the web already has — so the words on the phone do not
 * change, only where they come from. Anything else is left alone and listed,
 * because guessing at a near-match is how "Save" becomes "Save changes" in one
 * place and nobody notices.
 *
 * Interpolated literals are skipped: `Text("Fee \(amount)")` is a sentence
 * built at runtime and needs a key with a `{fee}` placeholder, which is a
 * judgement about wording rather than a substitution.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const appDir = join(repoRoot, "ios", "Fishers");

/** The SwiftUI calls whose first argument is text a person reads. */
const CALLS = ["Text", "Label", "Button", "navigationTitle", "TextField", "SecureField", "Toggle"];

const { en } = await import(join(repoRoot, "web", "src", "lib", "i18n", "en.ts"));

/**
 * Text to key. Where two keys share wording the shorter key wins — it is the
 * general one ("nav.home" over "onb.step.home_tab"), and a general key is the
 * safer thing to reach for from a screen this script cannot see.
 */
/**
 * Apostrophes and quotes are typographic in the dictionary and straight in the
 * Swift. Matching on the normalised form means "You're in." finds the key whose
 * value is "You’re in." — and the app then shows the typographic one, which is
 * what the website has always shown. Same product, same punctuation.
 */
const plain = (s) => s.replace(/[\u2018\u2019]/g, "'").replace(/[\u201C\u201D]/g, '"');

const keyFor = new Map();
for (const key of Object.keys(en).sort((a, b) => a.length - b.length || a.localeCompare(b))) {
  const text = en[key];
  if (typeof text === "string" && !keyFor.has(plain(text))) keyFor.set(plain(text), key);
}

const files = execSync(`find "${appDir}" -name '*.swift'`, { encoding: "utf8" })
  .split("\n")
  .filter(Boolean)
  // Generated, and not a screen.
  .filter((f) => !f.includes("/Generated/") && !f.endsWith("Localization.swift"));

const dry = process.argv.includes("--dry");
let changed = 0;
let replaced = 0;
const skipped = new Map();

for (const file of files) {
  const before = readFileSync(file, "utf8");
  let after = before;

  for (const call of CALLS) {
    // `Text("…")` where the literal has no interpolation and no escapes we
    // would have to think about.
    const pattern = new RegExp(String.raw`\b${call}\(\s*"([^"\\]{2,})"`, "g");
    after = after.replace(pattern, (whole, text) => {
      const key = keyFor.get(plain(text));
      if (!key) {
        if (!skipped.has(text)) skipped.set(text, 0);
        skipped.set(text, skipped.get(text) + 1);
        return whole;
      }
      replaced += 1;
      return `${call}(t(${JSON.stringify(key)})`;
    });
  }

  if (after !== before) {
    changed += 1;
    if (!dry) writeFileSync(file, after);
    console.log(`  ${dry ? "would change" : "changed"}  ${relative(repoRoot, file)}`);
  }
}

console.log(`\n${replaced} literal(s) in ${changed} file(s) mapped to existing keys.`);
const remaining = [...skipped.entries()].sort((a, b) => b[1] - a[1]);
console.log(`${remaining.length} distinct literal(s) have no exact match and were left alone.`);
if (process.argv.includes("--list")) {
  for (const [text, n] of remaining) console.log(`  ${String(n).padStart(3)}x  ${JSON.stringify(text)}`);
}
