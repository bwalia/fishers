import { ImageResponse } from "next/og";
import { brand } from "@/brand.generated";

/// The picture WhatsApp, Slack and Twitter show when somebody pastes a link.
///
/// Generated rather than committed, because it is the brand that decides what
/// it says: a PNG in `public/` would be Fishers' card on GullyCricket's pages.
/// No font is loaded on purpose — `ImageResponse` carries its own, and
/// fetching Barlow at build time is a network call that can fail a build for
/// an image nobody reads the kerning of.
export const alt = `${brand.name} — ${brand.tagline}`;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function openGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "90px",
          background: brand.themeDark,
          color: "#f3f6f0",
        }}
      >
        <div style={{ display: "flex", fontSize: 92, fontWeight: 700, letterSpacing: "-0.02em" }}>
          {brand.name}
        </div>
        <div style={{ display: "flex", width: 120, height: 8, background: "#7fa37f", margin: "34px 0" }} />
        <div style={{ display: "flex", fontSize: 44, lineHeight: 1.3, color: "#c8d2c6" }}>
          {brand.tagline}
        </div>
        <div style={{ display: "flex", marginTop: "auto", fontSize: 30, color: "#a7b4a5" }}>
          {brand.domain}
        </div>
      </div>
    ),
    size,
  );
}
