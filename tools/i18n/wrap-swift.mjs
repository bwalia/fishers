#!/usr/bin/env node
/**
 * Wrap what is drawn, leave what is stored.
 *
 *   node tools/i18n/wrap-swift.mjs [--dry]
 *
 * convert-swift.mjs replaces a literal with a key. That is right when the
 * literal is only ever drawn, and wrong when it is also a value — a position
 * saved on a profile, an enum's backing string that goes to the API. This
 * wraps instead: `tr("Right side")` draws the Punjabi and `position == option`
 * still compares the English.
 *
 * Only rendering positions, so a wrap can never change what is sent anywhere:
 * the text of a Text/Label/Section/navigationTitle, and `.rawValue` where it is
 * being drawn. `tr` returns its argument unchanged when the dictionary has no
 * entry, so wrapping is safe before the words are translated and starts working
 * the moment they are.
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

const files = execSync(`find "${appDir}" -name '*.swift'`, { encoding: "utf8" })
  .split("\n").filter(Boolean)
  .filter((f) => !f.includes("/Generated/") && !f.endsWith("Localization.swift"));

/** Drawn, never stored. The first argument of each of these is read by a person. */
const RENDER = [
  "Text", "Section", "navigationTitle", "navigationBarTitle",
  "Label", "Button", "Toggle", "TextField", "SecureField", "TextEditor",
  "alert", "confirmationDialog", "Picker", "Stepper", "Link",
  "SelectableChip", "Tile",
];

/**
 * Named arguments that are captions rather than values.
 *
 * Deliberately short: `title:` is on this list and `id:`, `key:`, `name:` and
 * `value:` are not, because those are the ones that end up saved or sent. A
 * wrap is reversible and `tr` is identity for anything the dictionary lacks,
 * but a wrapped *value* would be a data bug, so the list only grows with a
 * reason.
 */
const CAPTIONS = ["label", "caption", "title", "placeholder", "footnote", "message", "prompt", "subtitle", "hint", "header", "detail"];

let wrapped = 0, changed = 0;
for (const file of files) {
  const before = readFileSync(file, "utf8");
  // Line by line, so a line with interpolation or a raw value can be skipped
  // whole rather than half-matched.
  const keep = new Map();
  let after = before.split("\n").map((line, i) => {
    if (interpolated(line) || rawValue(line) || /^\s*(\/\/|\*)/.test(line)) {
      const token = `\u0000KEEP${i}\u0000`;
      keep.set(token, line);
      return token;
    }
    return line;
  }).join("\n");

  for (const call of RENDER) {
    // A plain literal: Text("Upcoming") -> Text(tr("Upcoming"))
    after = after.replace(
      new RegExp(String.raw`\b${call}\(\s*"([^"\\]{2,})"`, "g"),
      (whole, text) => {
        if (!/[A-Za-z]{2,}/.test(text)) return whole;
        wrapped += 1;
        return `${call}(tr(${JSON.stringify(text)})`;
      },
    );
    // A raw value being drawn: Text($0.rawValue) -> Text(tr($0.rawValue))
    after = after.replace(
      new RegExp(String.raw`\b${call}\(\s*(\$?\w[\w.]*\.rawValue)\s*\)`, "g"),
      (_whole, expr) => {
        wrapped += 1;
        return `${call}(tr(${expr}))`;
      },
    );
  }

  // Named captions: `label: "Clubs"` -> `label: tr("Clubs")`
  after = after.replace(
    new RegExp(String.raw`\b(${CAPTIONS.join("|")}):\s*"([^"\\]{2,})"`, "g"),
    (whole, name, text) => {
      if (!/[A-Za-z]{2,}/.test(text)) return whole;
      wrapped += 1;
      return `${name}: tr(${JSON.stringify(text)})`;
    },
  );

  for (const [token, line] of keep) after = after.replace(token, line);

  if (after !== before) {
    changed += 1;
    if (!dry) writeFileSync(file, after);
  }
}
console.log(`${wrapped} rendering site(s) in ${changed} file(s) ${dry ? "would be" : ""} wrapped in tr().`);
