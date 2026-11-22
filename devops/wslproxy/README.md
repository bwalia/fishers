# wslproxy edge specs

One vhost per ring, plus the shared routing rule they all attach to. This is
the same shape as `beaconpulse-prod-default`, which fronts
int/test/acc/beaconpulse.net through a single rule.

`register-edge-vhost.yml` reads these files. They are checked in so the edge
configuration is reviewable and re-appliable, rather than living only in the
wslproxy admin UI where a change leaves no trace.

The backend `193.237.176.232:8888` is the k3s1 traefik ingress entry — the same
target every working wslproxy host uses. Traefik then routes by `Host:` to the
right namespace's ingress, which is why all four rings share one backend and
still reach four different releases.

## A ring pinned to one node

A ring with `placement` in its brand file (Gully Cricket prod, on vps005) is
the exception. Pods on the edge nodes can't reach pods on the home nodes, so
the home Traefik can't serve that ring. Its hosts use a rule of their own,
`rule-<brand>-<ring>-<node>.json`, whose one backend is the node's public
address on :80, where that node's traefik-edge listens. This is the same way
diytaxreturn runs on cloud003 and vyltzero on vps002. `tools/brand generate
<brand> --wslproxy` writes the rule along with the vhosts, and a test keeps the
committed files in step with the brand file.
