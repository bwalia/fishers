# The dashboard — Next.js, built as one brand.
#
# The build context is the repo root, not web/, because the brand lives in
# brands/<id>.yaml and is turned into code by tools/brand. The brand is baked
# in: an image is Fishers or it is GullyCricket, and which one is a build
# argument rather than a runtime switch. A runtime switch is how a whole region
# gets served the wrong logo after one bad environment variable.
#
# NEXT_PUBLIC_* values are inlined into the client bundle at build time, so
# anything the browser reads has to be a build arg, not a runtime env var. That
# is the whole reason api.ts derives the API origin from the page's own
# hostname by default: one image then serves every environment, and int / test
# / acc / prod differ only in which host it is reached on.
#
# The one exception is a split-host deployment, where the API is not on the
# page's own origin. Pass NEXT_PUBLIC_API_BASE then, and accept an image per
# environment. The default here leaves it unset.

FROM node:22-alpine AS deps
WORKDIR /app
COPY web/package.json web/package-lock.json ./
# `npm ci` from the lockfile: a build must not be free to resolve a different
# tree from the one that was tested.
RUN npm ci --no-audit --no-fund

FROM node:22-alpine AS build
WORKDIR /app

# Which brand this image is. Nothing downstream can change it.
ARG BRAND=fishers
ENV BRAND=$BRAND

# The tool and the brand files, then its one dependency. Copied before the app
# so a change to a page does not reinstall them.
COPY tools/brand /brand-tool
COPY brands /brands
RUN cd /brand-tool && npm ci --omit=dev --no-audit --no-fund

COPY --from=deps /app/node_modules ./node_modules
COPY web/ ./

# Same-origin by default; set only for a split-host deployment.
ARG NEXT_PUBLIC_API_BASE=""
ENV NEXT_PUBLIC_API_BASE=$NEXT_PUBLIC_API_BASE
ENV NEXT_TELEMETRY_DISABLED=1

# Generate the brand, then build. Run here rather than through `prebuild` so
# the failure — if the brand is unreadable or missing — names itself instead of
# arriving as an npm lifecycle error six frames deep.
RUN node /brand-tool/index.mjs generate "$BRAND" --web --out=/app \
    && npm run build:next

FROM node:22-alpine AS runtime
WORKDIR /app

RUN apk add --no-cache curl \
    && addgroup -g 10001 -S fishers \
    && adduser -u 10001 -S fishers -G fishers

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME="::"

# standalone carries its own trimmed node_modules and server.js; static/ and
# public/ are not included in it and have to come across separately.
COPY --from=build --chown=10001:10001 /app/.next/standalone ./
COPY --from=build --chown=10001:10001 /app/.next/static ./.next/static
COPY --from=build --chown=10001:10001 /app/public ./public

USER 10001

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT}/login" -o /dev/null || exit 1

CMD ["node", "server.js"]
