#!/usr/bin/env node
/**
 * Sentences built at runtime.
 *
 *   node tools/i18n/interpolated.mjs [--list]
 *
 * Every wrapper refuses a line carrying `\(…)`, because a pattern that matches
 * across the quotes inside an interpolation turns working code into nonsense —
 * it did, twice. So these were never going to be handled by a pass, and they
 * are most of what is left.
 *
 * Each needs a key with named placeholders, which is a wording decision:
 * "POWERPLAY — \(n) overs left" becomes `{n} overs left` and the order of the
 * words can change in another language, which is the whole point of doing it
 * this way rather than gluing strings together.
 */
import { readFileSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const appDir = join(repoRoot, "ios", "Fishers");
const DRAWN = /\b(Text|Label|Button|Section|navigationTitle|alert|confirmationDialog|accessibilityLabel|accessibilityValue|message|title|caption|label|footnote|summary|line|blurb|verb|detail)\b/;

const files = execSync(`find "${appDir}" -name '*.swift'`, { encoding: "utf8" })
  .split("\n").filter(Boolean)
  .filter((f) => !f.includes("/Generated/") && !f.endsWith("Localization.swift"));

const found = [];
for (const file of files) {
  const source = readFileSync(file, "utf8");
  if (source.includes("i18n:catalog")) continue;
  source.split("\n").forEach((line, i) => {
    if (/^\s*(\/\/|\*)/.test(line)) return;
    if (!line.includes("\\(")) return;
    // Only where it is drawn, and only if there are real words around the hole.
    if (!DRAWN.test(line)) return;
    const literal = /"([^"]*\\\([^"]*)"/.exec(line);
    if (!literal) return;
    const words = literal[1].replace(/\\\([^)]*\)/g, " ").replace(/[^A-Za-z ]/g, " ").trim();
    if (words.split(/\s+/).filter((w) => w.length > 1).length < 2) return;
    found.push({ where: `${relative(repoRoot, file)}:${i + 1}`, line: line.trim() });
  });
}

console.log(`${found.length} interpolated sentence(s) in a drawn position.`);
if (process.argv.includes("--list")) {
  for (const f of found) console.log(`${f.where}\n    ${f.line.slice(0, 150)}`);
}
