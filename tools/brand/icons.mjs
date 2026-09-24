/**
 * Rasterise a brand's two drawings into the sizes each platform wants.
 *
 * Run by hand when the artwork changes, not by the build:
 *
 *   npm --prefix tools/brand run icons            # every brand
 *   npm --prefix tools/brand run icons gullycricket
 *
 * The PNGs are committed. They are outputs, but they are outputs of a step
 * that needs a rasteriser, and putting `sharp` in the path of every web, iOS
 * and Android build to redraw eight icons that change twice a year is a worse
 * trade than a handful of files in git. `sharp` is a devDependency for the
 * same reason: CI installs with --omit=dev and never sees it.
 */
import { existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { listBrands, loadBrand } from "./src/brand.mjs";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

/**
 * What comes out of which drawing.
 *
 * `icon` is the full-bleed tile — it has its own background, because a home
 * screen gives it none. `mark` is the same thing drawn for a light page, where
 * a tile would be a box around nothing.
 */
const SIZES = [
  // iOS: the App Store icon, and the two imagesets the brand header uses.
  ["icon", 1024, "icon-1024.png"],
  ["icon", 512, "icon-512.png"],
  ["mark", 512, "mark-512.png"],
  // Web: the PWA icon, and the notification badge Chrome masks to a silhouette.
  ["icon", 192, "icon-192.png"],
  ["mark", 96, "badge.png"],
  // Android launcher, one per density bucket. xxxhdpi is 192, which the web
  // icon already covers.
  ["icon", 144, "icon-144.png"],
  ["icon", 96, "icon-96.png"],
  ["icon", 72, "icon-72.png"],
  ["icon", 48, "icon-48.png"],
];

async function main() {
  let sharp;
  try {
    ({ default: sharp } = await import("sharp"));
  } catch {
    console.error(
      "This needs sharp, which is a devDependency so CI does not carry it:\n" +
        "  npm --prefix tools/brand install",
    );
    return 1;
  }

  const wanted = process.argv.slice(2);
  const brands = wanted.length ? wanted : listBrands(repoRoot);

  for (const id of brands) {
    const brand = loadBrand(repoRoot, id);
    const dir = join(repoRoot, "brands", id);
    for (const source of ["mark", "icon"]) {
      if (!existsSync(join(dir, `${source}.svg`))) {
        console.error(
          `${brand.name} has no ${source}.svg. Both drawings are the brand's own —` +
            ` a fallback here ships somebody else's mark.`,
        );
        return 1;
      }
    }

    mkdirSync(dir, { recursive: true });
    for (const [source, size, name] of SIZES) {
      // density, not the default 72dpi: sharp rasterises the SVG at that
      // density and *then* resizes, so a 1024px icon off a 48pt viewBox comes
      // out of a 72dpi render upscaled and soft.
      await sharp(join(dir, `${source}.svg`), { density: 600 })
        .resize(size, size)
        .png({ compressionLevel: 9 })
        .toFile(join(dir, name));
      console.log(`  ${brand.name.padEnd(14)} ${name.padEnd(16)} ${size}px from ${source}.svg`);
    }
  }
  return 0;
}

process.exit(await main());
