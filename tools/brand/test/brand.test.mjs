import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { checkContrast, listBrands, loadBrand, BrandError } from "../src/brand.mjs";
import { webFiles } from "../src/targets/web.mjs";
import { androidFiles } from "../src/targets/android.mjs";
import { iosFiles } from "../src/targets/ios.mjs";
import { helmValues, hostFor, namespaceFor } from "../src/helm.mjs";

const repoRoot = join(import.meta.dirname, "..", "..", "..");

const READABLE = `
id: test-brand
name: Test Brand
legalName: Test Brand Ltd
tagline: A tagline
description: A description
domain: example.test
rings:
  int: int.example.test
  test: test.example.test
  acc: acc.example.test
  prod: www.example.test
support:
  email: hello@example.test
source:
  primary: "#8fa28a"
  primaryPale: "#c7d3c0"
  surface: "#f7f4ed"
  accent: "#c8a96b"
ramp:
  primary400: "#8fa28a"
  primary500: "#798c76"
  primary600: "#667964"
  primary700: "#556754"
  primary800: "#445645"
  primary900: "#2c3a2d"
  accent400: "#c8a96b"
  accent500: "#ac9058"
  accent600: "#927947"
  accent700: "#7e673a"
  ink900: "#202a21"
  ink700: "#374337"
  ink500: "#4e5c4d"
mobile:
  bundleId: test.example.app
  displayName: Test Brand
`;

