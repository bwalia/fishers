import { brand } from "@/brand.generated";

/// Android App Links: the site vouching for its own app.
///
/// An Android phone that has the app installed reads this before it lets the
/// app take `https://<site>/invite/<token>` links, so a club link dropped in a
/// WhatsApp group opens straight in the app instead of the browser. The app's
/// side is the intent filter in `android/app/src/main/AndroidManifest.xml`.
///
/// Per brand, from `mobile.androidCertSha256` in `brands/<id>.yaml`: the
/// fingerprint of the key Google Play signs that brand's app with. A brand
/// whose key is not known yet gets a 404 rather than a statement naming the
/// wrong key — the phone treats both the same (the links open the website),
/// and only one of them is true.
export function GET() {
  const fingerprints: readonly string[] = brand.androidCertSha256;
  if (fingerprints.length === 0) {
    return new Response("Not found", { status: 404 });
  }
  return Response.json([
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: brand.androidPackage,
        sha256_cert_fingerprints: fingerprints,
      },
    },
  ]);
}
