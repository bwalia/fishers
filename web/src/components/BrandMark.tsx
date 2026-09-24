import { brand } from "@/brand.generated";

/// The brand's mark.
///
/// Deliberately not part of the line-art `Icon` set — those are interface
/// furniture drawn in whatever colour their surroundings use, and a badge has
/// to be itself wherever it lands: the top bar, a browser tab, a phone's home
/// screen, a notification.
///
/// The drawing itself lives in `brands/<id>/mark.svg` and is copied to
/// `/mark.svg` by the brand generator, so this component holds no artwork. It
/// used to hold Fishers' cricket ball inline, which is why every other brand
/// wore it.
export function BrandMark({
  size = 24,
  className,
}: {
  size?: number;
  className?: string;
}) {
  return (
    // eslint-disable-next-line @next/next/no-img-element -- a fixed-size static
    // asset that is on screen before hydration; next/image would defer it and
    // route it through the optimiser for no gain.
    <img
      src="/mark.svg"
      width={size}
      height={size}
      className={className}
      alt={brand.name}
      decoding="async"
    />
  );
}
