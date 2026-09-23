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
  return [
    { path: join(dir, "brand.xcconfig"), contents: xcconfig(brand) },
    { path: join(dir, "Brand.generated.swift"), contents: swift(brand) },
  ];
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
  const { ramp, source } = brand;
  return `// Generated from brands/${brand.id}.yaml. Do not edit.

import SwiftUI

/// Who this build is.
///
/// Every place the app names itself reads from here, so one file is the
/// difference between Fishers and GullyCricket. A literal is a place the next
/// brand is wrong.
enum Brand {
    static let id = ${JSON.stringify(brand.id)}
    static let name = ${JSON.stringify(brand.name)}
    static let legalName = ${JSON.stringify(brand.legalName)}
    static let tagline = ${JSON.stringify(brand.tagline)}
    static let supportEmail = ${JSON.stringify(brand.support.email)}
    static let domain = ${JSON.stringify(brand.domain)}

    /// The source colours are what the brand looks like; the ramp is what
    /// carries text, darkened until it does.
    enum Colours {
        static let sourcePrimary = Color(hex: ${swiftHex(source.primary)})
        static let sourcePrimaryPale = Color(hex: ${swiftHex(source.primaryPale)})
        static let sourceSurface = Color(hex: ${swiftHex(source.surface)})
        static let sourceAccent = Color(hex: ${swiftHex(source.accent)})

        static let primary = Color(hex: ${swiftHex(ramp.primary600)})
        static let primaryHover = Color(hex: ${swiftHex(ramp.primary700)})
        static let primaryDeep = Color(hex: ${swiftHex(ramp.primary900)})
        static let accent = Color(hex: ${swiftHex(ramp.accent700)})

        static let ink = Color(hex: ${swiftHex(ramp.ink900)})
        static let inkMuted = Color(hex: ${swiftHex(ramp.ink500)})
    }
}
`;
}
