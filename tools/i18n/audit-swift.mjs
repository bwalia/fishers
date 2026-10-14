#!/usr/bin/env node
/**
 * Every string a person could read, wherever it is written.
 *
 *   node tools/i18n/audit-swift.mjs [--list]
 *
 * convert-swift.mjs only ever looked at a literal in the first argument of
 * seven calls, and "0 left" meant "0 left that it looks at" — which is a
 * circular answer and was the wrong one. This looks at every literal in the
 * app target and rules things out explicitly, so what is left is what is
 * genuinely still English.
 */
import { readFileSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const appDir = join(repoRoot, "ios", "Fishers");

/** Positions where a literal is never read by a person. */
const NOT_COPY = [
  /\bt\(\s*$/,                                   // the key we just gave t()
  /\btr\(\s*$/,                                  // already translated by its English
  /systemImage:\s*$/, /systemName:\s*$/,         // SF Symbols
  /\bImage\(\s*$/, /decorative:\s*$/,
  /forKey:\s*$/, /forInfoDictionaryKey:\s*$/,    // defaults / plist keys
  /UserDefaults[^\n]*\bstring\(forKey:\s*$/,
  /\bURL\(string:\s*$/, /\bscheme\s*==\s*$/,
  /accessibilityIdentifier\(\s*$/,
  /\bcase\s+\w+\s*=\s*$/,                        // handled separately, see below
  /KeychainStore\.\w+\(\s*$/,
  /\bNSLog\(\s*$/, /\bprint\(\s*$/, /\bassert\w*\(/,
  /CodingKeys/, /\bkey:\s*"[^"]*"\s*\)/,
];

const files = execSync(`find "${appDir}" -name '*.swift'`, { encoding: "utf8" })
  .split("\n").filter(Boolean)
  .filter((f) => !f.includes("/Generated/") && !f.endsWith("Localization.swift"));

const findings = [];
const catalogs = [];
for (const file of files) {
  const source = readFileSync(file, "utf8");
  // A catalog holds the canonical English of values that are stored and sent,
  // translated where they are drawn. Counting those as "still in English" is
  // true of the source and false of the screen, and the difference matters
  // when the number is a ratchet.
  if (source.includes("i18n:catalog")) { catalogs.push(relative(repoRoot, file)); continue; }
  const lines = source.split("\n");
  lines.forEach((line, i) => {
    // Skip comments and the doc-comment prose that fills this codebase.
    if (/^\s*(\/\/|\*|\/\*)/.test(line)) return;
    for (const m of line.matchAll(/"([^"\\]{2,})"/g)) {
      const text = m[1];
      // Must contain a word a person would read.
      if (!/[A-Za-z]{2,}/.test(text)) continue;
      // Pure identifiers: no space, all lowercase or dotted — keys, not copy.
      if (!/\s/.test(text) && /^[a-z0-9_.\-/]+$/.test(text)) continue;
      // An SF Symbol: dotted lowercase words, never a sentence.
      if (/^[a-z0-9.]+$/.test(text) && text.includes(".")) continue;
      // HTTP verbs, header names and query fragments — wire words, not copy.
      if (/^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$/.test(text)) continue;
      if (/^(Accept|Authorization|Content-Type|application\/json|Bearer)$/i.test(text)) continue;
      if (/^[a-z_]+=[^\s]*&?$/.test(text)) continue;
      // An API path or a URL fragment.
      if (/^\//.test(text) || /^https?:/.test(text)) continue;
      // A number, a version, a scale point: "18.2", "2.5", "0.0".
      if (/^[\d.,\-–\s%]+$/.test(text)) continue;
      // A format or a separator with a stray word: " · ", " } ?? ".
      if (!/[A-Za-z]{2,}/.test(text.replace(/[^A-Za-z]/g, " ").trim())) continue;
      // Date and number format patterns — read by a formatter, not a person.
      if (/^[yMdHhmsaEZ:.,\/\s'#0-]+$/.test(text) && !/[a-z]{3,}/i.test(text.replace(/[yMdHhmsaEZ]/g, ""))) continue;
      const before = line.slice(0, m.index);
      if (NOT_COPY.some((re) => re.test(before))) continue;
      findings.push({ file: relative(repoRoot, file), line: i + 1, text, source: line.trim() });
    }
  });
}

/**
 * Code that got wrapped as if it were words.
 *
 * The wrapper once matched across two adjacent literals — `of: "_", with: " "`
 * became `of: "_tr(", with: ") "` — which compiles, runs, and silently does
 * the wrong thing. A green build said nothing. This is the check that would
 * have.
 */
const mangled = [];
for (const file of files) {
  readFileSync(file, "utf8").split("\n").forEach((line, i) => {
    // The signature is a *string literal* that contains a call. Looking for
    // `tr(` with a word boundary misses the real case, because the corruption
    // reads `"_tr("` and `_` is a word character — which is how this check
    // passed on the very corruption it was written for.
    // A *literal whose body contains a call* is the signature. Matching the
    // gap between two adjacent literals is not — `? tr("Bat") : tr("Bowl")`
    // looks the same to a careless pattern, and flagging it would bury the
    // real one. This check has now been wrong in both directions, so it is
    // written to say exactly what it means.
    for (const m of line.matchAll(/"([^"\\]*)"/g)) {
      if (/tr\(|String\(format:/.test(m[1])) {
        mangled.push(`${relative(repoRoot, file)}:${i + 1}  wrapped across two literals: ${m[0]}`);
      }
    }
    // A key sent through the English translator. It works by accident — `tr`
    // does not know the key, so it hands it back and `t` looks it up — but it
    // says the wrapper could not tell a key from a sentence, and the next one
    // it cannot tell apart may not be harmless.
    for (const m of line.matchAll(/\bt\(\s*tr\(/g)) {
      mangled.push(`${relative(repoRoot, file)}:${i + 1}  key passed through tr(): ${m[0]}`);
    }
    // And a lookup key dressed as a caption.
    for (const m of line.matchAll(/\[\s*tr\("[^"]*"\)\s*\]/g)) {
      mangled.push(`${relative(repoRoot, file)}:${i + 1}  subscript key wrapped: ${m[0]}`);
    }
  });
}
if (mangled.length) {
  console.error("Code wrapped as if it were words — a wrapper matched across two literals:");
  for (const m of mangled) console.error(`  ${m}`);
  process.exitCode = 1;
}

const byText = new Map();
for (const f of findings) {
  if (!byText.has(f.text)) byText.set(f.text, []);
  byText.get(f.text).push(f);
}
const byFile = new Map();
for (const f of findings) byFile.set(f.file, (byFile.get(f.file) ?? 0) + 1);

console.log(`${findings.length} user-readable literal(s) still in English, in ${byFile.size} file(s).`);
if (catalogs.length) {
  console.log(`(${catalogs.length} catalog file(s) skipped — English there is the stored value: ${catalogs.join(", ")})`);
}
console.log(`${byText.size} distinct.\n`);
console.log("Worst files:");
for (const [file, n] of [...byFile].sort((a, b) => b[1] - a[1]).slice(0, 15)) {
  console.log(`  ${String(n).padStart(4)}  ${file}`);
}
/**
 * A ratchet, not a target.
 *
 * The count may fall and must never rise. It exists because "nothing left in
 * English" has been claimed twice from a tool that only looked at part of the
 * app, and a number in CI is harder to fool than a claim in a commit message.
 */
const cap = process.argv.find((a) => a.startsWith("--max="));
if (cap) {
  const max = Number(cap.slice("--max=".length));
  if (findings.length > max) {
    console.error(`\nThat is ${findings.length - max} more than the agreed ${max}.`);
    console.error("Wrap them (tools/i18n/wrap-calls.mjs) or lower the cap if you have.");
    process.exit(1);
  }
  console.log(`\nWithin the cap of ${max}.`);
}

if (process.argv.includes("--list")) {
  console.log("\n--- every one ---");
  for (const [text, where] of [...byText].sort((a, b) => b[1].length - a[1].length)) {
    console.log(`${String(where.length).padStart(3)}x ${JSON.stringify(text)}`);
    console.log(`     ${where[0].file}:${where[0].line}  ${where[0].source.slice(0, 100)}`);
  }
}
