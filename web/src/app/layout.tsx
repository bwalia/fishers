import type { ReactNode } from "react";
import "./globals.css";
import { ShellNav } from "@/components/ShellNav";

export const metadata = {
  title: "Fishers — Club dashboard",
  description: "Web dashboard for Fishers club activity, fixtures and shop",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <div className="shell">
          <ShellNav />
          {children}
        </div>
      </body>
    </html>
  );
}
