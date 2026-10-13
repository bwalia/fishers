#!/usr/bin/env node
/**
 * Add a batch of new strings to the dictionaries.
 *
 *   node tools/i18n/add-keys.mjs <batch.json>
 *
 * The batch is `{ "_section": "…", "key": ["English", "ਪੰਜਾਬੀ"] }`. Both files
 * get the same keys in the same order under one `// MARK:` heading, so the two
 * stay readable side by side — which is how anybody checks a translation.
 *
 * A key that already exists is an error, not an overwrite: the existing
 * wording is on screens already, and silently changing it from a batch file is
 * how a button quietly becomes something else.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const i18n = join(here, "..", "..", "web", "src", "lib", "i18n");
const batchPath = resolve(process.argv[2] ?? "");
if (!process.argv[2]) throw new Error("which batch? node tools/i18n/add-keys.mjs <batch.json>");

const batch = JSON.parse(readFileSync(batchPath, "utf8"));
const section = batch._section ?? "Added";
const entries = Object.entries(batch).filter(([k]) => !k.startsWith("_"));

const { en } = await import(join(i18n, "en.ts"));
const clash = entries.filter(([k]) => k in en);
if (clash.length) {
  console.error("already in the dictionary — pick another key or reuse the existing one:");
  for (const [k] of clash) console.error(`  ${k} = ${JSON.stringify(en[k])}`);
  process.exit(1);
}

/** A TS string literal, double-quoted the way the rest of the file is. */
const lit = (s) => JSON.stringify(s);

function insert(file, which) {
  const path = join(i18n, file);
  const source = readFileSync(path, "utf8");
  // Both files end `};` or `} as const;` — put the block just before it.
  const close = /\n\}( as const)?;\n/.exec(source);
  if (!close) throw new Error(`cannot find where ${file} closes`);
  const lines = entries.map(([key, pair]) => `  ${lit(key)}: ${lit(pair[which])},`);
  const block = `\n  // MARK: ${section}\n${lines.join("\n")}\n`;
  const at = close.index;
  writeFileSync(path, source.slice(0, at) + block + source.slice(at));
  console.log(`  ${file}: +${lines.length}`);
}

insert("en.ts", 0);
insert("pa.ts", 1);
console.log(`\nAdded ${entries.length} key(s) under "${section}".`);
