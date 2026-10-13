#!/usr/bin/env node
/**
 * i18n — give the phone the same words the website has.
 *
 *   node tools/i18n/index.mjs          write the iOS string tables
 *   node tools/i18n/index.mjs --check  fail if what is written is out of date
 *
 * The dictionaries in `web/src/lib/i18n/` are the source for every platform,
 * not just the web. They are where the Punjabi was actually done — 2,652 keys
 * with a cricket vocabulary somebody thought about — and a second copy for iOS
 * would be a second place to add a string to and a second place to forget.
 *
 * Node reads the `.ts` files directly (type stripping, Node 22.18+), so this
 * needs no build step and no dependency.
 *
 * Output is JSON in the app bundle rather than a generated Swift dictionary:
 * 2,652 entries per language as a Swift literal is a type-checker problem for
 * no gain, and nothing here needs to be a compile-time constant. What the
 * dictionary does cost in safety — the web gets a compile error for a key that
 * does not exist — `StringsTests` buys back by checking every key the app asks
 * for against the table.
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..", "..");
const i18nDir = join(repoRoot, "web", "src", "lib", "i18n");

/**
 * The languages, read out of the web's own table.
 *
 * Parsed from the source rather than imported because `index.ts` imports
 * `./en` without a file extension, which Node's resolver will not follow. The
 * table is a plain literal and this only wants one field from each row, so a
 * regex is honest here — and it throws rather than guessing if the shape moves.
 */
function locales() {
  const source = readFileSync(join(i18nDir, "index.ts"), "utf8");
  const table = /export const LOCALES = \{([\s\S]*?)\n\} as const;/.exec(source);
  if (!table) throw new Error("LOCALES is not where tools/i18n expects it in web/src/lib/i18n/index.ts");
  const rows = [...table[1].matchAll(/(\w+):\s*\{\s*native:\s*"([^"]+)",\s*dir:\s*"(\w+)"/g)]
    .map(([, id, native, dir]) => ({ id, native, dir }));
  if (!rows.some((r) => r.id === "en")) {
    throw new Error("LOCALES parsed without `en`; the regex in tools/i18n needs looking at");
  }
  return rows;
}

async function dictionaries(ids) {
  const out = {};
  for (const id of ids) {
    const module = await import(join(i18nDir, `${id}.ts`));
    const dict = module[id];
    if (!dict) throw new Error(`web/src/lib/i18n/${id}.ts does not export \`${id}\``);
    out[id] = dict;
  }
  return out;
}

/** Sorted, so a regenerated file only differs where the words did. */
function table(dict) {
  const sorted = Object.fromEntries(Object.keys(dict).sort().map((k) => [k, dict[k]]));
  return JSON.stringify(sorted, null, 2) + "\n";
}

function swift(rows, keyCount) {
  const cases = rows.map((r) => `    case ${r.id}`).join("\n");
  const natives = rows
    .map((r) => `        case .${r.id}: return ${JSON.stringify(r.native)}`)
    .join("\n");
  return `// Generated from web/src/lib/i18n/ by tools/i18n. Do not edit.
//
// ${keyCount} keys per language. The words themselves are in the JSON tables
// beside this file; only the list of languages needs to be code, because it is
// what the picker iterates and what \`Language(rawValue:)\` validates.

import Foundation

/// A language the product speaks.
enum Language: String, CaseIterable, Identifiable, Sendable {
${cases}

    var id: String { rawValue }

    /// The name in its own script, never translated. A picker that offers
    /// "Punjabi" in English is no use to somebody who cannot read English,
    /// which is the whole point of the picker.
    var native: String {
        switch self {
${natives}
        }
    }

    /// The language this build falls back to, per key.
    static let fallback: Language = .en
}
`;
}

function main(argv) {
  const check = argv.includes("--check");
  const rows = locales();
  return dictionaries(rows.map((r) => r.id)).then((dicts) => {
    const files = [
      ...rows.map((r) => ({
        path: join(repoRoot, "ios", "Fishers", "Resources", "Strings", `${r.id}.json`),
        contents: table(dicts[r.id]),
      })),
      {
        path: join(repoRoot, "ios", "Fishers", "Strings", "Generated", "Language.generated.swift"),
        contents: swift(rows, Object.keys(dicts.en).length),
      },
    ];

    let stale = 0;
    for (const { path, contents } of files) {
      const where = relative(repoRoot, path);
      if (check) {
        let current = null;
        try {
          current = readFileSync(path, "utf8");
        } catch {
          /* missing counts as stale */
        }
        if (current !== contents) {
          console.error(`  stale  ${where}`);
          stale += 1;
        }
        continue;
      }
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, contents);
      console.log(`  wrote  ${where}`);
    }

    if (check && stale) {
      console.error(`\n${stale} file(s) out of date. Run: node tools/i18n/index.mjs`);
      return 1;
    }
    if (check) console.log("  iOS strings are up to date with the web.");
    return 0;
  });
}

main(process.argv.slice(2))
  .then((code) => process.exit(code))
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
