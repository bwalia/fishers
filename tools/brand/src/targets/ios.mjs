import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * What the iOS build needs.
 *
 * An xcconfig, which Xcode reads for the bundle id and display name, and a
 * Swift file for the palette and the copy. Both are generated per brand and
 * selected by the scheme, so a brand is a configuration rather than a branch.
 */
export function iosFiles(brand, repoRoot, outDir) {
  const dir = outDir ?? join(repoRoot, "ios", "Fishers", "Brand", "Generated");
  // A fixed name, not the brand's: project.yml names this file, and a path
  // that moved with the brand would mean editing the project to change brand.
  // One brand is active at a time, switched by running the generator — the
  // same shape the web has, and for the same reason.
  // The asset catalogue is not next to the generated Swift, because Xcode
  // compiles a catalogue from where the project says it is. AccentColor is the
  // system tint: SwiftUI reaches for it without being asked, so a brand that
  // left it behind would be its own colour everywhere it named one and Fishers'
  // sage everywhere it did not.
  const assets = outDir
    ? join(outDir, "Assets.xcassets")
    : join(repoRoot, "ios", "Fishers", "Resources", "Assets.xcassets");
  return [
    { path: join(dir, "brand.xcconfig"), contents: xcconfig(brand) },
    { path: join(dir, "Brand.generated.swift"), contents: swift(brand) },
    {
      path: join(assets, "AccentColor.colorset", "Contents.json"),
      contents: accentColorSet(brand),
    },
    ...artwork(brand, repoRoot, assets),
  ];
}

/**
 * The home-screen icon and the two images the brand header draws.
 *
 * Rendered from the brand's own `icon.svg` and `mark.svg` by
 * `npm --prefix tools/brand run icons`, which commits the PNGs. The catalogue
 * used to hold Fishers' artwork under Fishers' names, so every other brand
 * installed with Fishers' icon on the home screen and Fishers' ball in its
 * header — with the right name underneath, which made it look deliberate.
 */
const ARTWORK = [
  ["icon-1024.png", "AppIcon.appiconset", "icon.png"],
  ["icon-512.png", "BrandLogo.imageset", "logo.png"],
  ["mark-512.png", "BrandMark.imageset", "mark.png"],
];

function artwork(brand, repoRoot, assets) {
  const from = join(repoRoot, "brands", brand.id);
  const missing = ARTWORK.map(([n]) => n).filter((n) => !existsSync(join(from, n)));
  if (missing.length) {
    throw new Error(
      `${brand.name} has no ${missing.join(", ")}. Run \`npm --prefix tools/brand run icons\` ` +
        `to render them from brands/${brand.id}/icon.svg and mark.svg — a build ` +
        `cannot fall back to another brand's mark.`,
    );
  }
  return ARTWORK.flatMap(([source, set, name]) => [
    { path: join(assets, set, name), contents: readFileSync(join(from, source)) },
    { path: join(assets, set, "Contents.json"), contents: imageSet(name, set) },
  ]);
}

/** A single-scale set: one PNG, sized for the largest thing that draws it. */
function imageSet(name, set) {
  const icon = set.startsWith("AppIcon");
  return JSON.stringify(
    {
      images: [
        icon
          ? { filename: name, idiom: "universal", platform: "ios", size: "1024x1024" }
          : { filename: name, idiom: "universal", scale: "1x" },
        ...(icon ? [] : [{ idiom: "universal", scale: "2x" }, { idiom: "universal", scale: "3x" }]),
      ],
      info: { author: "tools/brand", version: 1 },
    },
    null,
    2,
  ) + "\n";
}

/** `#667964` as the 0–1 sRGB components an asset catalogue wants. */
function components(value) {
  const h = String(value).replace(/^#/, "");
  const full = h.length === 3 ? [...h].map((c) => c + c).join("") : h;
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16) / 255);
  return { r, g, b };
}

function colourEntry(value, dark) {
  const { r, g, b } = components(value);
  const f = (n) => n.toFixed(3);
  return {
    ...(dark ? { appearances: [{ appearance: "luminosity", value: "dark" }] } : {}),
    color: {
      "color-space": "srgb",
      components: { alpha: "1.000", red: f(r), green: f(g), blue: f(b) },
    },
    idiom: "universal",
  };
}

/**
 * The system tint, light and dark.
 *
 * Light takes the ramp's primary600 because the tint lands on white and has to
 * carry text; dark takes the pale source colour, because a tint that works on
 * cream disappears on near-black.
 */
