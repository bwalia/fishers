/// A player's face, or their initials when there isn't one.
///
/// Most people never upload a photo, so the fallback is the common case rather
/// than an error state: initials on a colour derived from the name, which is
/// stable per person and needs nothing stored.
export function Avatar({
  name,
  url,
  size = 40,
  className = "",
}: {
  name: string;
  url?: string | null;
  size?: number;
  className?: string;
}) {
  const style = { width: size, height: size, fontSize: Math.round(size * 0.38) };

  if (url) {
    return (
      // Plain <img>: these come from MinIO at runtime, whose host the
      // next/image loader would have to be told about at build time.
      // eslint-disable-next-line @next/next/no-img-element
      <img
        className={`avatar ${className}`}
        style={style}
        src={url}
        alt={name}
        width={size}
        height={size}
        loading="lazy"
      />
    );
  }

  return (
    <span className={`avatar initials ${className}`} style={{ ...style, background: tint(name) }} aria-hidden>
      {initials(name)}
    </span>
  );
}

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  const first = parts[0][0] ?? "";
  const last = parts.length > 1 ? parts[parts.length - 1][0] ?? "" : "";
  return (first + last).toUpperCase();
}

/// Same name, same colour, every time — a hash into the sage/gold family so
/// a wall of initials still looks like one design rather than confetti.
function tint(name: string): string {
  let h = 0;
  for (const ch of name) h = (h * 31 + ch.charCodeAt(0)) % 360;
  return `hsl(${90 + (h % 60)} 22% ${34 + (h % 3) * 6}%)`;
}
