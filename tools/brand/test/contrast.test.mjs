import { test } from "node:test";
import assert from "node:assert/strict";
import { AA_NORMAL, contrast, luminance, parseHex } from "../src/contrast.mjs";

/**
 * Checked against the values WCAG publishes, because a contrast function that
 * is quietly wrong passes every build and ships an unreadable screen.
 */
test("black on white is the maximum, 21:1", () => {
  assert.equal(Math.round(contrast("#000000", "#ffffff")), 21);
});

test("a colour against itself is 1:1", () => {
  assert.equal(contrast("#8fa28a", "#8fa28a"), 1);
});

test("the order of the two colours does not change the answer", () => {
  assert.equal(contrast("#667964", "#ffffff"), contrast("#ffffff", "#667964"));
});

test("luminance is 0 for black and 1 for white", () => {
  assert.equal(luminance("#000000"), 0);
  assert.equal(luminance("#ffffff"), 1);
});

/**
 * The number the design system documents. If this moves, either the formula is
 * wrong or somebody has changed the palette without redoing the work.
 */
test("the ramp's own documented ratios still hold", () => {
  assert.equal(contrast("#ffffff", "#667964").toFixed(2), "4.68");
  assert.equal(contrast("#ffffff", "#7e673a").toFixed(2), "5.40");
});

test("the source sage really does fail, which is why the ramp exists", () => {
  const ratio = contrast("#8fa28a", "#ffffff");
  assert.ok(ratio < AA_NORMAL, `expected under ${AA_NORMAL}, got ${ratio}`);
  assert.equal(ratio.toFixed(1), "2.7");
});

test("shorthand hex is expanded", () => {
  assert.deepEqual(parseHex("#fff"), [255, 255, 255]);
  assert.deepEqual(parseHex("fff"), [255, 255, 255]);
});

test("something that is not a colour says so", () => {
  assert.throws(() => parseHex("sage"), /not a hex colour/);
  assert.throws(() => parseHex("#12345"), /not a hex colour/);
});
