import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { parse } from "yaml";
import { BrandError, validate } from "./schema.mjs";
import { AA_NORMAL, contrast } from "./contrast.mjs";

/** Where the brand files live, relative to the repo root. */
export const BRANDS_DIR = "brands";

export function brandsRoot(repoRoot) {
  return join(repoRoot, BRANDS_DIR);
}

/** Every brand the repo knows about, by id. */
export function listBrands(repoRoot) {
  return readdirSync(brandsRoot(repoRoot))
    .filter((f) => f.endsWith(".yaml"))
    .map((f) => f.replace(/\.yaml$/, ""))
    .sort();
}

/**
 * Read and check one brand.
 *
 * Throws `BrandError` with something a person can act on — a missing brand
 * lists the ones that do exist, because the commonest cause is a typo.
 */
export function loadBrand(repoRoot, id) {
  const file = join(brandsRoot(repoRoot), `${id}.yaml`);
  if (!existsSync(file)) {
    const known = listBrands(repoRoot);
    throw new BrandError(
      `No brand called "${id}". This repo has: ${known.join(", ")}`,
    );
  }

  let parsed;
  try {
    parsed = parse(readFileSync(file, "utf8"));
  } catch (cause) {
    throw new BrandError(`${BRANDS_DIR}/${id}.yaml is not valid YAML: ${cause.message}`);
  }

  validate(parsed, `${BRANDS_DIR}/${id}.yaml`);

  if (parsed.id !== id) {
    throw new BrandError(
      `${BRANDS_DIR}/${id}.yaml says its id is "${parsed.id}". The file name is the id.`,
    );
  }
  return parsed;
}

/**
 * The colour pairs a screen actually puts together.
 *
 * Not every combination — only the ones the stylesheet uses, because a ratio
 * nobody can see is not worth failing a build over, and a list padded with
 * those is a list people learn to ignore.
 */
export function contrastPairs(brand) {
  const { ramp, source } = brand;
  return [
    { what: "white on a primary button", fg: "#ffffff", bg: ramp.primary600 },
    { what: "white on a primary button, hovered", fg: "#ffffff", bg: ramp.primary700 },
    { what: "white on an accent badge", fg: "#ffffff", bg: ramp.accent700 },
    { what: "body text on the page", fg: ramp.ink900, bg: source.surface },
    { what: "muted text on the page", fg: ramp.ink500, bg: source.surface },
    { what: "body text on a card", fg: ramp.ink900, bg: "#ffffff" },
    { what: "muted text on a card", fg: ramp.ink500, bg: "#ffffff" },
    { what: "body text on a raised card", fg: ramp.ink900, bg: source.primaryPale },
    { what: "a heading on the page", fg: ramp.primary900, bg: source.surface },
  ];
}

/**
 * Whether every pair a screen uses is readable.
 *
 * The palette is four source colours and a ramp darkened from them until the
 * ramp carries text. That is not a style choice: the original sage is 2.7:1 on
 * white, which fails WCAG AA, so it was darkened until it passed. A brand that
 * picks colours without redoing that work ships a screen nobody can read, and
 * nothing else in the build would notice.
 */
export function checkContrast(brand) {
  const results = contrastPairs(brand).map((pair) => ({
    ...pair,
    ratio: contrast(pair.fg, pair.bg),
  }));
  return {
    results,
    failed: results.filter((r) => r.ratio < AA_NORMAL),
    threshold: AA_NORMAL,
  };
}

export { BrandError };
