# Brands

One file per brand. Everything a frontend needs to become that brand lives
here; the backends are separate deployments with separate databases, so
nothing in this directory is shared at runtime.

A brand file is read at **build time** by `scripts/brand.mjs`, which writes
the generated CSS, the TypeScript constants, the Android resources and the
iOS xcconfig. Nothing generated is committed — it comes from here, and code
that lives in the repo drifts from the source it was generated from.

## The colours are not decoration

The palette is four source colours and a ramp darkened from them until the
ramp carries text. That is not a style choice. Sage `#8FA28A` on white is
**2.7:1** — unreadable, and a failure of WCAG AA — so it is darkened to
`#667964`, which is 4.68:1 and passes.

A new brand has to do the same. `npm run brand:check` computes every
foreground/background pair a screen actually uses and fails the build if one
is under 4.5:1. A brand whose text nobody can read is not a brand, it is a
support queue.

## Adding one

1. Copy `fishers.yaml`, change the name, domain and the four source colours.
2. Run `npm run brand:check -- <id>` and darken the ramp until it passes.
3. Put the icons in `brands/<id>/`: `icon-192.png` and `badge.png`. They are
   required — a build refuses rather than falling back, because a fallback
   means shipping somebody else's mark under a different name.
4. Add `devops/helm-charts/fishers-web/values-<id>-<ring>.yaml`.

The mobile apps take the same file: Android as a product flavour, iOS as an
xcconfig. Each brand is its own listing, its own bundle id and its own icon.

## What a brand actually gets

A brand is a whole stack, not a skin. Each has its own namespace, its own API,
its own database and its own Play and App Store listing. Nothing is shared at
runtime — a GullyCricket club is not in Fishers' database and never appears in
its search.

| | Fishers | GullyCricket |
|---|---|---|
| Web | int.fishers.cloud | int.gullycricket.app |
| Namespace | `fishers-int` | `gullycricket-int` |
| Android | `com.fishers.app` | `app.gullycricket` |
| iOS | `com.fishers.app` | `app.gullycricket` |

## Where it is read

| What | Reads it as |
|---|---|
| Web | `brand.generated.ts` and `brand.generated.css`, written by `prebuild` |
| Android | a product flavour, its resources generated per variant |
| iOS | an xcconfig and `Brand.generated.swift`, selected by the scheme |
| Helm | an overlay applied after the ring's own values |
| CD | a matrix — one push to main deploys every brand |

## What a brand supplies

| File | Size | Used for |
|---|---|---|
| `brands/<id>.yaml` | — | name, domain, rings, palette, bundle id |
| `brands/<id>/icon-192.png` | 192×192 | the app icon and the web manifest |
| `brands/<id>/badge.png` | 96×96 | the notification badge |

GullyCricket's icons are **provisional** — a ring and a letter in its own
colour, generated so the pipeline could be proven end to end. They are not a
logo and should be replaced before anybody sees them.

## Commands

```bash
node tools/brand/index.mjs list                    # which brands exist
node tools/brand/index.mjs check                   # every brand readable?
node tools/brand/index.mjs check gullycricket      # just this one
node tools/brand/index.mjs generate fishers        # all targets
node tools/brand/index.mjs generate fishers --web  # just the web
node tools/brand/index.mjs host gullycricket prod  # www.gullycricket.app
node tools/brand/index.mjs namespace fishers int   # fishers-int
```

`cd web && BRAND=gullycricket npm run dev` runs the dashboard as GullyCricket.
`./gradlew assembleGullycricketDebug` builds its app.
