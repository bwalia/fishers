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
