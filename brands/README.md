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
3. Drop the logo and icons in `brands/<id>/`.
4. Add `devops/helm-charts/fishers-web/values-<id>-<ring>.yaml`.

The mobile apps take the same file: Android as a product flavour, iOS as an
xcconfig. Each brand is its own listing, its own bundle id and its own icon.
