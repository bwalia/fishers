/// Which build this is.
///
/// `APP_VERSION` is baked into the image when it is built: the `vX.Y.Z` tag on
/// that commit, or its short sha when it has none. That is the only honest
/// answer, because the image is what is running. Reading the newest tag from
/// GitHub instead — which this used to do for every ring — made test, acc and
/// prod all claim the latest release while serving the one before it.
///
/// The GitHub lookup is kept only for `next dev` and any build without the
/// argument, where nothing better is known.
const REPO = process.env.GITHUB_REPO?.trim() || "bwalia/fishers";

/// Cached for an hour, so GitHub is asked once per ring per hour and stays
/// well inside the 60-an-hour it allows an unauthenticated caller. The abort
/// is what keeps a slow or unreachable GitHub from holding up a page: the
/// footer loses its version chip and nothing else.
export async function appVersion(): Promise<{ tag: string; url: string } | null> {
  const url = `https://github.com/${REPO}/releases/tag/`;
  const pinned = process.env.APP_VERSION?.trim();
  if (pinned) {
    // A tag has a release page; a bare sha has a commit page and nothing else.
    const isTag = /^v\d/.test(pinned);
    return { tag: pinned, url: isTag ? url + pinned : `https://github.com/${REPO}/commit/${pinned}` };
  }
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
