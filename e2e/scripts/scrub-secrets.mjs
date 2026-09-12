#!/usr/bin/env node
/**
 * Take the test accounts' password out of everything the run leaves behind,
 * before any of it is uploaded.
 *
 * The suite signs in the way a person does — by typing the password into the
 * page — so Playwright records it: in the error-context snapshot of the form,
 * and inside a trace's network log. Artifacts of a public repository are
 * public, and the int accounts are real accounts. Screenshots and videos are
 * safe (the field shows dots); text files are rewritten, and any trace that
 * still holds the password is deleted rather than shipped.
 *
 * Run with E2E_PASSWORD set, from the e2e directory:
 *   node scripts/scrub-secrets.mjs [more-secrets…]
 */
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const DIRS = ["test-results", "playwright-report"];
const REDACTED = "«redacted»";
const secrets = [process.env.E2E_PASSWORD, ...process.argv.slice(2)]
  .map((s) => (s ?? "").trim())
  .filter((s) => s.length >= 8);

if (!secrets.length) {
  console.log("scrub: nothing to look for (E2E_PASSWORD not set) — leaving the artifacts alone.");
  process.exit(0);
}

/// Files a person reads: rewritten in place. Anything else that contains a
/// secret is deleted, because there is no safe way to edit it here.
const TEXT = /\.(md|json|txt|log|html|js|css|xml|yaml|yml|jsonl)$/i;

/// A trace is a zip: what it holds is compressed, so the plain bytes never
/// match. Unpack it to look. Without `unzip` there is no way to be sure, and
/// an unsure trace is deleted rather than published.
function zipHoldsSecret(path) {
  const out = spawnSync("unzip", ["-p", path], { maxBuffer: 512 * 1024 * 1024 });
  if (out.error || out.status !== 0) {
    console.log(`scrub: cannot read inside ${path} (${out.error?.message ?? `unzip exit ${out.status}`})`);
    return true;
  }
  return secrets.some((s) => out.stdout.includes(Buffer.from(s)));
}

let cleaned = 0;
let deleted = 0;

function walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(path);
      continue;
    }
    if (!entry.isFile() || statSync(path).size === 0) continue;
    const bytes = readFileSync(path);
    const hit = /\.zip$/i.test(path)
      ? zipHoldsSecret(path)
      : secrets.some((s) => bytes.includes(Buffer.from(s)));
    if (!hit) continue;
    if (TEXT.test(path)) {
      let text = bytes.toString("utf8");
      for (const s of secrets) text = text.split(s).join(REDACTED);
      writeFileSync(path, text);
      cleaned++;
      console.log(`scrub: redacted ${path}`);
    } else {
      rmSync(path, { force: true });
      deleted++;
      console.log(`scrub: deleted ${path} (held a secret and cannot be edited safely)`);
    }
  }
}

for (const dir of DIRS) if (existsSync(dir)) walk(dir);
console.log(`scrub: ${cleaned} file(s) redacted, ${deleted} deleted.`);

// Prove it: nothing left holding a secret.
let left = 0;
function check(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) check(path);
    else if (
      entry.isFile() &&
      (/\.zip$/i.test(path)
        ? zipHoldsSecret(path)
        : secrets.some((s) => readFileSync(path).includes(Buffer.from(s))))
    ) {
      console.error(`scrub: STILL PRESENT in ${path}`);
      left++;
    }
  }
}
for (const dir of DIRS) if (existsSync(dir)) check(dir);
if (left) {
  console.error("scrub: refusing to call this clean.");
  process.exit(1);
}
