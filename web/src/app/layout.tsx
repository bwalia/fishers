import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Barlow, Barlow_Condensed, Noto_Sans_Gurmukhi } from "next/font/google";
import "./globals.css";
import { OfflineReady } from "@/components/OfflineReady";
import { ShellNav } from "@/components/ShellNav";
import { MobileNav } from "@/components/MobileNav";
import { LiveAlerts } from "@/components/LiveAlerts";
import { LOCALES, makeT } from "@/lib/i18n";
import { getLocale } from "@/lib/i18n/server";
import { LocaleProvider } from "@/lib/i18n/provider";
import { brand } from "@/brand.generated";
import { siteUrl } from "@/lib/site";

// next/font self-hosts and sets font-display: swap, so no FOIT and no layout
// shift waiting on Google.
const barlow = Barlow({
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700"],
  variable: "--font-barlow",
});
const barlowCondensed = Barlow_Condensed({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-barlow-condensed",
});

// Barlow carries no Gurmukhi, so Punjabi in it is a row of tofu boxes. The
// stylesheet puts this in front of Barlow only under `html[lang="pa"]`, and
// `preload: false` is what keeps that from costing every other reader a font
// download: the @font-face is declared on every page, but a browser fetches a
// font file only when something rendered actually needs a glyph from it.
const gurmukhi = Noto_Sans_Gurmukhi({
  subsets: ["gurmukhi", "latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-gurmukhi",
  preload: false,
});

/// What a crawler, a link preview and a browser tab are told.
///
/// `metadataBase` is the one that cannot be skipped: without it every
/// canonical and every OpenGraph image resolves relative to nothing, and
/// Next quietly falls back to localhost — which is the URL that then ends up
/// in a shared link. It comes from the ring rather than the brand, because
/// int.fishers.cloud claiming www.fishers.cloud as its canonical is how a
/// test ring gets production de-indexed.
///
/// No `title.template` on purpose: every page here already ends its own title
/// with the brand, and a template would make that "Privacy — Fishers — Fishers".
export const metadata: Metadata = {
  metadataBase: new URL(siteUrl()),
  title: `${brand.name} — ${brand.tagline}`,
  description: brand.description,
  applicationName: brand.name,
  // No `alternates.canonical` and no `openGraph.url` here, however much they
  // look like they belong: a route that does not set its own inherits this
  // one, and every page on the site then declared `/` as its canonical —
  // which is how you ask Google to index one page and throw the rest away.
  // Without the tag a crawler self-canonicalises, which is the right answer
  // everywhere; the pages worth pinning set their own below.
  openGraph: {
    type: "website",
    siteName: brand.name,
    title: `${brand.name} — ${brand.tagline}`,
    description: brand.description,
  },
  twitter: {
    card: "summary_large_image",
    title: `${brand.name} — ${brand.tagline}`,
    description: brand.description,
  },
};

export const viewport = {
  width: "device-width",
  initialScale: 1,
  // The browser chrome follows the theme, so a dark phone does not frame a
  // cream page in a light bar.
  // From the brand: the chrome is painted from metadata rather than from the
  // stylesheet, so a literal here would frame another brand's page in Fishers'
  // cream.
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: brand.themeLight },
    { media: "(prefers-color-scheme: dark)", color: brand.themeDark },
  ],
};

/// Applied before the first paint.
///
/// Without this the page renders in the system theme and then swaps to the
/// chosen one — a white flash on a dark phone, every navigation.
const THEME_BOOT = `try{var t=localStorage.getItem('fishers_theme');
if(t==='dark'||t==='light')document.documentElement.setAttribute('data-theme',t);}catch(e){}`;

export default async function RootLayout({ children }: { children: ReactNode }) {
  // Read before the first paint, so the page arrives in the reader's language
  // rather than arriving in English and correcting itself.
  //
  // This costs the whole tree its static prerender — `cookies()` is a dynamic
  // API, so every route became server-rendered-per-request, 24 of which used
  // to be prerendered (`/`, `/login`, `/privacy`, `/tour` among them). That is
  // a deliberate trade and not an oversight:
  //
  //   - the alternative that keeps the prerender is to leave the locale to the
  //     client, which means the cached HTML is English and every page visibly
  //     corrects itself on hydration. For a feature whose entire point is that
  //     a Punjabi speaker reads Punjabi, a flash of English on every load is
  //     the wrong thing to optimise away.
  //   - what was lost is a cached string, not the HTML itself: these pages are
  //     still server-rendered, so nothing about SEO or first paint changes
  //     beyond rendering a small tree per request on a Node server that is
  //     already running.
  //
  // The way to have both is `[locale]` route segments, which Next can
  // prerender once per language. That is a restructure of all thirty route
  // groups and is the upgrade path if these pages ever need the cache back.
  const locale = await getLocale();
  const t = makeT(locale);

  return (
    // `suppressHydrationWarning` belongs here and only here: THEME_BOOT sets
    // `data-theme` on this element before React hydrates, so the server HTML
    // and the client tree differ by exactly that attribute — on purpose, since
    // the alternative is a flash of the wrong theme on every navigation. It
    // suppresses one level, so nothing inside is affected.
    <html
      lang={locale}
      dir={LOCALES[locale].dir}
      className={`${barlow.variable} ${barlowCondensed.variable} ${gurmukhi.variable}`}
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOT }} />
      </head>
      <body>
        <LocaleProvider initial={locale}>
          <a className="skip-link" href="#main">{t("nav.skip")}</a>
          <OfflineReady />
          <ShellNav />
          <div className="shell">{children}</div>
          <MobileNav />
          <LiveAlerts />
        </LocaleProvider>
      </body>
    </html>
  );
}
