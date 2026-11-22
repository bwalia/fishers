import { join } from "node:path";
import { edgeHostsFor, pinFor } from "../helm.mjs";

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
 *
 * Except for a ring pinned to one node (brands/<brand>.yaml `placement`): the
 * home cluster's Traefik can't reach pods on the edge nodes, so that ring's
 * hosts get a rule of their own, sending them straight to the node.
 */
const SHARED_RULE = "fishers-prod-default";

export function wslproxyFiles(brand, repoRoot, outDir) {
  const dir = outDir ?? join(repoRoot, "devops", "wslproxy");
  const rings = Object.keys(brand.rings);
  const ruleOf = new Map();
  const files = [];
  for (const ring of rings) {
    const pin = pinFor(brand, ring);
    const rule = pin ? pinnedRule(brand, ring, pin) : null;
    if (rule) files.push({ path: join(dir, `rule-${rule.id}.json`), contents: `${JSON.stringify(rule, null, 2)}\n` });
    for (const host of edgeHostsFor(brand, ring)) if (!ruleOf.has(host)) ruleOf.set(host, rule?.id ?? SHARED_RULE);
  }
  return [
    ...[...ruleOf].map(([host, rule]) => ({
      path: join(dir, `host-${host}.json`),
      contents: `${JSON.stringify(spec(brand, host, rule), null, 2)}\n`,
    })),
    ...files,
  ];
}

/** The same shape as fishers-prod-default, with the node as the one backend. */
function pinnedRule(brand, ring, pin) {
  const id = `${brand.id}-${ring}-${pin.node}`;
  const backend = `${pin.address}:80`;
  return {
    id,
    name: id,
    profile_id: "prod",
    priority: 1,
    rules_tags: [brand.id, ring],
    match: {
      rules: { path: "/", path_key: "starts_with" },
      response: {
        strip_path: false,
        code: 305,
        routing: { mode: "least_conn" },
        backends: [
          {
            weight: 100,
            address: backend,
            label: `${pin.node}'s traefik-edge (hostNetwork, :80). ${brand.name} ${ring} runs wholly on that node — brands/${brand.id}.yaml placement.`,
          },
        ],
        redirect_uri: backend,
      },
    },
    servers: edgeHostsFor(brand, ring).map((h) => `host:${h}`),
  };
}

function spec(brand, host, rule) {
  return {
    id: `host:${host}`,
    server_name: host,
    proxy_server_name: host,
    rules: rule,
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
