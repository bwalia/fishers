//! Serves OpenAPI YAML and Swagger UI for the Fishers API.

use axum::response::{Html, IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};

use crate::state::AppState;

const OPENAPI_YAML: &str = include_str!("../openapi.yaml");

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/swagger-ui", get(swagger_ui))
        .route("/swagger-ui/", get(swagger_ui))
        .route("/api-docs/openapi.yaml", get(openapi_yaml))
        .route("/api-docs/openapi.json", get(openapi_json_redirect_hint))
}

async fn openapi_yaml() -> Response {
    (
        [(
            axum::http::header::CONTENT_TYPE,
            "application/yaml; charset=utf-8",
        )],
        OPENAPI_YAML,
    )
        .into_response()
}

/// Soft hint — canonical spec is YAML; some tools prefer this URL.
async fn openapi_json_redirect_hint() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "message": "Use /api-docs/openapi.yaml (OpenAPI 3.1)",
        "yaml": "/api-docs/openapi.yaml",
        "ui": "/swagger-ui"
    }))
}

async fn swagger_ui() -> Html<&'static str> {
    Html(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Fishers API — Swagger</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui.css"/>
  <style>
    body { margin: 0; background: #ffffff; }
    .swagger-ui { background: #ffffff; }
    .topbar { display: none; }
    .swagger-ui .info .title { color: #1a7f4b; }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui-bundle.js"></script>
  <script>
    window.ui = SwaggerUIBundle({
      url: '/api-docs/openapi.yaml',
      dom_id: '#swagger-ui',
      deepLinking: true,
      presets: [SwaggerUIBundle.presets.apis],
      layout: 'BaseLayout',
      tryItOutEnabled: true,
      persistAuthorization: true
    });
  </script>
</body>
</html>"#,
    )
}
