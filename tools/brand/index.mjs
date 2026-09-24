#!/usr/bin/env node
/**
 * brand — turn a brand file into what each frontend needs.
 *
 *   brand check [<id>]            every pair readable? writes nothing
 *   brand generate <id> [targets] write the generated files
 *   brand list                    which brands this repo has
 *   brand helm <id> <ring>        print the brand's Helm overlay
 *   brand host <id> <ring>        print where that ring answers
 *   brand namespace <id> <ring>   print the namespace it lives in
 *   brand hosts <id> <ring>       every hostname that ring answers on
 *   brand dns-hosts <id> <ring>   the ones that get a CNAME (not the apex)
 *   brand zone <id>               the Cloudflare zone
 *
 * Targets default to every platform: --web --android --ios.
 *
 * Nothing it writes is committed. Generated code that lives in the repo drifts
 * from the source it came from, which is the failure this exists to avoid.
 */

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { BrandError, checkContrast, listBrands, loadBrand } from "./src/brand.mjs";
import { webAssets, webFiles } from "./src/targets/web.mjs";
import { androidFiles } from "./src/targets/android.mjs";
import { iosFiles } from "./src/targets/ios.mjs";
import {
  dnsHostsFor,
  edgeHostsFor,
  helmValues,
  hostFor,
  namespaceFor,
  zoneFor,
} from "./src/helm.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..", "..");

const TARGETS = {
  web: (brand, root, out) => [...webFiles(brand, root, out), ...webAssets(brand, root, out)],
  android: androidFiles,
  ios: iosFiles,
};

function reportContrast(brand) {
  const { results, failed, threshold } = checkContrast(brand);
  for (const r of results) {
    const mark = r.ratio >= threshold ? "  ok  " : "  FAIL";
    console.log(
      `${mark} ${r.ratio.toFixed(2).padStart(6)}:1  ${r.what.padEnd(34)} ${r.fg} on ${r.bg}`,
    );
  }
  if (failed.length) {
    console.error(
      `\n${brand.name}: ${failed.length} pair${failed.length === 1 ? "" : "s"} under ` +
        `${threshold}:1.\n\n` +
        `Darken the ramp in brands/${brand.id}.yaml until they pass. The source colours\n` +
        `can stay as they are — they are surfaces and marks, and read best there anyway.\n` +
        `This is the same work the original palette did: sage is 2.7:1 on white, so it\n` +
        `was darkened to #667964, which is 4.68:1.`,
    );
  }
  return failed.length === 0;
}

function write(files) {
  for (const { path, contents } of files) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, contents);
    const size = Buffer.isBuffer(contents) ? ` (${contents.length} bytes)` : "";
    console.log(`  wrote ${path.replace(`${repoRoot}/`, "")}${size}`);
  }
}

function main(argv) {
  const [command = "check", ...rest] = argv;

  if (command === "list") {
    for (const id of listBrands(repoRoot)) console.log(id);
    return 0;
  }

  if (command === "check") {
    const ids = rest.length ? rest : listBrands(repoRoot);
    let ok = true;
    for (const id of ids) {
      const brand = loadBrand(repoRoot, id);
      console.log(`\n${brand.name} (${id})`);
      ok = reportContrast(brand) && ok;
    }
    if (ok) console.log("\nEvery brand is readable.");
    return ok ? 0 : 1;
  }

  if (command === "generate") {
    const [id, ...flags] = rest;
    if (!id) throw new BrandError("Which brand? Try: brand generate fishers");
    const brand = loadBrand(repoRoot, id);

    // Generating an unreadable brand is worse than refusing to: it ships.
    console.log(`${brand.name} (${id})`);
    if (!reportContrast(brand)) return 1;

    const outFlag = flags.find((f) => f.startsWith("--out="));
    const outDir = outFlag ? outFlag.slice("--out=".length) : undefined;
    const chosen = flags
      .filter((f) => f.startsWith("--") && !f.startsWith("--out="))
      .map((f) => f.slice(2));
    const targets = chosen.length ? chosen : Object.keys(TARGETS);
    for (const target of targets) {
      const build = TARGETS[target];
      if (!build) {
        throw new BrandError(
          `No target called "${target}". There is: ${Object.keys(TARGETS).join(", ")}`,
        );
      }
      write(build(brand, repoRoot, outDir));
    }
    return 0;
  }

  // Three one-liners the deploy workflow asks for. Kept here rather than
  // duplicated as shell, because the brand file is the one place that knows.
  const LOOKUPS = {
    helm: (brand, ring) => helmValues(brand, ring),
    host: (brand, ring) => `${hostFor(brand, ring)}\n`,
    namespace: (brand, ring) => `${namespaceFor(brand, ring)}\n`,
    hosts: (brand, ring) => `${edgeHostsFor(brand, ring).join(" ")}\n`,
    "dns-hosts": (brand, ring) => `${dnsHostsFor(brand, ring).join(" ")}\n`,
  };

  // The zone belongs to the brand, not to a ring.
  if (command === "zone") {
    const [id] = rest;
    if (!id) throw new BrandError("Try: brand zone gullycricket");
    process.stdout.write(`${zoneFor(loadBrand(repoRoot, id))}\n`);
    return 0;
  }

  if (LOOKUPS[command]) {
    const [id, ring] = rest;
    if (!id || !ring) {
      throw new BrandError(`Try: brand ${command} gullycricket int`);
    }
    const brand = loadBrand(repoRoot, id);
    try {
      process.stdout.write(LOOKUPS[command](brand, ring));
    } catch (e) {
      throw new BrandError(e.message);
    }
    return 0;
  }

  throw new BrandError(
    `No command called "${command}". There is: check, generate, list, helm, host, namespace, hosts, dns-hosts, zone`,
  );
}

try {
  process.exit(main(process.argv.slice(2)));
} catch (error) {
  if (error instanceof BrandError) {
    console.error(`\n${error.message}\n`);
    process.exit(1);
  }
  throw error;
}
