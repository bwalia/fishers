/**
 * The Helm values a brand needs for one ring.
 *
 * Each brand is its own stack — its own namespace, its own API, its own
 * database — so this is a whole values file rather than an overlay. Generated
 * so that adding a brand is a YAML file and a command, not a morning of
 * copying somebody else's and missing one line.
 */
export function helmValues(brand, ring) {
  const host = brand.rings[ring];
  const release = `${brand.id}-${ring}`;
  return `# ${ring} — generated from brands/${brand.id}.yaml. Do not edit.
#
# Each brand is a separate stack with its own database. Nothing here is shared
# with another brand at runtime, which is why this is a whole values file and
# not an overlay on somebody else's.

env: ${ring}
brand: ${brand.id}
hostname: ${host}
namespace: ${release}
replicaCount: ${ring === "prod" ? 2 : 1}

image:
  repository: int-spectoncr.diytaxreturn.co.uk/${brand.id}/${brand.id}-web
  tag: latest

# The brand is baked in at build time, so the image for one brand cannot serve
# another. That is deliberate: a runtime switch is a way to serve the wrong
# logo to a whole region after one bad environment variable.
build:
  brand: ${brand.id}

ingress:
  enabled: true
  className: traefik
  host: ${host}
  tls:
    enabled: true
    secretName: ${release}-tls

resources:
  requests:
    cpu: ${ring === "prod" ? "100m" : "50m"}
    memory: ${ring === "prod" ? "256Mi" : "128Mi"}
  limits:
    memory: ${ring === "prod" ? "1Gi" : "512Mi"}
`;
}