/** A scratch repo with whatever brand files a test needs. */
function withBrands(files, run) {
  const dir = mkdtempSync(join(tmpdir(), "brand-"));
  try {
    mkdirSync(join(dir, "brands"), { recursive: true });
    for (const [name, body] of Object.entries(files)) {
      writeFileSync(join(dir, "brands", name), body);
    }
    return run(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// ---- the real brands ----

test("this repo's brands all load and are readable", () => {
  const ids = listBrands(repoRoot);
  assert.ok(ids.includes("fishers"), "fishers is still here");
  for (const id of ids) {
    const brand = loadBrand(repoRoot, id);
    const { failed } = checkContrast(brand);
    assert.deepEqual(
      failed.map((f) => f.what),
      [],
      `${id} has unreadable pairs`,
    );
  }
});

test("every brand has its own domain and bundle id", () => {
  const brands = listBrands(repoRoot).map((id) => loadBrand(repoRoot, id));
  const domains = brands.map((b) => b.domain);
  const bundles = brands.map((b) => b.mobile.bundleId);
  assert.equal(new Set(domains).size, domains.length, "two brands share a domain");
  assert.equal(
    new Set(bundles).size,
    bundles.length,
    "two brands share a bundle id, so they are one App Store listing",
  );
});

// ---- the check that matters ----

/**
 * The whole point. A brand that picks a pretty colour without darkening it
 * ships a screen nobody can read, and nothing else in the build would notice.
 */
test("a brand whose text nobody can read is refused", () => {
  const unreadable = READABLE
    .replace('primary600: "#667964"', 'primary600: "#8fa28a"') // the undarkened sage
    .replace("id: test-brand", "id: bad-brand")
    .replace("bundleId: test.example.app", "bundleId: bad.example.app");

  withBrands({ "bad-brand.yaml": unreadable }, (dir) => {
    const brand = loadBrand(dir, "bad-brand");
    const { failed } = checkContrast(brand);
    assert.ok(failed.length > 0, "an undarkened primary should fail");
    assert.match(failed[0].what, /primary button/);
  });
});

// ---- what happens when a brand file is wrong ----

test("a missing brand lists the ones that exist", () => {
  withBrands({ "test-brand.yaml": READABLE }, (dir) => {
    assert.throws(
      () => loadBrand(dir, "nope"),
      (e) => e instanceof BrandError && /test-brand/.test(e.message),
    );
  });
});

test("every missing field is reported at once, not one per run", () => {
  withBrands({ "sparse.yaml": "id: sparse\n" }, (dir) => {
    try {
      loadBrand(dir, "sparse");
      assert.fail("should have refused");
    } catch (e) {
      assert.ok(e instanceof BrandError);
      for (const expected of ["name", "domain", "rings.prod", "source.primary", "mobile.bundleId"]) {
        assert.match(e.message, new RegExp(expected.replace(".", "\\.")));
      }
    }
  });
});

test("a colour that is not a colour says which one", () => {
  const broken = READABLE.replace('primary: "#8fa28a"', 'primary: "sage"');
  withBrands({ "test-brand.yaml": broken }, (dir) => {
    assert.throws(() => loadBrand(dir, "test-brand"), /source\.primary is "sage"/);
  });
});

test("an id that would not survive a namespace is refused", () => {
  const broken = READABLE.replace("id: test-brand", "id: Test_Brand");
  withBrands({ "Test_Brand.yaml": broken }, (dir) => {
    assert.throws(() => loadBrand(dir, "Test_Brand"), /lowercase letters/);
  });
});

test("a bundle id that is not reverse-DNS is refused", () => {
  const broken = READABLE.replace("bundleId: test.example.app", "bundleId: TestBrand");
  withBrands({ "test-brand.yaml": broken }, (dir) => {
    assert.throws(() => loadBrand(dir, "test-brand"), /reverse-DNS/);
  });
});

test("a file whose id disagrees with its name is refused", () => {
  withBrands({ "other.yaml": READABLE }, (dir) => {
    assert.throws(() => loadBrand(dir, "other"), /The file name is the id/);
  });
});

// ---- what gets generated ----

test("the web CSS carries the ramp, not the source colours, for text", () => {
  const brand = loadBrand(repoRoot, "fishers");
  const [css] = webFiles(brand, "/tmp/x");
  assert.match(css.contents, /--sage-600: #667964/);
  assert.match(css.contents, /--ink-900: #202a21/);
  assert.match(css.contents, /Do not edit/);
});

test("the web constants carry no colour, because CSS owns that", () => {
  const brand = loadBrand(repoRoot, "gullycricket");
  const [, ts] = webFiles(brand, "/tmp/x");
  assert.match(ts.contents, /"name": "GullyCricket"/);
  assert.ok(!/#[0-9a-f]{6}/.test(ts.contents), "a colour leaked into the constants");
});

test("android resources are written under the flavour's own directory", () => {
  const brand = loadBrand(repoRoot, "gullycricket");
  const files = androidFiles(brand, "/repo");
  assert.ok(files.every((f) => f.path.includes("/src/gullycricket/res/values/")));
  assert.match(files[0].contents, /<string name="app_name">GullyCricket<\/string>/);
});

/**
 * A brand name is somebody's input. Unescaped it breaks the XML, and the
 * generated header used to carry it raw — which no amount of escaping the
 * element content would have saved.
 */
test("a brand name with xml characters in it cannot break the resources", () => {
  const brand = { ...loadBrand(repoRoot, "fishers"), name: "Tom & Jerry's <XI>" };
  const [strings] = androidFiles(brand, "/repo");

  assert.match(strings.contents, /Tom &amp; Jerry&apos;s &lt;XI&gt;/);
  assert.ok(
    !/Tom & Jerry/.test(strings.contents),
    "the raw name appears somewhere, which would break the XML",
  );
  assert.ok(!/<XI>/.test(strings.contents), "an unescaped tag leaked through");
});

/** Machine-written headers name the file they came from, never free text. */
test("generated headers carry no brand name at all", () => {
  const brand = { ...loadBrand(repoRoot, "fishers"), name: "-- broken --" };
  for (const file of androidFiles(brand, "/repo")) {
    const header = file.contents.split("\n").slice(0, 3).join("\n");
    assert.ok(!header.includes("broken"), `a name reached a header: ${header}`);
  }
});

test("an id with a doubled hyphen is refused, because XML comments forbid it", () => {
  const broken = READABLE
    .replace("id: test-brand", "id: test--brand")
    .replace("bundleId: test.example.app", "bundleId: test.example.app");
  withBrands({ "test--brand.yaml": broken }, (dir) => {
    assert.throws(() => loadBrand(dir, "test--brand"), /single-hyphen separated/);
  });
});

test("the iOS xcconfig carries the bundle id that makes it its own listing", () => {
  const brand = loadBrand(repoRoot, "gullycricket");
  const [xcconfig] = iosFiles(brand, "/repo");
  assert.match(xcconfig.contents, /PRODUCT_BUNDLE_IDENTIFIER = app\.gullycricket/);
});

test("the helm overlay carries the brand and its host", () => {
  const brand = loadBrand(repoRoot, "gullycricket");
  const values = helmValues(brand, "int");
  assert.match(values, /hostname: int\.gullycricket\.app/);
  assert.match(values, /brand: gullycricket/);
});

/**
 * The overlay is only what differs by brand. Repeating the ring's own values
 * is how two files drift until one ring is a version behind.
 */
test("the overlay does not repeat what the ring already decides", () => {
  const values = helmValues(loadBrand(repoRoot, "fishers"), "prod");
  for (const leaked of ["replicaCount", "image:", "resources:", "secretName"]) {
    assert.ok(!values.includes(leaked), `${leaked} does not belong in the overlay`);
  }
});

/**
 * Fishers' namespace is what it has always been. If this changes, an existing
 * deploy moves to a new namespace and leaves its database behind.
 */
test("fishers keeps the namespace it already has", () => {
  const brand = loadBrand(repoRoot, "fishers");
  assert.equal(namespaceFor(brand, "int"), "fishers-int");
  assert.equal(namespaceFor(brand, "prod"), "fishers-prod");
});

test("a new brand gets its own namespace, which is what separates the data", () => {
  const brand = loadBrand(repoRoot, "gullycricket");
  assert.equal(namespaceFor(brand, "int"), "gullycricket-int");
});

test("an unknown ring is refused by name, not with undefined", () => {
  const brand = loadBrand(repoRoot, "fishers");
  assert.throws(() => hostFor(brand, "staging"), /has no "staging" ring/);
  assert.throws(() => namespaceFor(brand, "staging"), /int, test, acc, prod/);
});
