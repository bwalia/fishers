import type { ReactNode } from "react";
import { Barlow, Barlow_Condensed } from "next/font/google";
import "./globals.css";
import { ShellNav } from "@/components/ShellNav";

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

export const metadata = {
  title: "Fishers — Club dashboard",
  description: "Fixtures, live cricket scoring, club stats and shop",
};

export const viewport = {
  width: "device-width",
  initialScale: 1,
  // The browser chrome follows the theme, so a dark phone does not frame a
  // cream page in a light bar.
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f7f4ed" },
    { media: "(prefers-color-scheme: dark)", color: "#111712" },
  ],
};

/// Applied before the first paint.
///
/// Without this the page renders in the system theme and then swaps to the
/// chosen one — a white flash on a dark phone, every navigation.
const THEME_BOOT = `try{var t=localStorage.getItem('fishers_theme');
if(t==='dark'||t==='light')document.documentElement.setAttribute('data-theme',t);}catch(e){}`;

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={`${barlow.variable} ${barlowCondensed.variable}`}>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOT }} />
      </head>
      <body>
        <a className="skip-link" href="#main">Skip to main content</a>
        <div className="shell">
          <ShellNav />
          {children}
        </div>
      </body>
    </html>
  );
}
