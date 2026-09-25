import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { checkContrast, listBrands, loadBrand, BrandError } from "../src/brand.mjs";
import { validate } from "../src/schema.mjs";
import { webAssets, webFiles } from "../src/targets/web.mjs";
import { androidFiles } from "../src/targets/android.mjs";
import { iosFiles } from "../src/targets/ios.mjs";
import { wslproxyFiles } from "../src/targets/wslproxy.mjs";
import {
  dnsHostsFor,
  edgeHostsFor,
  helmValues,
  hostFor,
  namespaceFor,
  zoneFor,
} from "../src/helm.mjs";

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
gateway: []
support:
  email: hello@example.test
  sslEmail: admin@example.test
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
dark:
  bg: "#111712"
  surface: "#171d17"
  surface2: "#1c231c"
  surface3: "#242c24"
  fg: "#f3f6f0"
  fgMuted: "#c8d2c6"
  fgSubtle: "#a7b4a5"
  border: "#303a30"
  borderStrong: "#475547"
  onPrimary: "#14210f"
  raised: "#1d251d"
  accentPale: "#2e2717"
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
      for (const expected of [
        "name", "domain", "rings.prod", "source.primary", "dark.bg", "mobile.bundleId",
      ]) {
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

/**
 * The stylesheet owns the palette. The only colours here are the two the
 * browser chrome is painted from, which come from metadata rather than CSS —
 * anything else has leaked, and a palette in two places drifts.
 */
test("the web constants carry only the two chrome colours", () => {
  const brand = loadBrand(repoRoot, "gullycricket");
  const [, ts] = webFiles(brand, "/tmp/x");
  assert.match(ts.contents, /"name": "Gully Cricket"/);

  const colours = ts.contents.match(/#[0-9a-f]{6}/g) ?? [];
  assert.deepEqual(
    colours.sort(),
    [brand.dark.bg, brand.source.surface].sort(),
    "a colour other than the chrome pair leaked into the constants",
  );
});

test("android resources are written under the flavour's own directory", () => {
  const brand = loadBrand(repoRoot, "gullycricket");
  const files = androidFiles(brand, repoRoot);
  // Everything under the flavour's own res/ — values for the strings and
  // colours, mipmap-* for the launcher icon.
  assert.ok(files.every((f) => f.path.includes("/src/gullycricket/res/")));
  assert.match(files[0].contents, /<string name="app_name">Gully Cricket<\/string>/);
  assert.ok(
    files.some((f) => f.path.endsWith("/mipmap-xxxhdpi/ic_launcher.png")),
    "the flavour has no launcher icon of its own",
  );
});

/**
 * A brand name is somebody's input. Unescaped it breaks the XML, and the
 * generated header used to carry it raw — which no amount of escaping the
 * element content would have saved.
 */
test("a brand name with xml characters in it cannot break the resources", () => {
  const brand = { ...loadBrand(repoRoot, "fishers"), name: "Tom & Jerry's <XI>" };
  const [strings] = androidFiles(brand, repoRoot);

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
  for (const file of androidFiles(brand, repoRoot)) {
    if (Buffer.isBuffer(file.contents)) continue; // the icons, which say nothing
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
  const [xcconfig] = iosFiles(brand, repoRoot);
  assert.match(xcconfig.contents, /PRODUCT_BUNDLE_IDENTIFIER = app\.gullycricket/);
});

/**
 * SwiftUI reaches for AccentColor without being asked, so a brand that did not
 * write one would be its own colour everywhere it named one and Fishers' sage
 * everywhere it did not — the hardest kind of wrong to see in a screenshot.
 */
test("the iOS accent colour is the brand's, in both appearances", () => {
  const files = iosFiles(loadBrand(repoRoot, "gullycricket"), repoRoot);
  const accent = files.find((f) => f.path.endsWith("AccentColor.colorset/Contents.json"));
  assert.ok(accent, "no AccentColor was generated");
  const { colors } = JSON.parse(accent.contents);
  const [light, dark] = colors;
  // #a54f18 — GullyCricket's primary600, the step that carries white text.
  assert.equal(light.color.components.red, (0xa5 / 255).toFixed(3));
  assert.equal(dark.appearances[0].value, "dark");
  assert.notDeepEqual(light.color.components, dark.color.components);
});

/**
 * The generated Swift is the whole palette, not a sample of it: a colour the
 * app cannot get from Brand is a colour somebody writes as a hex literal, and
 * a hex literal is where the last brand stayed.
 */
test("the generated Swift carries every ramp and dark colour", () => {
  const [, swift] = iosFiles(loadBrand(repoRoot, "gullycricket"), repoRoot);
  for (const name of ["primary600", "primary900", "accent700", "ink500"]) {
    assert.match(swift.contents, new RegExp(`static let ${name} = Color\\(hex:`));
  }
  for (const name of ["bg", "surface2", "fgMuted", "borderStrong"]) {
    assert.match(swift.contents, new RegExp(`static let ${name} = Color\\(hex:`));
  }
});

/**
 * The release workflows append this straight to $GITHUB_ENV, and fastlane's
 * Appfile and Fastfile read both. A change to the shape here is a change to
 * which App Store listing a build is signed for.
 */
test("a brand's mobile identity is shell the workflows can append", () => {
  const brand = loadBrand(repoRoot, "gullycricket");
  assert.equal(brand.mobile.bundleId, "app.gullycricket");
  // The display name is two words; the id, which is a namespace and a Gradle
  // flavour, is one.
  assert.equal(brand.mobile.displayName, "Gully Cricket");
  assert.equal(brand.id, "gullycricket");
});

test("the helm overlay carries the brand and its host", () => {
  const brand = loadBrand(repoRoot, "gullycricket");
  const values = helmValues(brand, "int");
  assert.match(values, /hostname: int\.gullycricket\.app/);
  assert.match(values, /brand: gullycricket/);
});

/**
 * A gateway belongs to one brand: its Service lives in that brand's namespace.
 * A ring without one must say so, because naming a Service that is not there
 * does not fail the deploy — Traefik drops the paths and answers 404, which is
 * how GullyCricket's int came up with no /api, /swagger-ui or /health.
 */
test("the overlay turns Kong off for a brand with no gateway of its own", () => {
  assert.match(helmValues(loadBrand(repoRoot, "gullycricket"), "int"), /enabled: false/);
  assert.match(helmValues(loadBrand(repoRoot, "fishers"), "int"), /enabled: true/);
  // Fishers has it on int and nowhere else. A ring that quietly gained one
  // would send every browser call to the API through a gateway nobody sized.
  for (const ring of ["test", "acc", "prod"]) {
    assert.match(
      helmValues(loadBrand(repoRoot, "fishers"), ring),
      /enabled: false/,
      `fishers ${ring} has no gateway deployed`,
    );
  }
});

test("a gateway on a ring that does not exist is rejected, not deployed", () => {
  const brand = { ...loadBrand(repoRoot, "fishers"), gateway: ["stagng"] };
  assert.throws(() => validate(brand, "brands/x.yaml"), /not a ring/);
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

// ---- the edge ----

test("a ring's hosts come from the brand, and prod carries the apex", () => {
  const fishers = loadBrand(repoRoot, "fishers");
  assert.deepEqual(edgeHostsFor(fishers, "int"), ["int.fishers.cloud"]);
  assert.deepEqual(edgeHostsFor(fishers, "prod"), ["www.fishers.cloud", "fishers.cloud"]);
});

/**
 * The apex is an A record at the zone root. A CNAME cannot coexist with one,
 * so Cloudflare refuses the upsert and takes the whole deploy with it — the
 * apex needs the vhost, for its own certificate, and nothing else.
 */
test("the apex is left out of the CNAMEs", () => {
  const fishers = loadBrand(repoRoot, "fishers");
  assert.deepEqual(dnsHostsFor(fishers, "prod"), ["www.fishers.cloud"]);
  assert.ok(!dnsHostsFor(fishers, "prod").includes("fishers.cloud"));
});

test("a second brand registers in its own zone, not somebody else's", () => {
  const gully = loadBrand(repoRoot, "gullycricket");
  assert.equal(zoneFor(gully), "gullycricket.app");
  assert.deepEqual(edgeHostsFor(gully, "int"), ["int.gullycricket.app"]);
  assert.deepEqual(
    edgeHostsFor(gully, "prod"),
    ["www.gullycricket.app", "gullycricket.app"],
  );
});

test("no brand's hosts stray into another brand's zone", () => {
  for (const id of listBrands(repoRoot)) {
    const brand = loadBrand(repoRoot, id);
    for (const ring of ["int", "test", "acc", "prod"]) {
      for (const host of edgeHostsFor(brand, ring)) {
        assert.ok(
          host === brand.domain || host.endsWith(`.${brand.domain}`),
          `${id} ${ring} registers ${host}, which is not in ${brand.domain}`,
        );
      }
    }
  }
});

// ---- assets ----

/**
 * A brand without its own mark is not ready, and a fallback here would mean
 * shipping somebody else's logo under a different name.
 */
test("a brand without its own icons is refused, by name", () => {
  const brand = { ...loadBrand(repoRoot, "fishers"), id: "no-such-brand" };
  assert.throws(
    () => webAssets(brand, repoRoot),
    /icon-192\.png.*brands\/no-such-brand/s,
  );
});

test("every brand in this repo supplies its own icons", () => {
  for (const id of listBrands(repoRoot)) {
    const brand = loadBrand(repoRoot, id);
    const files = webAssets(brand, repoRoot);
    assert.equal(files.length, 3, `${id} is missing an asset`);
    for (const f of files) {
      assert.ok(f.contents.length > 0, `${id}: ${f.path} is empty`);
    }
  }
});

test("no two brands ship the same icon", () => {
  const seen = new Map();
  for (const id of listBrands(repoRoot)) {
    const [icon] = webAssets(loadBrand(repoRoot, id), repoRoot);
    const key = icon.contents.toString("base64");
    const owner = seen.get(key);
    assert.ok(!owner, `${id} ships ${owner}'s icon`);
    seen.set(key, id);
  }
});

/** The browser chrome is painted from metadata, not from the stylesheet. */
test("the chrome colours reach the typescript", () => {
  const gully = loadBrand(repoRoot, "gullycricket");
  const [, ts] = webFiles(gully, "/tmp/x");
  assert.match(ts.contents, /"themeLight": "#fdf7f2"/);
  assert.match(ts.contents, /"themeDark": "#1a1210"/);
});

// ---- the edge vhost specs ----

/**
 * Fishers' specs are live and working. The generator has to reproduce them
 * exactly, or adopting it silently rewrites a working edge — which is the kind
 * of change that is only noticed when a certificate stops renewing.
 */
test("the generator reproduces the committed fishers specs byte for byte", () => {
  const brand = loadBrand(repoRoot, "fishers");
  for (const file of wslproxyFiles(brand, repoRoot)) {
    const committed = readFileSync(file.path, "utf8");
    assert.equal(
      JSON.stringify(JSON.parse(file.contents), null, 2),
      JSON.stringify(JSON.parse(committed), null, 2),
      `${file.path} would be rewritten`,
    );
  }
});

test("every hostname a brand answers on gets a spec", () => {
  const gully = loadBrand(repoRoot, "gullycricket");
  const paths = wslproxyFiles(gully, "/repo").map((f) => f.path);
  for (const host of ["int.gullycricket.app", "www.gullycricket.app", "gullycricket.app"]) {
    assert.ok(
      paths.some((p) => p.endsWith(`host-${host}.json`)),
      `${host} has no vhost spec`,
    );
  }
});

/** Let's Encrypt writes about expiring certificates; a customer must not land there. */
test("the certificate address is not the support address", () => {
  for (const id of listBrands(repoRoot)) {
    const brand = loadBrand(repoRoot, id);
    assert.notEqual(
      brand.support.sslEmail,
      brand.support.email,
      `${id} points certificate mail at its support address`,
    );
  }
});
