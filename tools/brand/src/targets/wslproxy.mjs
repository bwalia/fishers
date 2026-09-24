import { join } from "node:path";
import { edgeHostsFor } from "../helm.mjs";

/**
 * The edge vhost specs — one per hostname a brand answers on.
 *
 * Generated rather than written by hand. They were a file per host per brand,
 * which is the kind of list somebody adds a brand to three-quarters of: the
 * DNS goes up, the vhost does not, and the edge answers the fallback's
 * self-signed certificate on a domain that looks live.
 *
 * The routing rule is deliberately shared. It says "send this to k3s1's
 * Traefik", and Traefik picks the namespace from the Host header — which is
 * brand-agnostic, and would be the same file copied under a different name.
 */
const SHARED_RULE = "fishers-prod-default";

export function wslproxyFiles(brand, repoRoot, outDir) {
  const dir = outDir ?? join(repoRoot, "devops", "wslproxy");
  const rings = Object.keys(brand.rings);
  const hosts = [...new Set(rings.flatMap((ring) => edgeHostsFor(brand, ring)))];

  return hosts.map((host) => ({
    path: join(dir, `host-${host}.json`),
    contents: `${JSON.stringify(spec(brand, host), null, 2)}\n`,
  }));
}

function spec(brand, host) {
  return {
    id: `host:${host}`,
    server_name: host,
    proxy_server_name: host,
    rules: SHARED_RULE,
    profile_id: "prod",
    ssl_enabled: true,
    ssl_force_https: true,
    ssl_auto_renew: true,
    ssl_staging: false,
    ssl_email: brand.support.sslEmail,
    listens: [{ listen: "80" }],
    match_cases: {},
    config_status: true,
    access_log: `logs/${host}.access.log`,
    error_log: `logs/${host}.error.log`,
  };
}
