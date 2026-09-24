import { join } from "node:path";

/**
 * What the Android build needs.
 *
 * Android has product flavours for exactly this, so the generated part is only
 * the per-brand resources: the app name and the palette. The flavour itself is
 * declared in build.gradle.kts, which is code somebody reads, not output.
 */
export function androidFiles(brand, repoRoot, outDir) {
  // Gradle passes where it wants them, because generated resources go through
  // the variant API — a directory written into a source set is one AGP cannot
  // see a task dependency for.
  const dir = outDir
    ? join(outDir, "values")
    : join(repoRoot, "android", "app", "src", brand.id, "res", "values");
  return [
    { path: join(dir, "strings.xml"), contents: strings(brand) },
    { path: join(dir, "brand_colors.xml"), contents: colours(brand) },
  ];
}

function strings(brand) {
  return `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated from brands/${brand.id}.yaml. Do not edit. -->
<resources>
    <string name="app_name">${xml(brand.mobile.displayName)}</string>
    <string name="brand_name">${xml(brand.name)}</string>
    <string name="brand_tagline">${xml(brand.tagline)}</string>
    <string name="brand_support_email">${xml(brand.support.email)}</string>
</resources>
`;
}

function colours(brand) {
  const { ramp, source } = brand;
  return `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated from brands/${brand.id}.yaml. Do not edit.

     Compose reads these through BrandColours rather than hardcoding a palette,
     so a brand is a flavour rather than a fork.
-->
<resources>
    <color name="brand_source_primary">${source.primary}</color>
    <color name="brand_source_primary_pale">${source.primaryPale}</color>
    <color name="brand_source_surface">${source.surface}</color>
    <color name="brand_source_accent">${source.accent}</color>

    <color name="brand_primary_500">${ramp.primary500}</color>
    <color name="brand_primary_600">${ramp.primary600}</color>
    <color name="brand_primary_700">${ramp.primary700}</color>
    <color name="brand_primary_900">${ramp.primary900}</color>

    <color name="brand_accent_600">${ramp.accent600}</color>
    <color name="brand_accent_700">${ramp.accent700}</color>

    <color name="brand_ink_900">${ramp.ink900}</color>
    <color name="brand_ink_700">${ramp.ink700}</color>
    <color name="brand_ink_500">${ramp.ink500}</color>
</resources>
`;
}

const xml = (s) =>
  String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
