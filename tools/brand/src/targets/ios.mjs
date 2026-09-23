import { join } from "node:path";

/**
 * What the iOS build needs.
 *
 * An xcconfig, which Xcode reads for the bundle id and display name, and a
 * Swift file for the palette and the copy. Both are generated per brand and
 * selected by the scheme, so a brand is a configuration rather than a branch.
 */
export function iosFiles(brand, repoRoot) {
  const dir = join(repoRoot, "ios", "Fishers", "Brand", "Generated");
  return [
    { path: join(dir, `${brand.id}.xcconfig`), contents: xcconfig(brand) },
    { path: join(dir, "Brand.generated.swift"), contents: swift(brand) },
  ];
}

function xcconfig(brand) {
  return `// Generated from brands/${brand.id}.yaml. Do not edit.
//
// Selected by the scheme. The bundle id is what makes this a separate listing
// on the App Store rather than an update to somebody else's app.

PRODUCT_BUNDLE_IDENTIFIER = ${brand.mobile.bundleId}
PRODUCT_NAME = ${brand.mobile.displayName}
FISHERS_BRAND_ID = ${brand.id}
FISHERS_API_HOST = ${brand.rings.prod}
`;
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
        static let sourcePrimary = Color(hex: ${JSON.stringify(source.primary)})
        static let sourcePrimaryPale = Color(hex: ${JSON.stringify(source.primaryPale)})
        static let sourceSurface = Color(hex: ${JSON.stringify(source.surface)})
        static let sourceAccent = Color(hex: ${JSON.stringify(source.accent)})

        static let primary = Color(hex: ${JSON.stringify(ramp.primary600)})
        static let primaryHover = Color(hex: ${JSON.stringify(ramp.primary700)})
        static let primaryDeep = Color(hex: ${JSON.stringify(ramp.primary900)})
        static let accent = Color(hex: ${JSON.stringify(ramp.accent700)})

        static let ink = Color(hex: ${JSON.stringify(ramp.ink900)})
        static let inkMuted = Color(hex: ${JSON.stringify(ramp.ink500)})
    }
}
`;
}
