/**
 * What a brand file has to say, and what happens when it does not.
 *
 * Validation is loud and specific on purpose. A brand is added by somebody who
 * has not read this code, and "Cannot read properties of undefined" is not a
 * thing they can act on — "brands/x.yaml: missing rings.prod" is.
 */

const REQUIRED_STRINGS = [
  "id",
  "name",
  "legalName",
  "tagline",
  "description",
  "domain",
];

const RINGS = ["int", "test", "acc", "prod"];

const SOURCE_COLOURS = ["primary", "primaryPale", "surface", "accent"];

const RAMP_COLOURS = [
  "primary400", "primary500", "primary600", "primary700", "primary800", "primary900",
  "accent400", "accent500", "accent600", "accent700",
  "ink900", "ink700", "ink500",
];

const DARK_COLOURS = [
  "bg", "surface", "surface2", "surface3",
  "fg", "fgMuted", "fgSubtle",
  "border", "borderStrong", "onPrimary", "raised", "accentPale",
];

const HEX = /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/;

export class BrandError extends Error {}

/**
 * Check a parsed brand file, and hand back the same object.
 *
 * Every problem is collected before anything is thrown, so adding a brand is
 * one round of corrections rather than a dozen.
 */
export function validate(brand, source) {
  const problems = [];
  const where = (path) => `${source}: ${path}`;

  for (const key of REQUIRED_STRINGS) {
    if (typeof brand?.[key] !== "string" || !brand[key].trim()) {
      problems.push(`${where(key)} is missing`);
    }
  }

  if (brand?.id && !/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(brand.id)) {
    problems.push(
      `${where("id")} must be lowercase letters and digits, single-hyphen separated ` +
        `(like "gully-cricket") — it becomes a Kubernetes namespace, an Android ` +
        `flavour, a directory name and an XML comment, and a doubled hyphen is ` +
        `illegal in the last of those`,
    );
  }

  for (const ring of RINGS) {
    if (typeof brand?.rings?.[ring] !== "string") {
      problems.push(`${where(`rings.${ring}`)} is missing`);
    }
  }

  // A typo here is silent in the worst way: the ring deploys, the ingress
  // names a gateway Service that does not exist, and Traefik drops the paths
  // that name it and answers 404 instead of erroring.
  if (!Array.isArray(brand?.gateway)) {
    problems.push(
      `${where("gateway")} is missing — list the rings with a Kong in front of ` +
        `the API, or \`gateway: []\` for a brand that has none yet`,
    );
  } else {
    for (const ring of brand.gateway) {
      if (!RINGS.includes(ring)) {
        problems.push(
          `${where("gateway")} has "${ring}", which is not a ring. ` +
            `Rings are: ${RINGS.join(", ")}`,
        );
      }
    }
  }

  for (const key of ["email", "sslEmail"]) {
    if (typeof brand?.support?.[key] !== "string") {
      problems.push(`${where(`support.${key}`)} is missing`);
    }
  }

  for (const key of SOURCE_COLOURS) {
    problems.push(...colourProblem(brand?.source?.[key], where(`source.${key}`)));
  }
  for (const key of RAMP_COLOURS) {
    problems.push(...colourProblem(brand?.ramp?.[key], where(`ramp.${key}`)));
  }
  for (const key of DARK_COLOURS) {
    problems.push(...colourProblem(brand?.dark?.[key], where(`dark.${key}`)));
  }

  for (const key of ["bundleId", "displayName"]) {
    if (typeof brand?.mobile?.[key] !== "string") {
      problems.push(`${where(`mobile.${key}`)} is missing`);
    }
  }
  if (brand?.mobile?.bundleId && !/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/.test(brand.mobile.bundleId)) {
    problems.push(
      `${where("mobile.bundleId")} must be a reverse-DNS id such as app.gullycricket — ` +
        `it is the Android applicationId and the iOS bundle identifier`,
    );
  }

  if (problems.length) {
    throw new BrandError(
      `That brand file cannot be used yet:\n  ${problems.join("\n  ")}`,
    );
  }
  return brand;
}

function colourProblem(value, path) {
  if (typeof value !== "string") return [`${path} is missing`];
  if (!HEX.test(value)) return [`${path} is "${value}", which is not a hex colour`];
  return [];
}

export { RINGS, SOURCE_COLOURS, RAMP_COLOURS, DARK_COLOURS };
