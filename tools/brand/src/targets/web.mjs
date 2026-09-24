import { join } from "node:path";

/**
 * What the Next.js build needs.
 *
 * Two files: the custom properties the stylesheet already reads, and the
 * constants every place the product names itself now reads instead of a
 * literal. Neither is committed — generated code in the repo drifts from the
 * source it came from.
 */
export function webFiles(brand, repoRoot, outDir) {
  // `outDir` is the dashboard's own root. The container build passes it,
  // because there the tool lives outside the app and would otherwise resolve
  // a repo root that does not contain it.
  const web = outDir ?? join(repoRoot, "web");
  return [
    {
      path: join(web, "src", "app", "brand.generated.css"),
      contents: css(brand),
    },
    {
      path: join(web, "src", "brand.generated.ts"),
      contents: typescript(brand),
    },
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

function typescript(brand) {
  const value = {
    id: brand.id,
    name: brand.name,
    legalName: brand.legalName,
    tagline: brand.tagline,
    description: brand.description,
    domain: brand.domain,
    supportEmail: brand.support.email,
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
