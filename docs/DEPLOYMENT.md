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

## Backups

Patroni keeps the cluster up when a node goes, and prod runs a streaming
standby it promotes automatically. Neither is a backup: a replica copies
`DROP TABLE` as faithfully as it copies everything else. So `fishers-db` also
ships a CronJob that dumps the database into MinIO every night at **02:15 UTC**
(`devops/helm-charts/fishers-db/templates/backup-cronjob.yaml`), kept for
**14 days**.

Two containers rather than one image that can do both: `postgres:<version>`
dumps, `minio/mc` uploads, handing the file over on an emptyDir. The dump tag
follows `postgresVersion`, because `pg_dump` refuses to talk to a server newer
than itself.

What it refuses to do:

- **Upload a dump it cannot read back.** After dumping it runs
  `pg_restore --file=/dev/null`, which reads and decompresses every data block.
  `pg_restore --list` is not enough — the table of contents sits at the front of
  the archive, so a dump cut in half still lists all its tables.
- **Upload an empty one.** A dump with no table data restores cleanly and
  contains nothing; the job fails instead.
- **Delete anything before tonight's copy is confirmed stored.** The old ones go
  only after `mc stat` finds the new one.
- **Put backups anywhere near `media`.** That bucket is readable by anyone
  holding a key, because avatars load in a browser. Dumps go to `db-backups`,
  which is created private and has no anonymous policy applied to it, ever.

**How much you lose, and what is not in there.** The recovery point is the last
run, so up to 24 hours. The `media` bucket is *not* backed up: restore an old
database and its rows still point at whatever avatars MinIO holds now, so a key
written since the dump resolves to a picture that is still there, and one
deleted since does not. The operator's own credentials Secret is not in here
either — it is regenerated, and the API reads it from the cluster.

### Looking at them

```sh
export KUBECONFIG=~/.kube/k3s1.yaml
kubectl get cronjob fishers-db-backup -n fishers-int

# --all-containers, because the dump and every check it does run in an INIT
# container: on a failed night the only regular container never starts, and
# without this the command prints nothing at all. --ignore-errors so that
# not-yet-started container's error does not swallow the output either.
kubectl logs -n fishers-int -l app.kubernetes.io/name=fishers-db-backup \
  --all-containers --ignore-errors --prefix --tail=50

# what is actually stored
kubectl exec -n fishers-int fishers-minio-0 -- sh -lc '
  mc alias set t http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
  mc ls t/db-backups/int/'
```

### Restoring one

Restore into a **new** database first and look at it. Never straight over the
live one — if the dump turns out to be the problem, that is the only copy gone.

```sh
export KUBECONFIG=~/.kube/k3s1.yaml
NS=fishers-int
FILE=fishers-20260912T021500Z.dump   # from `mc ls` above

# Patroni moves the leader on failover and on every operator rolling update, so
# ask which pod holds it. On prod there are two, and the other one is read-only.
PG=$(kubectl get pod -n $NS -l spilo-role=master -o jsonpath='{.items[0].metadata.name}')

# 1. straight from MinIO into the database pod — not via your laptop. A dump is
#    every member's data in one file; it does not want a second home.
kubectl exec -n $NS fishers-minio-0 -- sh -lc "
  mc alias set t http://localhost:9000 \"\$MINIO_ROOT_USER\" \"\$MINIO_ROOT_PASSWORD\" >/dev/null
  mc cat t/db-backups/int/$FILE" \
| kubectl exec -i -n $NS $PG -- sh -c "cat > /tmp/$FILE"

# 2. restore it beside the live database, not over it
kubectl exec -n $NS $PG -- psql -U postgres -c 'CREATE DATABASE restore_check OWNER fishers'
kubectl exec -n $NS $PG -- pg_restore -U postgres -d restore_check /tmp/$FILE

# 3. check it is the database you meant to get back
kubectl exec -n $NS $PG -- psql -U postgres -d restore_check -c 'select count(*) from users'
```

Only once that looks right, replace the live one. Stop the API first: its pool
holds connections, and `DROP DATABASE` refuses while anything is attached.

```sh
WAS=$(kubectl get deploy fishers-api -n $NS -o jsonpath='{.spec.replicas}')
kubectl scale deploy/fishers-api -n $NS --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=fishers-api -n $NS --timeout=120s

kubectl exec -n $NS $PG -- psql -U postgres -c 'DROP DATABASE fishers'
kubectl exec -n $NS $PG -- psql -U postgres -c 'CREATE DATABASE fishers OWNER fishers'
kubectl exec -n $NS $PG -- pg_restore -U postgres -d fishers /tmp/$FILE

# Back up, on the replica count it had. It replays its own migrations on boot,
# so a dump from an older release catches up by itself.
kubectl scale deploy/fishers-api -n $NS --replicas=$WAS
kubectl rollout status deploy/fishers-api -n $NS

# and tidy up
kubectl exec -n $NS $PG -- psql -U postgres -c 'DROP DATABASE restore_check'
kubectl exec -n $NS $PG -- rm -f /tmp/$FILE
```

`pg_restore` runs without `--no-owner`: the dump carries `OWNER TO fishers`, and
`postgres` is a superuser, so the tables come back owned by the user the API
connects as. Strip the owner and the API can read nothing.

Swap `int` for the ring you mean in both the namespace and the object prefix —
each ring writes under its own name in its own MinIO.

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
