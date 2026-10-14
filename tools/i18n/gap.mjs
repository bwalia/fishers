#!/usr/bin/env node
/**
 * What the app can say that the dictionary cannot translate.
 *
 *   node tools/i18n/gap.mjs [--list]
 *
 * This is the number that decides what a person sees. A string reads in
 * English for one of two reasons: the place it is written was never wrapped,
 * or it was wrapped and the dictionary has no entry for it. audit-swift.mjs
 * counts the first. This counts the second, and it is the one that stays after
 * the wrapping is done — because `tr` falls back to the English it was given.
 *
 * Deliberately English in the source and still counted here: the option arrays
 * (`["Batter", "Spinner", …]`) are the values stored on a profile, translated
 * at the point they are drawn. They need an entry like anything else.
 */
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const { en } = await import(join(repoRoot, "web", "src", "lib", "i18n", "en.ts"));
const plain = (s) => s.replace(/[\u2018\u2019]/g, "'").replace(/[\u201C\u201D]/g, '"');
const have = new Set(Object.values(en).map(plain));

const files = execSync(`find "${join(repoRoot, "ios", "Fishers")}" -name '*.swift'`, { encoding: "utf8" })
  .split("\n").filter(Boolean)
  .filter((f) => !f.includes("/Generated/") && !f.endsWith("Localization.swift"));

const missing = new Map();
for (const file of files) {
  readFileSync(file, "utf8").split("\n").forEach((line, i) => {
    if (/^\s*(\/\/|\*)/.test(line)) return;
    // A line with interpolation has quotes inside quotes, and matching across
    // them yields fragments of code rather than sentences. The wrappers skip
    // these for the same reason; they need a key with a placeholder, by hand.
    if (line.includes("\\(")) return;
    for (const m of line.matchAll(/"([^"\\]{2,})"/g)) {
      const text = m[1];
      if (!/[A-Za-z]{2,}/.test(text)) continue;
      if (!/\s/.test(text) && /^[a-z0-9_.\-/]+$/.test(text)) continue;
      if (/^\//.test(text) || /^https?:/.test(text)) continue;
      if (/^(GET|POST|PUT|PATCH|DELETE|Accept|Authorization|Bearer)$/i.test(text)) continue;
      if (/^[\d.,\-–\s%]+$/.test(text)) continue;
      // Format strings and Info.plist / asset-catalogue names.
      if (/%[@dfs.0-9]/.test(text)) continue;
      if (/^(AccentColor|AppIcon|BrandLogo|BrandMark|CFBundle\w+|NS\w+|UI\w+)$/.test(text)) continue;
      const before = line.slice(0, m.index);
      if (/\bt\(\s*$/.test(before)) continue;
      if (/(systemImage|systemName|forKey|forInfoDictionaryKey):\s*$/.test(before)) continue;
      if (/URL\(string:\s*$/.test(before) || /\bImage\(\s*$/.test(before)) continue;
      if (have.has(plain(text))) continue;
      if (!missing.has(text)) missing.set(text, `${file.replace(repoRoot + "/", "")}:${i + 1}`);
    }
  });
}

console.log(`${missing.size} distinct English string(s) the app can show with no dictionary entry.`);
if (process.argv.includes("--list")) {
  for (const [text, where] of missing) console.log(`${JSON.stringify(text)}\t${where}`);
}
