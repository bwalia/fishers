# Fishers API — Rust/Axum.
#
# Migrations are compiled in, not shipped alongside: fishers-db calls
# sqlx::migrate!("./migrations"), which embeds the directory at build time and
# replays it on startup. That is why there is no separate migrations image and
# no init container — the binary cannot be newer than its own schema.
#
# reqwest is pinned to rustls-tls in Cargo.toml, so nothing here links OpenSSL
# and the runtime needs only CA certificates.
#
# The toolchain is pinned rather than `latest`: a transitive dependency already
# requires edition2024, so 1.83 fails outright, and a floating tag would move
# that failure from this file to a random future build.

FROM rust:1.90-slim-bookworm AS build

# pkg-config and libssl-dev are NOT needed (rustls). git is, because build
# metadata resolves the workspace from a checkout.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Manifests first so a source-only change reuses the dependency layer. The
# stub main.rs is thrown away by the real build below; it exists so `cargo
# build` has something to compile while it resolves and builds the ~400
# dependency crates, which is the slow half.
COPY Cargo.toml Cargo.lock ./
COPY agent/Cargo.toml       agent/
COPY api/Cargo.toml         api/
COPY db/Cargo.toml          db/
COPY domain/Cargo.toml      domain/
COPY jobs/Cargo.toml        jobs/
COPY notifications/Cargo.toml notifications/
COPY payments/Cargo.toml    payments/
RUN mkdir -p agent/src api/src db/src domain/src jobs/src notifications/src payments/src \
    && echo 'fn main() {}' > api/src/main.rs \
    && for c in agent db domain jobs notifications payments; do echo '' > "$c/src/lib.rs"; done \
    && cargo build --release -p fishers-api \
    && rm -rf agent/src api/src db/src domain/src jobs/src notifications/src payments/src

COPY . .
# Touch the real entrypoints so cargo does not trust the stub's fingerprint.
RUN find . -name '*.rs' -newermt '1 hour ago' -print0 | xargs -0r touch \
    && cargo build --release -p fishers-api \
    && strip target/release/fishers-api

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --create-home fishers

COPY --from=build /src/target/release/fishers-api /usr/local/bin/fishers-api

USER 10001
WORKDIR /home/fishers

# Dual-stack: one listener serves IPv4 and IPv6 alike, which is what the
# cluster's Service and a curl from a debug pod each expect.
ENV API_HOST="[::]" \
    API_PORT=8080 \
    RUST_LOG="fishers_api=info,tower_http=warn,sqlx=warn"

EXPOSE 8080

# Liveness only — /health is a constant. Readiness must use /health/ready,
# which touches the pool; see the chart's readinessProbe.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${API_PORT}/health" || exit 1

ENTRYPOINT ["/usr/local/bin/fishers-api"]
