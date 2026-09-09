# Deploying Fishers

Four rings, one host each, promoted by [Ring Promoter](https://rp.workstation.co.uk/).

| Ring | Host | Builds images? |
|------|------|----------------|
| int  | `int.fishers.cloud`  | yes |
| test | `test.fishers.cloud` | yes |
| acc  | `acc.fishers.cloud`  | no — deploys what int/test built |
| prod | `www.fishers.cloud`  | no — same |

## One host per ring

`int.fishers.cloud` serves the dashboard at `/` and the API at `/api`,
`/swagger-ui` and `/health`. One host per ring means one certificate, one
Cloudflare record and one wslproxy vhost — and, because the browser never
leaves the origin it loaded, no CORS configuration to keep in step across four
environments.

It also means the dashboard image is environment-agnostic. `api.ts` derives the
API origin from the page's own hostname, so the same image serves all four
rings and there is no build-time host to go stale. That is the same property
that makes `scripts/start.sh` work on a LAN address.

The iOS app takes its host at launch (`FISHERS_API_URL`), so it points at a
ring without a rebuild:

```
https://int.fishers.cloud     https://www.fishers.cloud
```

## Build once, promote many

int and test build images from the promoted ref. acc and prod build nothing —
they deploy the same `:latest` those builds pushed. Rebuilding for production
would ship an artefact nobody tested, from source that only probably matches.

Every build also pushes a `:<sha>` tag, so a ring can be pinned to an exact
build when `:latest` has moved on:

```bash
helm upgrade fishers-api devops/helm-charts/fishers-api \
  -n fishers-prod --reuse-values --set image.tag=<sha>
```

## What runs in a ring

Namespace `fishers-<ring>`, deployed in this order — which is not incidental:

1. **fishers-postgres** — StatefulSet, one PVC. The API's readiness probe
   touches the pool, so an API rolled out first would never go Ready.
2. **fishers-api** — schema is compiled into the binary (`sqlx::migrate!`) and
   replays on boot, so there is no migration job and the binary can never be
   newer than its own schema.
3. **fishers-web** — owns the ingress for the host. Deployed last, so the
   ingress is created when both Services it names already exist; an ingress
   ahead of its backend answers 503, which reads as a broken release.

### Probes

`/health` is a constant string. `/health/ready` touches the pool.

- **Liveness** uses `/health`. Restarting a pod cannot fix a database outage —
  wiring liveness to the database turns one failed dependency into a
  crash-loop.
- **Readiness** uses `/health/ready`. A pod that cannot reach Postgres should
  leave the Service, but should not be killed.
- **Ring Promoter** gates on `/health/ready` too. A promotion gated on
  `/health` would wave through a ring where every real request hangs — which is
  exactly the state this repo was found in locally.

## First-time setup for a ring

### 1. Repository secrets

`bwalia/fishers` has none of these yet. All are required before any deploy:

| Secret | Used for |
|---|---|
| `MY_K3S1_CONFIG` | base64 kubeconfig for k3s1 |
| `NEBULACR_REGISTRY` / `NEBULACR_USERNAME` / `NEBULACR_PASSWORD` | image push + in-cluster pull secret |
| `FISHERS_JWT_SECRET` | signs access/refresh tokens |
| `FISHERS_DB_PASSWORD` | Postgres role, shared by both charts |
| `CLOUDFLARE_API_TOKEN` | DNS records in the `fishers.cloud` zone |
| `WSLPROXY_USER` / `WSLPROXY_PASSWORD` / `WSLPROXY_GATEWAY_URL` | edge vhost admin API |
| `ANTHROPIC_API_KEY` | optional — chat assistant; absent means disabled |
| `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` | optional |

Use a **different** `FISHERS_JWT_SECRET` per ring if you use GitHub
Environments. A shared signing key makes a token minted in int valid in prod.
The charts refuse an empty one rather than falling back to a default.

### 2. Register the edge

```
Actions → "Register edge vhost (Cloudflare + wslproxy)" → ENV: all
```

Creates the Cloudflare CNAME to `lon1.pop0.uk` and the wslproxy vhost from
`devops/wslproxy/host-<host>.json`. Until the vhost exists the edge answers
"Host not configured", which looks like a broken deploy and is not one.

The shared rule (`devops/wslproxy/rule-fishers-prod-default.json`) points all
four hosts at `193.237.176.232:8888`, the k3s1 traefik ingress entry. Traefik
then routes by `Host:` to the right namespace — which is why four rings share
one backend and still reach four different releases.

`proxied: false` on the CNAME is deliberate: the wslproxy edge terminates TLS
and renews its own certificate, and proxying through Cloudflare as well would
put a second terminator in front of it and break the ACME challenge.

### 3. Deploy

```
Actions → "Deploy Single Environment" → ENV: int, DEPLOY_BRANCH: main
```

### 4. Register with Ring Promoter

Paste `devops/ring-promoter/fishers-apps.yaml` into the `apps:` list of the
Ring Promoter ConfigMap and restart it:

```bash
kubectl -n ring-system edit configmap ring-promoter-config
kubectl -n ring-system rollout restart deploy/ring-promoter
```

Ring Promoter needs `RP_GITHUB_TOKEN` to have `actions:write` on
`bwalia/fishers`. After that, promotion int → test → acc → prod is a click (or
an unattended chain) at https://rp.workstation.co.uk/.

## DNS

ExternalDNS is the primary write path — each ring's ingress carries an
`external-dns.alpha.kubernetes.io/hostname` annotation.

`cloudflare-dns-reconcile.yml` is the backstop, hourly and on demand. It
discovers hosts from **live ingresses by suffix**, not from a list in the repo:
catching an ingress that forgot its annotation is the entire point, and a
hard-coded list would only re-assert what somebody already remembered to write
down. It writes CNAME only — never TXT, which is ExternalDNS's ownership
registry, and writing it here would have the two fighting over every record.

## Troubleshooting

| Symptom | Look at |
|---|---|
| "Host not configured" from the edge | wslproxy vhost missing — run *Register edge vhost* |
| 503 on `/` but `/api` works | web pods not Ready; `kubectl -n fishers-<ring> get pods` |
| API pod Ready but requests hang | it isn't — readiness touches the pool. Check `/health/ready` directly |
| Deploy times out on the API step | `--wait` blocks on readiness, so this is usually Postgres. `kubectl -n fishers-<ring> logs sts/fishers-postgres` |
| Ring Promoter shows red after a green workflow | health_url probes the outcome, not the run. Check the host through the edge |

## Local development

None of this is involved. `./scripts/start.sh` runs the whole stack on your
Mac — see the README.