function accentColorSet(brand) {
  return JSON.stringify(
    {
      colors: [
        colourEntry(brand.ramp.primary600, false),
        colourEntry(brand.source.primaryPale, true),
      ],
      info: { author: "tools/brand", version: 1 },
    },
    null,
    2,
  ) + "\n";
}

function xcconfig(brand) {
  return `// Generated from brands/${brand.id}.yaml. Do not edit.
//
// Read by the app target through project.yml's configFiles. The bundle id is
// what makes this a separate listing on the App Store rather than an update to
// somebody else's app, so regenerating for another brand and rebuilding is the
// whole of switching.

PRODUCT_BUNDLE_IDENTIFIER = ${brand.mobile.bundleId}
PRODUCT_NAME = ${brand.mobile.displayName}
FISHERS_BRAND_ID = ${brand.id}
FISHERS_API_HOST = ${brand.rings.prod}
`;
}

/** `#8fa28a` as `0x8FA28A` — what `Color(hex:)` takes. */
function swiftHex(value) {
  return `0x${String(value).replace(/^#/, "").toUpperCase()}`;
}

function swift(brand) {
  const { ramp, source, dark } = brand;
  const hex = (v) => `Color(hex: ${swiftHex(v)})`;
  return `// Generated from brands/${brand.id}.yaml. Do not edit.

import SwiftUI

/// Who this build is, and what it looks like.
///
/// Every place the app names itself or picks a colour reads from here, so one
/// file is the difference between Fishers and GullyCricket. A literal is a
/// place the next brand is wrong — and wrong quietly, because a hardcoded
/// palette still compiles and still renders.
///
/// The same numbers the web's \`brand.generated.css\` gets, from the same brand
/// file, so a club's phone and its laptop are the same product.
enum Brand {
    static let id = ${JSON.stringify(brand.id)}
    static let name = ${JSON.stringify(brand.name)}
    static let legalName = ${JSON.stringify(brand.legalName)}
    static let tagline = ${JSON.stringify(brand.tagline)}
    static let supportEmail = ${JSON.stringify(brand.support.email)}
    static let domain = ${JSON.stringify(brand.domain)}

    /// The source colours are what the brand looks like. All four are light by
    /// design — none of them carries white text — which is why the ramp exists.
    enum Source {
        static let primary = ${hex(source.primary)}
        static let primaryPale = ${hex(source.primaryPale)}
        static let surface = ${hex(source.surface)}
        static let accent = ${hex(source.accent)}
    }

    /// Each source colour darkened until it carries text. Every pair is checked
    /// against WCAG AA by \`npm run brand:check\`, which fails the build rather
    /// than shipping a button nobody can read.
    enum Ramp {
        static let primary400 = ${hex(ramp.primary400)}
        static let primary500 = ${hex(ramp.primary500)}
        static let primary600 = ${hex(ramp.primary600)}
        static let primary700 = ${hex(ramp.primary700)}
        static let primary800 = ${hex(ramp.primary800)}
        static let primary900 = ${hex(ramp.primary900)}

        static let accent400 = ${hex(ramp.accent400)}
        static let accent500 = ${hex(ramp.accent500)}
        static let accent600 = ${hex(ramp.accent600)}
        static let accent700 = ${hex(ramp.accent700)}

        static let ink900 = ${hex(ramp.ink900)}
        static let ink700 = ${hex(ramp.ink700)}
        static let ink500 = ${hex(ramp.ink500)}
    }

    /// Dark is not a grey inversion: these are mixed from the brand's own hue,
    /// so the two appearances are the same room at different times of day.
    enum Dark {
        static let bg = ${hex(dark.bg)}
        static let surface = ${hex(dark.surface)}
        static let surface2 = ${hex(dark.surface2)}
        static let surface3 = ${hex(dark.surface3)}
        static let fg = ${hex(dark.fg)}
        static let fgMuted = ${hex(dark.fgMuted)}
        static let fgSubtle = ${hex(dark.fgSubtle)}
        static let border = ${hex(dark.border)}
        static let borderStrong = ${hex(dark.borderStrong)}
        static let onPrimary = ${hex(dark.onPrimary)}
        static let raised = ${hex(dark.raised)}
        static let accentPale = ${hex(dark.accentPale)}
    }
}
`;
}
