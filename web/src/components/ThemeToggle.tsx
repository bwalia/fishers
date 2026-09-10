"use client";

import { useEffect, useState } from "react";

type Choice = "system" | "light" | "dark";

/// Day, night, or whatever the device says.
///
/// The choice is written to `data-theme` on the root, which the stylesheet
/// honours over `prefers-color-scheme` in both directions — so picking light on
/// a device set to dark actually gives you light, which a media query alone
/// cannot do.
export function ThemeToggle() {
  const [choice, setChoice] = useState<Choice>("system");

  useEffect(() => {
    setChoice((localStorage.getItem("fishers_theme") as Choice) ?? "system");
  }, []);

  const apply = (next: Choice) => {
    setChoice(next);
    localStorage.setItem("fishers_theme", next);
    const root = document.documentElement;
    if (next === "system") root.removeAttribute("data-theme");
    else root.setAttribute("data-theme", next);
  };

  // Cycles rather than opening a menu: it is one control in a crowded bar, and
  // the label says where the next tap lands.
  const next: Choice = choice === "system" ? "light" : choice === "light" ? "dark" : "system";
  const label = { system: "Match my device", light: "Light", dark: "Dark" }[choice];

  return (
    <button
      type="button"
      className="theme-toggle"
      onClick={() => apply(next)}
      title={`Theme: ${label}. Tap for ${next === "system" ? "your device setting" : next}.`}
      aria-label={`Theme: ${label}. Change to ${next === "system" ? "match my device" : next}.`}
    >
      {choice === "dark" ? <MoonIcon /> : choice === "light" ? <SunIcon /> : <AutoIcon />}
    </button>
  );
}

const stroke = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.6,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

function SunIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden>
      <circle cx="12" cy="12" r="4" {...stroke} />
      <path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4" {...stroke} />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden>
      <path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z" {...stroke} />
    </svg>
  );
}

/// Half sun, half moon — the usual mark for "follow the device".
function AutoIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden>
      <circle cx="12" cy="12" r="8" {...stroke} />
      <path d="M12 4a8 8 0 0 0 0 16Z" fill="currentColor" />
    </svg>
  );
}
