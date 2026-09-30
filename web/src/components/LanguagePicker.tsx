"use client";

import { Icon } from "@/components/Icon";
import { OverflowMenu } from "@/components/OverflowMenu";
import { LOCALES, type Locale } from "@/lib/i18n";
import { useLocale } from "@/lib/i18n/provider";

/// Pick the language the product speaks to you in.
///
/// Every name is written in its own script — ਪੰਜਾਬੀ, not "Punjabi". Somebody
/// who needs this menu may not read the language the menu is currently in,
/// which makes an English list of language names the one version guaranteed
/// not to work.
///
/// A globe, not a flag: a flag makes one country stand in for a language, and
/// Punjabi has no single flag that would not be an argument.
export function LanguagePicker() {
  const { locale, setLocale, t } = useLocale();

  return (
    <OverflowMenu label={t("lang.change")} icon="globe" className="lang-picker">
      {(Object.keys(LOCALES) as Locale[]).map((code) => (
        <button
          key={code}
          type="button"
          role="menuitem"
          className="overflow-item"
          lang={code}
          // `aria-current` rather than a tick alone: the tick is the visual
          // cue, this is the one a screen reader reads.
          aria-current={code === locale ? "true" : undefined}
          onClick={() => code !== locale && setLocale(code)}
        >
          <span className="lang-tick" aria-hidden="true">
            {code === locale ? <Icon name="check" size={16} /> : null}
          </span>
          {LOCALES[code].native}
        </button>
      ))}
    </OverflowMenu>
  );
}
