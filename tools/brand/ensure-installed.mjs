#!/usr/bin/env node
/**
 * Make sure the brand tool can run, then run it.
 *
 * A fresh clone has no `tools/brand/node_modules`, so the first `npm run dev`
 * in web/ would fail with a module-not-found pointing at a file the developer
 * has never opened. Installing one dependency on their behalf is friendlier
 * than a stack trace, and it happens once.
 *
 * Arguments are passed straight through to the CLI.
 */

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));

if (!existsSync(join(here, "node_modules", "yaml"))) {
  console.log("brand: installing the tool's dependencies (once)");
  const install = spawnSync("npm", ["ci", "--omit=dev", "--silent"], {
    cwd: here,
    stdio: "inherit",
  });
  if (install.status !== 0) {
    console.error(
      "\nCould not install the brand tool. Run it yourself:\n" +
        "  npm ci --omit=dev --prefix tools/brand\n",
    );
    process.exit(1);
  }
}

const run = spawnSync("node", [join(here, "index.mjs"), ...process.argv.slice(2)], {
  stdio: "inherit",
});
process.exit(run.status ?? 1);
