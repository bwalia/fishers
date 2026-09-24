/**
 * The Helm values that differ by brand, and nothing else.
 *
 * Deliberately an overlay rather than a whole file. The ring's own values —
 * image, resources, replica count — are the same decisions whichever brand is
 * being deployed, and duplicating them per brand is how two files drift until
 * one ring is a version behind.
 *
 * Whether Kong is in front is not one of those. It reads like a ring-wide
 * decision and it is not: the gateway's Service lives in the brand's own
 * namespace and is deployed per brand, so only the brand file knows both the
 * ring and whether that ring's gateway exists. Treating it as ring-wide is
 * what sent GullyCricket's /api, /swagger-ui and /health at Fishers' proxy,
 * which does not exist in its namespace — Traefik dropped all three and
 * answered 404.
 *
 * Helm applies `-f` in order, so this goes last:
 *
 *   helm upgrade ... -f values-int.yaml -f <this>
 */
export function helmValues(brand, ring) {
  const host = brand.rings[ring];
  if (!host) {
    throw new Error(
      `${brand.name} has no "${ring}" ring. It has: ${Object.keys(brand.rings).join(", ")}`,
    );
  }
  // Only what the chart actually reads. A value nobody consumes is worse than
  // no value: the TLS secret is named from the chart and isolated by the
  // namespace already, so setting it here would look like it mattered.
  const gateway = brand.gateway.includes(ring);
  return `# ${ring} — generated from brands/${brand.id}.yaml by tools/brand. Do not edit.
#
# Only what differs by brand. The ring's own values file carries everything
# else, because image, resources and replicas are the same decisions whichever
# brand is being deployed — and two files that repeat each other drift until
# one ring is a version behind.

brand: ${brand.id}
hostname: ${host}

# ${
    gateway
      ? `This ring has its own gateway: kong-${brand.id}-${ring}-kong-proxy.`
      : `No gateway on this ring, so /api, /swagger-ui and /health go straight
# at fishers-api. Naming one that is not deployed is not a louder failure than
# this — it is a quieter one, because Traefik drops the paths and 404s.`
  }
kong:
  enabled: ${gateway}
`;
}

/** Where a brand's ring answers. Used by the deploy workflow. */
export function hostFor(brand, ring) {
  const host = brand.rings[ring];
  if (!host) {
    throw new Error(
      `${brand.name} has no "${ring}" ring. It has: ${Object.keys(brand.rings).join(", ")}`,
    );
  }
  return host;
}

/**
 * The namespace a brand's ring lives in.
 *
 * `<brand>-<ring>`, which for Fishers is `fishers-int` — exactly what it has
 * always been, so nothing moves. A new brand gets its own, which is what keeps
 * two brands' databases apart on one cluster.
 */
export function namespaceFor(brand, ring) {
  hostFor(brand, ring); // rejects an unknown ring with a readable message
  return `${brand.id}-${ring}`;
}

/**
 * Every hostname a ring answers on, for DNS and the edge vhost.
 *
 * Prod carries the apex as well as `www`, because somebody typing the domain
 * without it has to arrive somewhere. The apex is an A record at the zone
 * root: a CNAME cannot coexist with one, so Cloudflare refuses the upsert and
 * takes the whole deploy down with it. It needs the vhost for its own
 * certificate and nothing else — which is why [dnsHostsFor] leaves it out.
 */
export function edgeHostsFor(brand, ring) {
  const host = hostFor(brand, ring);
  return ring === "prod" ? [host, brand.domain] : [host];
}

/** The hosts that get a CNAME — everything but the apex. */
export function dnsHostsFor(brand, ring) {
  return edgeHostsFor(brand, ring).filter((h) => h !== brand.domain);
}

/** The Cloudflare zone a brand's records live in. */
export function zoneFor(brand) {
  return brand.domain;
}
