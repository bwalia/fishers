import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { brand } from "@/brand.generated";
import { getLocale, getT } from "@/lib/i18n/server";
import { formatDate, postBySlug } from "@/lib/blog";
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

  return (
    <main id="main">
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
