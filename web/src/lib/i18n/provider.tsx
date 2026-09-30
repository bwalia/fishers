"use client";

import { createContext, useCallback, useContext, useMemo, type ReactNode } from "react";
import { useRouter } from "next/navigation";

import { LOCALES, LOCALE_COOKIE, DEFAULT_LOCALE, makeT, type Locale, type T } from "./index";

type Value = { locale: Locale; setLocale: (next: Locale) => void; t: T };

const Ctx = createContext<Value>({
  locale: DEFAULT_LOCALE,
  setLocale: () => {},
  t: makeT(DEFAULT_LOCALE),
});

/// A year. The choice is not something to re-ask on a Monday.
const A_YEAR = 60 * 60 * 24 * 365;

/// Carries the reader's language down the client tree.
///
/// `initial` comes from the server, which read the cookie — so the first paint
/// is already in the right language and there is no flash of English.
export function LocaleProvider({ initial, children }: { initial: Locale; children: ReactNode }) {
  const router = useRouter();

  const setLocale = useCallback(
    (next: Locale) => {
      // `SameSite=Lax` so it survives following a shared live-scoreboard link
      // from a chat app; no `Secure` because local development is http.
      document.cookie = `${LOCALE_COOKIE}=${next}; path=/; max-age=${A_YEAR}; samesite=lax`;
      const root = document.documentElement;
      root.lang = next;
      root.dir = LOCALES[next].dir;
      // Client components read the new value from context on the next render,
      // but anything the server rendered is still in the old language until it
      // is asked again. `refresh()` re-runs those without losing form state or
      // scroll position, which a reload would.
      router.refresh();
    },
    [router]
  );

  const value = useMemo<Value>(
    () => ({ locale: initial, setLocale, t: makeT(initial) }),
    [initial, setLocale]
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useLocale() {
  return useContext(Ctx);
}

/// `const t = useT()` — then `t("moment.six")`.
export function useT(): T {
  return useContext(Ctx).t;
}
