import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  Children,
  cloneElement,
  Fragment,
  isValidElement,
  type ReactElement,
  type ReactNode,
} from "react";
import { brand } from "@/brand.generated";
import { getLocale, getT } from "@/lib/i18n/server";
import { formatDate, postBySlug } from "@/lib/blog";
import { siteUrl } from "@/lib/site";
import { AppStoreBadge } from "@/components/AppStoreBadge";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const post = postBySlug(slug);
  if (!post) return {};
  return {
    title: `${post.title} — ${brand.name}`,
    description: post.summary,
    alternates: { canonical: `/blog/${post.slug}` },
    openGraph: { type: "article", title: post.title, description: post.summary, publishedTime: post.date },
  };
}

/// The words inside a node, for turning a heading into an anchor.
function textOf(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textOf).join("");
  if (isValidElement(node)) return textOf((node.props as { children?: ReactNode }).children);
  return "";
}

const anchor = (text: string) =>
  text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");

/// Reads a post body once: puts an id on every h2, and says what it found.
///
/// The contents list and the anchors it points at come from the same walk, so
/// they cannot disagree. The alternative — a `sections` field beside the body
/// — is the same list written twice, and wrong the first time somebody edits a
/// heading and not the copy of it.
function sectioned(body: ReactNode): { toc: { id: string; text: string }[]; body: ReactNode } {
  const toc: { id: string; text: string }[] = [];
  const walk = (nodes: ReactNode): ReactNode =>
    Children.map(nodes, (node) => {
      if (!isValidElement(node)) return node;
      // A post body is one fragment, so the headings are a level down.
      if (node.type === Fragment) return walk((node.props as { children?: ReactNode }).children);
      if (node.type !== "h2") return node;
      const text = textOf((node.props as { children?: ReactNode }).children);
      const id = anchor(text);
      toc.push({ id, text });
      return cloneElement(node as ReactElement<{ id?: string }>, { id });
    });
  return { toc, body: walk(body) };
}

export default async function BlogPostPage({ params }: Props) {
  const { slug } = await params;
  const post = postBySlug(slug);
  if (!post) notFound();
  const t = await getT();
  const locale = await getLocale();

  const url = siteUrl();
  const { toc, body } = sectioned(post.body());

  return (
    <main id="main" className="post">
      {/* A post, for the result rather than for the page. `BlogPosting` is
          what puts a date beside the headline in search; without it a launch
          announcement reads as the same age forever, and an announcement that
          looks undated is one nobody clicks. Author and publisher are both the
          organisation on purpose — these are company posts, and inventing a
          person to sign them would be a fabricated entity in structured data. */}
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify({
            "@context": "https://schema.org",
            "@type": "BlogPosting",
            headline: post.title,
            description: post.summary,
            datePublished: post.date,
            dateModified: post.date,
            mainEntityOfPage: `${url}/blog/${post.slug}`,
            image: `${url}/icon-192.png`,
            inLanguage: locale,
            author: { "@id": `${url}/#organization` },
            publisher: { "@id": `${url}/#organization` },
          }),
        }}
      />

      {/* A band rather than a column: the title is the widest thing on the
          page and the only one that should be. Everything below it sets its
          own measure. */}
      <header className="post-hero">
        <div className="post-hero-in">
          <Link href="/blog" className="post-back">
            <span aria-hidden="true">←</span> {t("blog.back")}
          </Link>
          <div className="post-head">
            <div className="post-head-text">
              <time dateTime={post.date} className="post-date">
                {formatDate(post.date, locale)}
              </time>
              <h1>{post.title}</h1>
              <p className="post-lede">{post.summary}</p>
            </div>
            <div className="post-head-app">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img className="post-icon" src="/icon-192.png" width={128} height={128} alt="" />
              <AppStoreBadge label={t("app.download", { brand: brand.name })} height={52} />
            </div>
          </div>
        </div>
      </header>

      <div className="post-main">
        <article className="post-body prose">{body}</article>
        {/* After the article in the source, so a reader on a phone meets the
            post and not its furniture, and a screen reader reaches the same
            two in the same order. The grid puts it alongside on a wide
            window; the contents list is for that window and hides below it,
            where four headings are a scroll rather than a navigation. */}
        <aside className="post-aside">
          {toc.length > 1 && (
            <nav className="post-toc" aria-labelledby="post-toc-h">
              <h2 id="post-toc-h">{t("blog.contents")}</h2>
              <ol>
                {toc.map((section) => (
                  <li key={section.id}>
                    <a href={`#${section.id}`}>{section.text}</a>
                  </li>
                ))}
              </ol>
            </nav>
          )}
          <div className="post-get">
            <p>{t("app.banner", { brand: brand.name })}</p>
            <AppStoreBadge label={t("app.download", { brand: brand.name })} height={48} />
          </div>
        </aside>
      </div>
    </main>
  );
}
