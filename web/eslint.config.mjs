import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { FlatCompat } from "@eslint/eslintrc";

const compat = new FlatCompat({ baseDirectory: dirname(fileURLToPath(import.meta.url)) });

/// Next's own rules, as flat config.
///
/// `next lint` used to be the script here, but nothing was installed behind
/// it: running it dropped into an interactive setup prompt and exited without
/// linting anything, which is a check that reads as passing because it never
/// ran. Next 15 deprecated that command anyway, so this is the ESLint CLI with
/// the same rule sets it would have configured.
const config = [
  ...compat.extends("next/core-web-vitals", "next/typescript"),
  {
    // Build output and dependencies are not ours to lint.
    ignores: ["**/.next/**", "**/node_modules/**", "**/out/**", "next-env.d.ts"],
  },
  {
    // next.config.js is a CommonJS file Node loads directly, which is how
    // Next ships it. The rule is about ESM source, not a Node config.
    files: ["*.config.js"],
    rules: { "@typescript-eslint/no-require-imports": "off" },
  },
];

export default config;
