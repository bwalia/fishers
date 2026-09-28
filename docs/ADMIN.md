# The system view

`/admin` shows one brand's whole deployment on a page: how many people have
registered, how many clubs there are, what money has moved, and what is
currently broken. It exists for the person who runs the service, for the
evening when something is wrong and the question is "wrong where".

Every brand has its own database, so "the system" is one brand's deployment.
Nothing here can show another brand's people, and nothing needed to be written
to keep it that way.

## Who can see it

`PLATFORM_ADMIN_EMAILS` — a comma-separated list, read at startup:

```
PLATFORM_ADMIN_EMAILS=someone@example.com,someone-else@example.com
```

An environment list rather than a column on `users`, deliberately:

- There is no "make this person an admin" endpoint, so there is none to get
  wrong.
- Somebody who reaches the database cannot promote themselves by writing a row.
  The list lives in the vault beside the signing keys, at
  `kv/<brand>/<ring>/config` like every other setting.
- Granting it is a deploy. For a page that shows every user's email address,
  that is the right way round.

An address on the list also has to be **verified** on the account. Without
that, the list would be a set of usernames to impersonate: anybody could
register with the operator's address and be an admin until somebody noticed.

Refusal is a **404**, not a 403. A 403 tells whoever is probing that the panel
exists and that this account is not on the list. Neither fact is any use to
them and both are worth something to an attacker.

## Where the list lives

WSLVault, at `kv/<brand>/<ring>/config`, beside `JWT_SECRET` and the rest. The
chart passes that whole secret through with `envFrom`, so a key added in the
vault needs no chart change and no rebuild:

```bash
printf 'you@example.com' | scripts/vault-set.sh fishers int PLATFORM_ADMIN_EMAILS
```

The value goes in on stdin so it never reaches a shell history or a process
list. It is read-modify-write, so it adds to the ring's config rather than
replacing it. Each brand and ring is a separate grant — separate vault paths,
separate databases, separate deployments.

## Getting in the first time

**Sign in with Google, and there is nothing else to do.** Both paths that
attach a Google account set `email_verified_at`: `create_google_user` writes it
on a new account, and `link_google` fills it in on an existing one. Google has
already proved the address, so the verification requirement is met the moment
you sign in with it.

That matters because email verification otherwise needs SMTP, and SMTP is off
in most rings — which would leave the operator unable to confirm the very
address that lets them in.

If the address cannot use Google, break the circle from the database. Only
somebody with cluster access can, and cluster access is already more than this
panel grants:

```bash
export KUBECONFIG=~/.kube/k3s1.yaml
kubectl exec -n <brand>-<ring> fishers-db-0 -c postgres -- \
  psql -U postgres -d fishers -c \
  "UPDATE users SET email_verified_at = NOW() WHERE email = 'you@example.com'"
```

Either way, `/me` then returns `platform_admin: true`, the **System** link
appears in the More menu, and `/admin` answers.

If the link is missing, the cached copy of `/me` in the browser is stale —
sign out and in. If the page says it could not load, the address is not on the
list or is not verified; the two are deliberately indistinguishable from
outside.

## The password fallback

An account made with Google has **no password at all**, and `link_google`
clears any that an unverified account had — deliberately, so somebody who
squatted on an address cannot keep a credential once the real owner arrives.
The cost is that Google becomes the only way in, and on the day it is
unreachable, or a client id is rotated wrongly, it is no way in at all.

`POST /me/password` is the second way, and **Profile → Password** is where to
do it:

- where a password already exists, the current one has to be typed again — a
  stolen session must not be enough to replace the credential that outlives
  sessions;
- where there is none, a live session is the proof;
- either way every **other** session is revoked, so a token somebody else holds
  does not quietly become a permanent one.

Whoever the system view belongs to should set one. Everybody else can too; they
just have less to lose by not.

## What it shows

**What might be wrong**, first, because that is what the page is for:

| Check | Goes red when |
|---|---|
| Schema | a migration failed — the API is running against a schema it does not expect |
| Stripe webhooks | events received and not processed; payments may look unpaid |
| Payments | any failed in the last week |
| Assistant | agent runs errored in the last week, with the last message |

Underneath: verification codes outstanding, notifications sent in 24 hours and
how many nobody opened, and the database's size on disk.

**How big it is** — people, clubs, matches, balls scored, each with how many
arrived in the last week and the last month. The totals say how big; the deltas
say whether anything is happening, which is the more useful of the two.

**The detail** — four panels:

- *People*: registered, confirmed by email and by phone, signed in somewhere,
  devices taking push, and soft-deleted accounts, which every other count
  excludes.
- *Clubs*: clubs, teams, memberships, how many have nobody but their owner, and
  a breakdown by sport. A club playing two sports counts under both.
- *Cricket*: fixtures ahead, balls scored, and matches by status.
- *Money*: taken per currency — never summed across them, because pence and
  paise add to a number that means nothing — payments, failures this week, and
  orders placed but not paid.

**Find somebody**, because most trouble arrives as one person saying they
cannot log in rather than as a number. Searches name, email and phone, and
includes deleted accounts, marked — "I deleted my account and want it back" is
a real reason to write in, and a search that cannot find them answers the wrong
question. This is the only page in the app that shows contact details for
somebody you do not share a club with, which is the whole point of it and the
reason for the gate.

**What just happened** — the last 25 rows of `platform_events`, the audit trail
the rest of the app already writes.

## What it does not do

It reads. There is no button here that changes anything: no deleting a user, no
refunding a payment, no editing a club. That is not an oversight — a panel that
can only look at things needs far less defending than one that can act, and
nothing so far has needed the other kind. When something does, it should arrive
with its own confirmation step and its own line in `platform_events`.

It is also not monitoring. It answers "what does the system look like right
now", asked by a person. It does not alert, it does not keep history, and a
number that matters should end up somewhere that does.
