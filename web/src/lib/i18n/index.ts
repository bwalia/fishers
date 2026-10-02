import { en, type Dict, type Key } from "./en";
import { pa } from "./pa";

export type { Key, Dict };
export { en };

/// The languages the product speaks.
///
/// `native` is the name in its own script and is never translated — a picker
/// that says "Punjabi" in English is no use to the person who needs it.
///
/// `dir` is here from the start so that adding Urdu is a row in this table
/// plus a stylesheet pass, not a refactor of every component. Nothing RTL is
/// listed yet: `globals.css` uses physical `margin-left`/`left:` in 99 places
/// and logical properties in none, so an RTL language added today would lay
/// out mirrored-but-wrong. That pass is its own piece of work.
export const LOCALES = {
  en: { native: "English", dir: "ltr", script: "latin" },
  pa: { native: "ਪੰਜਾਬੀ", dir: "ltr", script: "gurmukhi" },
} as const;

export type Locale = keyof typeof LOCALES;

export const DEFAULT_LOCALE: Locale = "en";

/// Written by the picker, read by the server before the first paint. A cookie
/// rather than `localStorage` for exactly that reason: `layout.tsx` is a
/// server component and has to put the right `lang` on `<html>` in the first
/// response, and it cannot see `localStorage`.
export const LOCALE_COOKIE = "fishers_lang";

const DICTS: Record<Locale, Dict> = { en, pa };

export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && value in LOCALES;
}

/// A locale from anything untrusted — a cookie, a header, a query string.
export function localeFrom(value: string | undefined | null): Locale {
  if (!value) return DEFAULT_LOCALE;
  const tag = value.trim().toLowerCase();
  if (isLocale(tag)) return tag;
  // "pa-IN" and "pa_Guru_IN" are both Punjabi as far as this product cares.
  const base = tag.split(/[-_]/)[0];
  return isLocale(base) ? base : DEFAULT_LOCALE;
}

/// The best we can do from an `Accept-Language` header, for a first visit with
/// no cookie yet. Quality values are honoured, so `en;q=0.8, pa` is Punjabi.
export function localeFromAcceptLanguage(header: string | undefined | null): Locale {
  if (!header) return DEFAULT_LOCALE;
  const ranked = header
    .split(",")
    .map((part) => {
      const [tag, ...params] = part.split(";").map((s) => s.trim());
      const q = params
        .map((p) => /^q=([\d.]+)$/i.exec(p))
        .find(Boolean);
      return { tag, q: q ? Number(q[1]) : 1 };
    })
    .filter((x) => x.tag && Number.isFinite(x.q))
    .sort((a, b) => b.q - a.q);
  for (const { tag } of ranked) {
    const base = tag.split(/[-_]/)[0].toLowerCase();
    if (isLocale(base)) return base;
  }
  return DEFAULT_LOCALE;
}

export type Vars = Record<string, string | number>;

/// The stem of a plural pair: `outcome.runs` for `outcome.runs.one` and
/// `outcome.runs.other`. Derived from the dictionary, so a stem is only
/// accepted where both forms actually exist.
export type PluralBase<K extends string = Key> = K extends `${infer B}.one` ? B : never;

/// What `t` will accept: any key, or the stem of a plural pair.
export type AnyKey = Key | PluralBase;

/// Two plural forms, chosen the way English and every language carried here
/// chooses them. A language with more forms — Arabic's six, Welsh's four —
/// needs this to grow a per-locale rule before it is added to `LOCALES`, and
/// would read wrong rather than fail loudly, which is why it is called out.
function resolve(key: AnyKey, count: number | undefined): Key {
  if (typeof count === "number") {
    const form = `${key}.${count === 1 ? "one" : "other"}` as Key;
    if (form in en) return form;
  }
  if (key in en) return key as Key;
  // A plural stem used without a count. The general form beats printing the
  // stem itself onto the page.
  const other = `${key}.other` as Key;
  return other in en ? other : (key as Key);
}

/// The translator for one language.
///
/// Falls back to English per key, not per dictionary: a language that is 90%
/// done shows 90% of itself and English for the rest, which is a gap a reader
/// can live with. Falling back to the key would put `moment.hat_trick` on a
/// live scoreboard.
export function makeT(locale: Locale) {
  const dict = DICTS[locale] ?? en;
  return function t(key: AnyKey, vars?: Vars): string {
    const form = resolve(key, typeof vars?.count === "number" ? vars.count : undefined);
    let out: string = dict[form] ?? en[form] ?? form;
    if (vars) {
      for (const [name, value] of Object.entries(vars)) {
        out = out.replaceAll(`{${name}}`, String(value));
      }
    }
    return out;
  };
}

export type T = ReturnType<typeof makeT>;

/// A translator for code that is neither a component nor a server component —
/// `api.ts` throwing a session error, for instance, where threading `t` down
/// from a caller would mean changing every call in the app.
///
/// Reads the same cookie the provider writes, so it agrees with what is on
/// screen. Off the browser there is no cookie to read and it falls back to
/// English; anything rendered belongs in `useT`/`getT`, which do see the
/// request.
export function clientT(): T {
  if (typeof document === "undefined") return makeT(DEFAULT_LOCALE);
  const match = document.cookie.match(new RegExp(`(?:^|; )${LOCALE_COOKIE}=([^;]*)`));
  return makeT(localeFrom(match ? decodeURIComponent(match[1]) : null));
}
