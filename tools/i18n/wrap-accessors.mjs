#!/usr/bin/env node
/**
 * Wrap the literals inside display accessors.
 *
 *   node tools/i18n/wrap-accessors.mjs [--dry]
 *
 * `var label: String { self == .bat ? "Bat" : "Bowl" }` is a model saying what
 * to draw. The enum's `rawValue` is what is coded and sent; the label is only
 * ever read by a person, so wrapping it is safe in a way that wrapping the raw
 * value would not be.
 *
 * Only accessors named for display. `name`, `key`, `id`, `value`, `path` and
 * `query` are deliberately absent — those are the ones that travel.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

/**
 * A line carrying string interpolation is left alone.
 *
 * `"…bye\(runs == 1 ? "" : "s")…"` has quotes inside quotes, and a regex that
 * matches the inner `"s"` turns a working line into `"str("`. These need a key
 * with a placeholder rather than a wrap, which is a wording decision — so they
 * are reported, not guessed at.
 */
const interpolated = (line) => line.includes("\\(");

/** A raw value has to be a literal — wrapping one does not compile. */
const rawValue = (line) => /\bcase\s+\w+\s*=\s*"/.test(line) || /,\s*\w+\s*=\s*"/.test(line);

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const appDir = join(repoRoot, "ios", "Fishers");
const dry = process.argv.includes("--dry");

const DISPLAY = [
  "label", "title", "caption", "blurb", "summary", "hint", "footnote",
  "message", "headline", "subtitle", "explanation", "wording", "sentence", "text",
];
const decl = new RegExp(String.raw`^(\s*)(?:public |private |fileprivate |internal )?var (${DISPLAY.join("|")}): String\??\s*\{`);

let wrapped = 0, changed = 0;
const files = execSync(`find "${appDir}" -name '*.swift'`, { encoding: "utf8" })
  .split("\n").filter(Boolean)
  .filter((f) => !f.includes("/Generated/") && !f.endsWith("Localization.swift"));

for (const file of files) {
  const lines = readFileSync(file, "utf8").split("\n");
  let out = [...lines];
  let touched = false;

  for (let i = 0; i < lines.length; i++) {
    const m = decl.exec(lines[i]);
    if (!m) continue;
    // Count braces from the declaration until they balance. Guessing the end
    // from indentation ran past the accessor and into the enum's own cases,
    // where it wrapped raw values — which have to be literals, and did not
    // compile. Balanced braces cannot do that.
    let depth = 0, end = -1;
    for (let j = i; j < lines.length && j - i <= 80; j++) {
      for (const ch of lines[j]) {
        if (ch === "{") depth += 1;
        else if (ch === "}") depth -= 1;
      }
      if (depth <= 0) { end = j; break; }
    }
    if (end < 0) continue;   // not a shape we understand; leave it alone
    for (let j = i; j <= end; j++) {
      if (/^\s*(\/\/|\*)/.test(out[j])) continue;
      if (interpolated(out[j]) || rawValue(out[j])) continue;
      out[j] = out[j].replace(/"([^"\\]{2,})"/g, (whole, text) => {
        if (!/[A-Za-z]{2,}/.test(text)) return whole;
        // Already handled, or an SF Symbol.
        if (/^[a-z0-9.]+$/.test(text) && text.includes(".")) return whole;
        wrapped += 1;
        touched = true;
        return `tr(${JSON.stringify(text)})`;
      });
    }
  }
  if (touched) {
    changed += 1;
    if (!dry) writeFileSync(file, out.join("\n"));
  }
}
console.log(`${wrapped} literal(s) in ${changed} display accessor file(s) ${dry ? "would be" : ""} wrapped.`);
