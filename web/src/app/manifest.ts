import type { MetadataRoute } from "next";
import { brand } from "@/brand.generated";

/// What a phone needs to keep this on a home screen.
///
/// A scorer at a ground opens the app once and then has no signal for three
/// hours. Installed, it launches from the home screen with no browser chrome
/// and — with the service worker — without the network. The brand supplies the
/// name and the colours, because a literal here is a place the next brand is
/// wrong.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: brand.name,
    short_name: brand.name,
    description: brand.description,
    start_url: "/",
    display: "standalone",
    background_color: brand.themeLight,
    theme_color: brand.themeLight,
    orientation: "any",
    icons: [
      { src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" },
      { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "maskable" },
    ],
    // Straight to the thing somebody opens the app at a ground to do.
    shortcuts: [
      { name: "Score a match", url: "/score" },
      { name: "Fixtures", url: "/events" },
    ],
  };
}
