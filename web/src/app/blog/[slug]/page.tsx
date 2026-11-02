import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
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

export default async function BlogPostPage({ params }: Props) {
  const { slug } = await params;
  const post = postBySlug(slug);
  if (!post) notFound();
  const t = await getT();
  const locale = await getLocale();

  const url = siteUrl();

  return (
    <main id="main">
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
      <article className="blog-post">
        <p>
          <Link href="/blog" className="muted">
            ← {t("blog.back")}
          </Link>
        </p>
        <header className="blog-post-head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="blog-post-icon" src="/icon-192.png" width={72} height={72} alt="" />
          <div>
            <h1>{post.title}</h1>
            <time dateTime={post.date} className="muted">
              {formatDate(post.date, locale)}
            </time>
          </div>
        </header>
        <p className="blog-post-lede">{post.summary}</p>
        <AppStoreBadge label={t("app.download", { brand: brand.name })} height={52} />
        <div className="panel prose blog-post-body">{post.body()}</div>
        <div className="blog-post-foot">
          <AppStoreBadge label={t("app.download", { brand: brand.name })} height={52} />
        </div>
      </article>
    </main>
  );
}
