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

/// Must match `SportType` in backend/domain/src/enums.rs.
///
/// A fourth copy of that list — the web's `SPORTS` and the iOS `Sport` enum
/// are the others — and the one it matters most to get right, because a typo
/// here does not fail anywhere visible: the brand generates, the ring
/// deploys, and the sport is simply missing from every picker.
const SPORTS = ["cricket", "football", "badminton", "paddle", "pickleball", "tennis", "other"];

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

  // Optional. Left out means every sport, which is what every brand did
  // before this existed; present means exactly these and nothing else. An
  // empty list is rejected rather than read as "none": a brand that offers no
  // sports is an app with nothing in it, and is far more likely to be a
  // half-finished edit than an intention.
  if (brand?.sports !== undefined) {
    if (!Array.isArray(brand.sports) || brand.sports.length === 0) {
      problems.push(
        `${where("sports")} must be a non-empty list, or left out entirely to ` +
          `offer every sport`,
      );
    } else {
      for (const sport of brand.sports) {
        if (!SPORTS.includes(sport)) {
          problems.push(
            `${where("sports")} has "${sport}", which the API's SportType does ` +
              `not accept. Sports are: ${SPORTS.join(", ")}`,
          );
        }
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

  for (const key of ["bundleId", "displayName", "googleIosClientId"]) {
    if (typeof brand?.mobile?.[key] !== "string") {
      problems.push(`${where(`mobile.${key}`)} is missing`);
    }
  }
  // Required, not optional, and this is the reason: the reversed form of this
  // id is a URL scheme in Info.plist, and GIDSignIn aborts Continue with
  // Google when the scheme does not match the client id /auth/google returns.
  // Left to a default, a new brand inherits whichever brand was hardcoded and
  // ships a sign-in button that always errors — green build, broken app.
  const googleId = brand?.mobile?.googleIosClientId;
  if (typeof googleId === "string" && !/^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$/.test(googleId)) {
    problems.push(
      `${where("mobile.googleIosClientId")} must be an iOS OAuth client id ` +
        `such as 1234-abcd.apps.googleusercontent.com, from this brand's own ` +
        `Google Cloud project (Credentials -> type "iOS")`,
    );
  }
  if (brand?.mobile?.bundleId && !/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/.test(brand.mobile.bundleId)) {
    problems.push(
      `${where("mobile.bundleId")} must be a reverse-DNS id such as app.gullycricket — ` +
        `it is the Android applicationId and the iOS bundle identifier`,
    );
  }

  // Optional: a brand whose Play signing key is not known yet serves no
  // assetlinks.json at all. One that lists keys must list them as Play
  // Console prints them — a fingerprint in the wrong form does not fail
  // anywhere visible, it just leaves every invite link opening the browser.
  const certs = brand?.mobile?.androidCertSha256;
  if (certs !== undefined) {
    const fingerprint = /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/;
    if (!Array.isArray(certs) || certs.length === 0) {
      problems.push(
        `${where("mobile.androidCertSha256")} must be a list of SHA-256 fingerprints, ` +
          `or left out for a brand whose signing key is not known yet`,
      );
    } else {
      for (const cert of certs) {
        if (typeof cert !== "string" || !fingerprint.test(cert)) {
          problems.push(
            `${where("mobile.androidCertSha256")} has "${cert}", which is not a SHA-256 ` +
              `fingerprint as Play Console prints it (32 upper-case hex pairs joined by colons)`,
          );
        }
      }
    }
  }

  // Optional: a brand with no live listing has no `stores`, and the website
  // draws no badge. One that has one must give a real App Store URL — the
  // badge links straight to it.
  const appStore = brand?.stores?.appStore;
  if (appStore !== undefined && !(typeof appStore === "string" && /^https:\/\/apps\.apple\.com\//.test(appStore))) {
    problems.push(`${where("stores.appStore")} must be an https://apps.apple.com/ link`);
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
