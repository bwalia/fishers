import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * What the Next.js build needs.
 *
 * Two files: the custom properties the stylesheet already reads, and the
 * constants every place the product names itself now reads instead of a
 * literal. Neither is committed — generated code in the repo drifts from the
 * source it came from.
 */
/**
 * The files a brand has to supply itself.
 *
 * Missing ones are an error rather than a fallback. A fallback here means
 * shipping another brand's mark, which is worse than a build that stops and
 * says which file to add.
 *
 * The mark is the drawing; the PNGs are rendered from it and its full-bleed
 * twin by `npm --prefix tools/brand run icons`. The header takes the source
 * file itself, because it is drawn at three sizes on the same page — vector
 * where the brand has one, and the artwork where it does not.
 */
const ASSETS = ["icon-192.png", "icon-512.png", "badge.png"];

/**
 * The file the header mark is served from.
 *
 * A brand that was drawn has mark.svg; one whose logo arrived as artwork has
 * mark.png. Which one it is has to reach the component, because a browser
 * will not serve a PNG named .svg — so it is generated into brand.generated.ts
 * rather than assumed here.
 */
function markAsset(repoRoot, brand) {
  // mark-192.png rather than mark.png: the source artwork is the thing the
  // other sizes are rendered FROM, and shipping it to a browser that draws it
  // at 32px costs most of a megabyte.
  for (const name of ["mark.svg", "mark-192.png"]) {
    if (existsSync(join(repoRoot, "brands", brand.id, name))) return name;
  }
  return null;
}

export function webAssets(brand, repoRoot, outDir) {
  const from = join(repoRoot, "brands", brand.id);
  const to = outDir ? join(outDir, "public") : join(repoRoot, "web", "public");
  const mark = markAsset(repoRoot, brand);
  const wanted = [...ASSETS, ...(mark ? [mark] : [])];
  const missing = [...ASSETS.filter((name) => !existsSync(join(from, name))), ...(mark ? [] : ["mark.svg or mark.png"])];
  if (missing.length) {
    throw new Error(
      `${brand.name} has no ${missing.join(", ")}. Put them in brands/${brand.id}/ — ` +
        `a build cannot fall back to another brand's mark.`,
    );
  }
  return wanted.map((name) => ({
    path: join(to, name),
    contents: readFileSync(join(from, name)),
  }));
}

export function webFiles(brand, repoRoot, outDir) {
  // `outDir` is the dashboard's own root. The container build passes it,
  // because there the tool lives outside the app and would otherwise resolve
  // a repo root that does not contain it.
  const web = outDir ?? join(repoRoot, "web");
  const from = join(repoRoot, "brands", brand.id);
  return [
    {
      path: join(web, "src", "app", "brand.generated.css"),
      contents: css(brand),
    },
    {
      path: join(web, "src", "brand.generated.ts"),
      contents: typescript(brand, markAsset(repoRoot, brand)),
    },
    // The browser tab and the iOS home screen, as Next's app-directory
    // conventions want them. Generated per brand rather than committed: a
    // single icon.svg checked in here is one brand's mark worn by every brand,
    // which is what GullyCricket was serving in its tab — Fishers' ball.
    //
    // PNG, not SVG, because a brand's artwork is not always a drawing, and a
    // favicon is read at 16px where that difference does not survive anyway.
    // Skipped rather than thrown when the rendered PNGs are not there:
    // webAssets above already refuses a brand that is missing them, and it
    // does it by name, so failing twice for one reason only buys a worse
    // message.
    ...[
      ["icon.png", "icon-192.png"],
      ["apple-icon.png", "icon-512.png"],
    ]
      .filter(([, src]) => existsSync(join(from, src)))
      .map(([out, src]) => ({
        path: join(web, "src", "app", out),
        contents: readFileSync(join(from, src)),
      })),
  ];
}

function css(brand) {
  const { ramp, source, dark, id } = brand;
  return `/* Generated from brands/${id}.yaml. Do not edit.
 *
 * The source colours are what the brand looks like; the ramp is what carries
 * text, darkened until it does. Every pair a screen puts together is checked
 * by \`npm run brand:check\`, which fails under 4.5:1 — the original sage was
 * 2.7:1 on white, and that is the mistake this stops repeating.
 *
 * The names below are the ones globals.css has always used. Keeping them means
 * a brand change is this file and nothing else.
 */
:root {
  --sage: ${source.primary};
  --sage-pale: ${source.primaryPale};
  --cream: ${source.surface};
  --gold: ${source.accent};

  --sage-400: ${ramp.primary400};
  --sage-500: ${ramp.primary500};
  --sage-600: ${ramp.primary600};
  --sage-700: ${ramp.primary700};
  --sage-800: ${ramp.primary800};
  --sage-900: ${ramp.primary900};

  --gold-400: ${ramp.accent400};
  --gold-500: ${ramp.accent500};
  --gold-600: ${ramp.accent600};
  --gold-700: ${ramp.accent700};

  --ink-900: ${ramp.ink900};
  --ink-700: ${ramp.ink700};
  --ink-500: ${ramp.ink500};

  /* Dark, mixed from the same hue — the two themes are the same room at
     different times of day, not a grey inversion. globals.css points its dark
     block at these. */
  --brand-dark-bg: ${dark.bg};
  --brand-dark-surface: ${dark.surface};
  --brand-dark-surface-2: ${dark.surface2};
  --brand-dark-surface-3: ${dark.surface3};
  --brand-dark-fg: ${dark.fg};
  --brand-dark-fg-muted: ${dark.fgMuted};
  --brand-dark-fg-subtle: ${dark.fgSubtle};
  --brand-dark-border: ${dark.border};
  --brand-dark-border-strong: ${dark.borderStrong};
  --brand-dark-on-primary: ${dark.onPrimary};
  --brand-dark-raised: ${dark.raised};
  --brand-dark-accent-pale: ${dark.accentPale};
}
`;
}

function typescript(brand, mark) {
  const value = {
    id: brand.id,
    name: brand.name,
    legalName: brand.legalName,
    tagline: brand.tagline,
    description: brand.description,
    domain: brand.domain,
    supportEmail: brand.support.email,
    // The browser chrome is painted from metadata rather than from CSS, so
    // these two have to be here as well as in the stylesheet.
    themeLight: brand.source.surface,
    themeDark: brand.dark.bg,
    // Where the header mark is served from. A brand that was drawn has a
    // vector here; one whose logo arrived as artwork has a PNG, and the
    // component must not have to know which.
    markSrc: `/${mark ?? "mark.svg"}`,
    // And the dark one. The mark is drawn for a light page — GullyCricket's is
    // navy on nothing, which on a dark surface is nothing on nothing, and that
    // is exactly how it shipped. The icon is the same artwork full-bleed, with
    // a background of its own, which is what it was drawn for: "a home screen
    // gives it none". So dark surfaces get the tile.
    markSrcDark: "/icon-192.png",
  };
  return `/* Generated from brands/${brand.id}.yaml. Do not edit. */

/**
 * Who this build is.
 *
 * Every place the product names itself reads from here, so one file is the
 * difference between Fishers and GullyCricket. Import \`brand\` rather than
 * writing the name: a literal is a place the next brand is wrong.
 */
export const brand = ${JSON.stringify(value, null, 2)} as const;

export type Brand = typeof brand;
`;
}
