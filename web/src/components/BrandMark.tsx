import { brand } from "@/brand.generated";

/// The brand's mark.
///
/// Deliberately not part of the line-art `Icon` set — those are interface
/// furniture drawn in whatever colour their surroundings use, and a badge has
/// to be itself wherever it lands: the top bar, a browser tab, a phone's home
/// screen, a notification.
///
/// The drawing itself lives in `brands/<id>/mark.svg` — or `mark.png`, where a
/// brand's logo arrived as artwork rather than as a drawing — and the brand
/// generator copies it and writes the path into `brand.markSrc`. This
/// component holds no artwork and no file extension: it used to hold Fishers'
/// cricket ball inline, which is why every other brand wore it.
///
/// There are two, because a mark drawn for a light page has nothing to stand
/// on when the page is dark. GullyCricket's is navy on transparent, so in dark
/// mode it was invisible — not faint, absent. The dark one is the brand's
/// full-bleed icon, which carries its own background.
export function BrandMark({
  size = 24,
  className,
}: {
  size?: number;
  className?: string;
}) {
  // Both are rendered and CSS shows one. Not a media query in JS and not a
  // theme read at runtime: the bar is on screen before hydration, and a mark
  // that picks itself after first paint flickers through the wrong one. The
  // hidden copy costs a `display: none` img — it is not fetched by any
  // browser that honours the rule, and it is never announced, because
  // display:none takes it out of the accessibility tree too.
  const cls = (which: string) =>
    `brand-mark brand-mark-${which}${className ? ` ${className}` : ""}`;
  return (
    <>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={brand.markSrc}
        width={size}
        height={size}
        alt={brand.name}
        decoding="async"
        className={cls("light")}
      />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={brand.markSrcDark}
        width={size}
        height={size}
        alt={brand.name}
        decoding="async"
        className={cls("dark")}
      />
    </>
  );
}
