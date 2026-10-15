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
    // Walk the literals with escapes honoured. The regex this replaced skipped
    // any literal containing a backslash and matched the gap to the next one,
    // so `t("k", vars: ["n": n])` was reported as the missing string
    // `", vars: ["`. Most of what this tool used to list was that.
    const literals = [];
    for (let at = 0; at < line.length; ) {
      const open = line.indexOf('"', at);
      if (open < 0) break;
      let close = open + 1;
      while (close < line.length && !(line[close] === '"' && line[close - 1] !== "\\")) close += 1;
      if (close >= line.length) break;
      literals.push({ body: line.slice(open + 1, close), index: open });
      at = close + 1;
    }
    for (const m of literals.map((l) => ({ 1: l.body, index: l.index }))) {
      const text = m[1];
      if (text.length < 2) continue;
      // Built at runtime; interpolated.mjs is where those are counted.
      if (text.includes("\\(")) continue;
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

/**
 * Strings that are not words, listed one by one rather than matched by a
 * pattern — a pattern would quietly swallow the next real sentence that
 * happened to look like one of these.
 *
 * Each is here because translating it would break something: a key the server
 * or the system reads, a format a date formatter parses, a code a comparison
 * depends on, or the demo club's fixtures, which are seed data rather than
 * copy.
 */
const NOT_WORDS = new Set([
  // Info.plist keys, UserDefaults keys, launch arguments, environment names.
  "FishersAPIBaseURL", "FishersWebBaseURL", "FishersLANAPIBaseURL", "FishersLANWebBaseURL",
  "FISHERS_API_URL", "FISHERS_WEB_URL", "FISHERS_UITEST_ACCESS_TOKEN", "FISHERS_UITEST_REFRESH_TOKEN",
  "-FishersSignOutOnLaunch", "fishers:fixtures-guide-dismissed", "OfflineCache", "invalidURL",
  "com.google.GIDSignIn", "Content-Type", "cricket_season=true&", ":welcomed", "+captain",
  // Formats and locales, read by a formatter and never by a person.
  "HH:mm", "EEE HH:mm", "yyyy-MM-dd", "en_GB", "en_US_POSIX", "in (\\d+)s",
  // Codes a comparison depends on: iCal weekdays, the Test match format, the
  // currency. Translate one and the comparison stops matching.
  "SU", "WE", "SA", "TEST", "GBP",
  // Pieces a string is split on, not sentences: `replacingOccurrences(of:
  // " standard")`, `separators = [" vs ", " v "]`.
  " standard", " vs ", " and ",
  // The demo club's seeded fixtures. Sample data, shipped so an empty account
  // has something in it; translating it would be translating test fixtures.
  "London Lords", "Middlesex League", "Watford", "Wednesday Nets", "Saturday League",
  "Sunday Social Cricket", "Main square, Nursery ground", "40 overs", "20/1 (2.0 ov)",
  // A local's name that happens to sit inside an interpolation.
  "perBowler",
]);

const words = [...missing].filter(([text]) => !NOT_WORDS.has(text));
const plumbing = missing.size - words.length;

console.log(`${words.length} distinct English string(s) the app can show with no dictionary entry.`);
console.log(`(${plumbing} more are named in NOT_WORDS — keys, formats, codes and demo data, which must stay as they are.)`);

// Zero is the bar now. A new English string with no entry fails the build
// rather than waiting to be noticed on a screen, which is how this one was.
if (process.argv.includes("--strict") && words.length > 0) {
  console.error("\nAdd them with tools/i18n/add-keys.mjs, or name them in NOT_WORDS if they are not words.");
  process.exit(1);
}

if (process.argv.includes("--list")) {
  for (const [text, where] of words) console.log(`${JSON.stringify(text)}\t${where}`);
}
