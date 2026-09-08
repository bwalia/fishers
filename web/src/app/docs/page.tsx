"use client";

import { useEffect, useState } from "react";
import { apiOrigin } from "@/lib/api";

export default function DocsPage() {
  // Resolved in the browser, so the links point at the host you are actually on.
  const [origin, setOrigin] = useState("");
  useEffect(() => setOrigin(apiOrigin()), []);
  const swagger = `${origin}/swagger-ui`;
  const yaml = `${origin}/api-docs/openapi.yaml`;

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
