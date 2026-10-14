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
  // Found by listing every `var …: String {` in the app and keeping the ones
  // whose value is only ever drawn. `id`, `systemImage`, `address`, `initials`,
  // `firstName`, `theirName` and the rest are left out on purpose: they are
  // identifiers, SF Symbols, or somebody's actual name.
  "shortLabel", "shortTitle", "shortName", "missing", "responsibilities",
  "verb", "word", "line", "freshness", "syncLabel", "detail", "errorDescription",
];
/**
 * A name that says the value is read, wherever it sits in the identifier:
 * `scoringButtonTitle`, `headline(for:)`, `statusMessage`. Matching the whole
 * name against a fixed list missed most of them — these are the words, and the
 * name has to end with one so `titleId` or `labelKey` is not swept up.
 */
const ENDS = "(title|label|headline|caption|message|summary|blurb|note|hint|phrase|wording|sentence|text|verb|word)";
const decl = new RegExp(
  String.raw`^(\s*)(?:public |private |fileprivate |internal |static )*` +
  String.raw`(?:var (?:${DISPLAY.join("|")}|\w*${ENDS})\s*:\s*String\??\s*\{` +
  String.raw`|func (?:${DISPLAY.join("|")}|\w*${ENDS})\s*\([^)]*\)\s*->\s*String\??\s*\{)`,
  "i",
);

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
      if (/\\\([^)]*"/.test(out[j]) || rawValue(out[j])) continue;
      // Walk the literals rather than pattern-matching the line, for the same
      // reason wrap-calls does: a pattern can match the gap between two
      // adjacent literals. It also lets the one already inside `tr(` be seen
      // and left alone, instead of becoming `tr(tr("…"))`.
      const line = out[j];
      let rebuilt = "";
      let at = 0;
      while (at < line.length) {
        const open = line.indexOf('"', at);
        if (open < 0) { rebuilt += line.slice(at); break; }
        let close = open + 1;
        while (close < line.length && !(line[close] === '"' && line[close - 1] !== "\\")) close += 1;
        if (close >= line.length) { rebuilt += line.slice(at); break; }
        const body = line.slice(open + 1, close);
        const before = line.slice(at, open);
        const skip =
          body.length < 2 ||
          // `"\(season.seasonYear)"` is a value rendered as text, not words.
          body.includes("\\(") ||
          !/[A-Za-z]{2,}/.test(body) ||
          (/^[a-z0-9.]+$/.test(body) && body.includes(".")) ||
          /\b(t|tr)\($/.test(before) ||
          // A dictionary key: `vars: ["away": …]` names the placeholder the
          // translation will look for. Translate the key and `{away}` is
          // never substituted — in Punjabi only, where nobody is looking.
          /[\[,]\s*$/.test(before) && /^\s*:/.test(line.slice(close + 1)) ||
          // A switch pattern or a comparison: both sides have to stay the
          // value the server sent, or the match stops happening in Punjabi.
          /\bcase\s+$/.test(before) ||
          /[=!]=\s*$/.test(before) ||
          /\.(?:contains|hasPrefix|hasSuffix)\($/.test(before) ||
          // `payload["team_name"]` is a lookup into JSON the server sent.
          // Wrapping it made the app search for a Punjabi key and find
          // nothing — a bug a green build and a wrapped-count both missed.
          /\[\s*$/.test(before) ||
          /(systemImage|systemName|of|with|separator|format|forKey):\s*$/.test(before);
        rebuilt += before + (skip ? `"${body}"` : `tr("${body}")`);
        if (!skip) { wrapped += 1; touched = true; }
        at = close + 1;
      }
      out[j] = rebuilt;
    }
  }
  if (touched) {
    changed += 1;
    if (!dry) writeFileSync(file, out.join("\n"));
  }
}
console.log(`${wrapped} literal(s) in ${changed} display accessor file(s) ${dry ? "would be" : ""} wrapped.`);
