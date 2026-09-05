const API_ORIGIN =
  process.env.NEXT_PUBLIC_API_BASE?.replace(/\/$/, "") || "http://127.0.0.1:8080";

export default function DocsPage() {
  const swagger = `${API_ORIGIN}/swagger-ui`;
  const yaml = `${API_ORIGIN}/api-docs/openapi.yaml`;

  return (
    <main>
      <section className="hero">
        <h1>API documentation</h1>
        <p>
          Interactive Swagger UI is served by the Fishers API. Open it in a new tab to try
          endpoints with your JWT.
        </p>
      </section>
      <div className="panel">
        <p>
          <a className="btn primary" href={swagger} target="_blank" rel="noreferrer">
            Open Swagger UI
          </a>
        </p>
        <p className="muted" style={{ marginTop: 16 }}>
          Spec: <a href={yaml}>{yaml}</a>
        </p>
      </div>
    </main>
  );
}
