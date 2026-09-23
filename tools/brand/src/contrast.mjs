/**
 * WCAG 2.1 contrast.
 *
 * Written out rather than taken from a package because being wrong here is
 * invisible: it would pass a build and ship a screen nobody can read. The
 * formulas are from the spec and the tests check them against the published
 * worked examples.
 */

/** sRGB hex to relative luminance, per WCAG 2.1 §relative-luminance. */
export function luminance(hex) {
  const channels = parseHex(hex).map((eight) => {
    const c = eight / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  const [r, g, b] = channels;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** The ratio between two colours, always >= 1, lighter over darker. */
export function contrast(a, b) {
  const [lighter, darker] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (lighter + 0.05) / (darker + 0.05);
}

/** WCAG AA for body text. Large text is 3:1, but nothing here relies on that. */
export const AA_NORMAL = 4.5;

export function parseHex(hex) {
  const value = String(hex).trim().replace(/^#/, "");
  const full = value.length === 3 ? value.replace(/./g, (c) => c + c) : value;
  if (!/^[0-9a-fA-F]{6}$/.test(full)) {
    throw new Error(`"${hex}" is not a hex colour`);
  }
  return [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16));
}
