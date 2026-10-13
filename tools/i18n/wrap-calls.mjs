#!/usr/bin/env node
/**
 * Wrap every literal inside a rendering call, not just the first argument.
 *
 *   node tools/i18n/wrap-calls.mjs [--dry]
 *
 * `Text(mode == .login ? "Welcome back" : "Join your club")` is the shape that
 * made "0 literals left" wrong twice: the first argument is an expression, so
 * anything anchored to `Call("` walks straight past it. This matches the call,
 * counts parentheses to find where it ends, and wraps each literal inside.
 *
 * Still only rendering calls, so a wrap cannot change a stored value, and
 * `systemImage:`/`systemName:` arguments are left alone because an SF Symbol
 * name is not words.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const appDir = join(repoRoot, "ios", "Fishers");
const dry = process.argv.includes("--dry");

const CALLS = [
  "Text", "Label", "Button", "Section", "navigationTitle", "navigationBarTitle",
  "Toggle", "TextField", "SecureField", "TextEditor", "Picker", "Stepper", "Link",
  "alert", "confirmationDialog", "SelectableChip", "Tile", "LabeledContent",
];
const opener = new RegExp(String.raw`\b(${CALLS.join("|")})\(`, "g");

let wrapped = 0, changed = 0;
const files = execSync(`find "${appDir}" -name '*.swift'`, { encoding: "utf8" })
  .split("\n").filter(Boolean)
  .filter((f) => !f.includes("/Generated/") && !f.endsWith("Localization.swift"));

for (const file of files) {
  const before = readFileSync(file, "utf8");
  let text = before;
  let out = "";
  let cursor = 0;
  opener.lastIndex = 0;

  for (let m; (m = opener.exec(text)); ) {
    const openAt = m.index + m[0].length - 1;
    // Where this call closes.
    let depth = 0, closeAt = -1, inString = false;
    for (let i = openAt; i < text.length; i++) {
      const ch = text[i];
      if (ch === '"' && text[i - 1] !== "\\") inString = !inString;
      if (inString) continue;
      if (ch === "(") depth += 1;
      else if (ch === ")") { depth -= 1; if (depth === 0) { closeAt = i; break; } }
      if (i - openAt > 2000) break;
    }
    if (closeAt < 0) continue;

    const span = text.slice(openAt, closeAt + 1);
    // One line at a time inside the call, so the two refusals still apply.
    const rewritten = span.split("\n").map((line) => {
      if (line.includes("\\(")) return line;                 // interpolation
      if (/\bcase\s+\w+\s*=\s*"/.test(line)) return line;    // a raw value
      if (/^\s*(\/\/|\*)/.test(line)) return line;           // a comment
      return line.replace(/(\w+:\s*)?"([^"\\]{2,})"/g, (whole, named, body) => {
        if (named && /^(systemImage|systemName|key|id|value|tag):\s*$/.test(named)) return whole;
        if (!/[A-Za-z]{2,}/.test(body)) return whole;
        if (/^[a-z0-9.]+$/.test(body) && body.includes(".")) return whole;   // SF Symbol
        wrapped += 1;
        return `${named ?? ""}tr(${JSON.stringify(body)})`;
      });
    }).join("\n");

    out += text.slice(cursor, openAt) + rewritten;
    cursor = closeAt + 1;
    opener.lastIndex = closeAt + 1;
  }
  out += text.slice(cursor);

  if (out !== before) {
    changed += 1;
    if (!dry) writeFileSync(file, out);
  }
}
console.log(`${wrapped} literal(s) inside ${changed} file(s)' rendering calls ${dry ? "would be" : ""} wrapped.`);
