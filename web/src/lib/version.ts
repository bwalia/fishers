/// Which build this is, read from the repo's tags.
///
/// The tag rather than the commit: `v1.0.148` is something somebody can quote
/// in a bug report, and it is what the release page is addressed by. There is
/// no version in `package.json` worth showing — it has never been bumped —
/// and baking one in at build time means the number is only ever as fresh as
/// the last image, which on a ring that has not redeployed is a lie.
///
/// `APP_VERSION` short-circuits the lookup, for a deployment that would rather
/// pin the number than let a page depend on github.com.
const REPO = process.env.GITHUB_REPO?.trim() || "bwalia/fishers";

/// Cached for an hour, so GitHub is asked once per ring per hour and stays
/// well inside the 60-an-hour it allows an unauthenticated caller. The abort
/// is what keeps a slow or unreachable GitHub from holding up a page: the
/// footer loses its version chip and nothing else.
export async function appVersion(): Promise<{ tag: string; url: string } | null> {
  const url = `https://github.com/${REPO}/releases/tag/`;
  const pinned = process.env.APP_VERSION?.trim();
  if (pinned) return { tag: pinned, url: url + pinned };
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/tags?per_page=1`, {
      headers: { accept: "application/vnd.github+json" },
      signal: AbortSignal.timeout(2500),
      next: { revalidate: 3600 },
    });
    if (!res.ok) return null;
    const tags: { name?: string }[] = await res.json();
    const tag = tags[0]?.name;
    return tag ? { tag, url: url + tag } : null;
  } catch {
    return null;
  }
}
