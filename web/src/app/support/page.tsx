import type { Metadata } from "next";
import Link from "next/link";
import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getT();
  return {
    title: `${t("sup.support")} — ${brand.name}`,
    description: t("sup.description", { brand: brand.name }),
    alternates: { canonical: "/support" },
  };
}

/// The page App Store Connect links to as the support URL, which is a required
/// field — a listing cannot be submitted without one. Static for the same
/// reason the privacy policy is: somebody who cannot get in is exactly the
/// person reading this, so it must not need the API up to render.
export default async function SupportPage() {
  const t = await getT();
  const questions = [
    ["sup.q_join", "sup.a_join"],
    ["sup.q_signin", "sup.a_signin"],
    ["sup.q_score", "sup.a_score"],
    ["sup.q_language", "sup.a_language"],
    ["sup.q_delete", "sup.a_delete"],
  ] as const;

  return (
    <main id="main">
      <section className="hero">
        <h1>{t("sup.support")}</h1>
        <p>{t("sup.intro")}</p>
      </section>

      <div className="panel">
        <h2>{t("sup.write_to_us")}</h2>
        <p>
          <a className="btn primary" href={`mailto:${brand.supportEmail}`}>
            {brand.supportEmail}
          </a>
        </p>
        <p className="muted">{t("sup.reply_time")}</p>
      </div>

      <div className="panel prose">
        <h2>{t("sup.questions")}</h2>
        <dl>
          {questions.map(([question, answer]) => (
            <div key={question}>
              <dt>{t(question)}</dt>
              <dd>{t(answer)}</dd>
            </div>
          ))}
        </dl>
      </div>

      <div className="panel">
        <h2>{t("sup.the_rest")}</h2>
        <nav className="site-foot-col">
          <Link href="/forgot">{t("foot.forgot_password")}</Link>
          <Link href="/profile#delete">{t("foot.delete_account")}</Link>
          <Link href="/privacy">{t("rest.privacy")}</Link>
          <Link href="/terms">{t("foot.terms")}</Link>
        </nav>
      </div>
    </main>
  );
}
