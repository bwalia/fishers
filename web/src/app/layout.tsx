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
  themeColor: "#1b7f4c",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={`${barlow.variable} ${barlowCondensed.variable}`}>
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
