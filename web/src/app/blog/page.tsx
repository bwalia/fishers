import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { brand } from "@/brand.generated";
import { getLocale, getT } from "@/lib/i18n/server";
import { formatDate, postsForBrand } from "@/lib/blog";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getT();
  return {
    title: `${t("blog.title")} — ${brand.name}`,
    description: t("blog.intro", { brand: brand.name }),
    alternates: { canonical: "/blog" },
  };
}

export default async function BlogPage() {
  const posts = postsForBrand();
  // A brand with nothing written has no blog, rather than an empty one.
  if (!posts.length) notFound();
  const t = await getT();
  const locale = await getLocale();

  return (
    <main id="main">
      <section className="hero">
        <h1>{t("blog.title")}</h1>
        <p>{t("blog.intro", { brand: brand.name })}</p>
      </section>

      <ul className="blog-list">
        {posts.map((post) => (
          <li key={post.slug} className="panel blog-card">
            <time dateTime={post.date} className="muted">
              {formatDate(post.date, locale)}
            </time>
            <h2>
              <Link href={`/blog/${post.slug}`}>{post.title}</Link>
            </h2>
            <p>{post.summary}</p>
            <Link href={`/blog/${post.slug}`} className="btn sm">
              {t("blog.read")}
            </Link>
          </li>
        ))}
      </ul>
    </main>
  );
}
