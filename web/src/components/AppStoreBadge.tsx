import { brand } from "@/brand.generated";

/// Apple's "Download on the App Store" badge, linking to this brand's listing.
///
/// Drawn rather than fetched: it is a black pill, the Apple mark and two lines
/// of SF-style text, laid out the way Apple's own badge is, so it is
/// recognised at a glance and costs no request. The words stay in English in
/// every language on purpose — they are Apple's mark, not our copy, and Apple
/// ships no Punjabi badge. The accessible name is ours and is translated.
///
/// Renders nothing for a brand with no live listing, so every place that
/// draws it can do so unconditionally.
export function AppStoreBadge({ label, height = 44 }: { label: string; height?: number }) {
  if (!brand.appStoreUrl) return null;
  return (
    <a
      className="app-store-badge"
      href={brand.appStoreUrl}
      rel="noopener noreferrer"
      target="_blank"
      aria-label={label}
      style={{ height }}
    >
      <svg viewBox="0 0 24 24" width={height * 0.55} height={height * 0.55} aria-hidden="true" focusable="false">
        <path
          fill="currentColor"
          d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"
        />
      </svg>
      <span className="app-store-badge-text" aria-hidden="true">
        <span className="app-store-badge-small">Download on the</span>
        <span className="app-store-badge-big">App Store</span>
      </span>
    </a>
  );
}
