import { cookies, headers } from "next/headers";

import { LOCALE_COOKIE, localeFrom, localeFromAcceptLanguage, makeT, type Locale } from "./index";

/// The reader's language, on the server, before anything is painted.
///
/// The cookie wins because it is a choice; the browser's `Accept-Language` is
/// only a guess, and is used for a first visit so that a Punjabi speaker's
/// first page is already Punjabi rather than English-until-they-find-the-menu.
///
/// Kept out of `index.ts` because `next/headers` cannot be imported into a
/// client component — pulling it in there fails the build.
export async function getLocale(): Promise<Locale> {
  const jar = await cookies();
  const chosen = jar.get(LOCALE_COOKIE)?.value;
  if (chosen) return localeFrom(chosen);
  const head = await headers();
  return localeFromAcceptLanguage(head.get("accept-language"));
}

/// `t` for a server component.
export async function getT() {
  return makeT(await getLocale());
}
