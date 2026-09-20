# Venue hire, event management and suppliers

Design for turning a Fishers venue from a label on a fixture into a bookable,
billable asset — for every sport, and for events that are not sport at all.

## 1. The gap, precisely

`venues` today is six columns and no behaviour:

```sql
CREATE TABLE venues (
    id, club_id, name, address, lat, lng, created_at
);
```

It is a place a fixture points at. It has no notion of being hireable, no
rates, no availability, no owner who confirms, no money. Every requirement
below is genuinely new work — nothing here is a rename of something existing.

What *does* already exist and should be built on rather than duplicated:

| Have | Where | Use for |
|---|---|---|
| `SportType` — cricket, football, badminton, paddle, pickleball, tennis, other | `domain/src/enums.rs` | Multi-sport is already in the spine |
| `Event` with `venue_id`, `sport`, `event_subtype`, fees, tickets, capacity, `metadata` | `domain/src/event.rs` | The thing a hire produces |
| `Payment`, `CreatePaymentIntentRequest` | `domain/src/payment.rs` | Deposits and balances |
| `Product`, `Order`, `OrderItem` | `domain/src/order.rs` | Catering lines, stall fees |
| `platform_events` append-only log | `docs/PLATFORM.md` | Booking state changes |
| RBAC matrix with `ManageEvents`, `ManageClubOps` | `domain/src/rbac.rs` | Who may confirm a booking |

**Fishers starts with an advantage most booking platforms never get.** Bookteq,
LemonBooking and the rest must go and acquire supply — sign up venues one at a
time. Fishers already has clubs with grounds, pavilions and bars on the
platform, and already has the clubs and players who need them. Both sides of
the marketplace are already here. That is the thing worth building around.

## 2. What the research says

### Pitch and facility hire
The UK systems converge on one shape: a request is **held, not booked**, until a
lettings manager approves it. Block bookings in particular require approval
before confirmation. Payment is deliberately plural — card online, BACS by
invoice, cash, or pay-on-the-day for casual slots, where a player books an open
slot, pays and is confirmed on the spot.
([Bookteq](https://www.bookteq.com/pitch-booking-software/),
[LemonBooking](https://lemonbooking.com/en-GB/solutions/sports-facility-booking-system),
[Allbooked](https://www.allbooked.com/insights/sports-pitch-booking-software))

### Catering
A catering job is only secure once **proposal, contract, deposit and service
details are connected**. The money has a standard shape:

- A deposit on signing to hold the date — commonly ~50%, usually
  **non-refundable**, because it holds a date and commits the caterer's own
  purchases whether or not the event happens.
- A **guest-count lock**, typically 7 days out, with a per-added-guest price
  written into the contract.
- Final balance on or before the day.

([PandaDoc catering contract](https://www.pandadoc.com/catering-contract-template/),
[Evolved Catering on deposits](https://evolvedeventscatering.com/blog/catering-deposit-guide/),
[Promise Legal](https://blog.promise.legal/startup-central/catering-contracts-for-events-a-legal-guide-for-startups/),
[Maroo](https://www.maroo.us/solutions/catering-providers))

### Stalls and vendors
Market software handles **vendor applications, stall allocation on a site map,
compliance tracking, invoicing and digital signature**. Compliance is not a
footnote: food hygiene rating and public liability insurance are the documents
that gate a stallholder trading at all.
([LocalStalls](https://localstalls.com/en),
[Marketspread](https://marketspread.com/manage/events/))

### Connecting businesses
The marketplace pattern is a brief out, matched quotes back, in one workspace —
Cvent's Vendor Marketplace does RFP-to-supplier matching across 65,000 vendors.
Revenue is commission, subscription, lead fees, or premium placement, and
payment architecture for high-value advance commitments uses **escrow and
milestone scheduling**.
([Cvent](https://www.cvent.com/en/event-marketing-management/vendor-marketplace),
[Shipturtle](https://www.shipturtle.com/blog/build-event-planning-services-marketplace))

## 3. The core idea

**One booking lifecycle, three uses.** Pitch hire, party hire and a charity BBQ
are not three systems. They are one booking against one bookable asset, differing
only in what is attached to it:

| | Asset | Attached |
|---|---|---|
| Play a match | A pitch / court / lane | A fixture |
| Birthday, wedding | A pavilion / hall / bar | Catering, maybe a bar tab |
| BBQ, charity match | Ground + pavilion | Catering, stalls, tickets, a fixture |

Build the booking once. Let the attachments vary. A club that only ever hires
out a net lane never sees the catering half of the product.

## 4. Domain model

### `venue_spaces` — the bookable unit
A venue is a site; you hire a *space* within it. Hertford CC is a venue; its
square, its outfield, its two net lanes and its pavilion are five spaces with
different rates, capacities and rules.

```
venue_spaces
  id, venue_id, name, kind, sports[], capacity,
  is_hireable, requires_approval,
  notice_hours_min, notice_days_max,
  slot_minutes, buffer_minutes,
  cancellation_policy_id, notes, active
```

`kind`: `pitch | square | net_lane | court | hall | pavilion | bar | room | other`
`sports[]`: which `SportType`s the space serves — empty means non-sport (a hall).
This is how "all sports" is satisfied: a space declares what it is for, and
football, tennis and padel need no new code.

### `venue_rate_cards` — what it costs
```
venue_rate_cards
  id, space_id, name, unit, amount_cents, currency,
  member_amount_cents, day_of_week[], time_from, time_to,
  season_from, season_to, min_units, active
```
`unit`: `per_hour | per_session | per_half_day | per_day | per_head | fixed`.
Member vs non-member pricing is first-class — clubs charge their own members
differently, and a rate card that cannot express that gets worked around in
someone's head.

### `venue_availability` and `venue_blackouts`
Opening hours per space per weekday, plus explicit blackouts for maintenance,
league fixtures, winter. A booking may only be *held* inside availability and
outside blackouts.

### `venue_bookings` — the spine
```
venue_bookings
  id, space_id, venue_id, owner_club_id,
  requester_user_id, requester_club_id,
  purpose, sport, starts_at, ends_at,
  headcount, status, hold_expires_at,
  quote_id, agreement_id,
  total_cents, deposit_cents, currency,
  payment_terms, decline_reason, cancelled_at,
  created_at, updated_at
```
`purpose`: `match | training | nets | social | private_hire | fundraiser | other`
`payment_terms`: `prepay | deposit_then_balance | pay_on_the_day | invoice`

### Suppliers
```
suppliers            id, name, kind, owner_user_id, club_id?, service_area, active, verified_at
supplier_services    id, supplier_id, name, unit, from_amount_cents, min_headcount, lead_time_days
supplier_documents   id, supplier_id, kind, number, issued_at, expires_at, file_key, verified_at
```
`kind`: `caterer | bar | bbq | hire | equipment | photography | officiating | other`
`document.kind`: `public_liability | food_hygiene | dbs | pat_test | other`

`supplier_documents` is the compliance gate the research is emphatic about. A
supplier with an expired public liability certificate cannot be confirmed onto
an event, and the system should say so rather than leaving a secretary to
remember.

### Stalls
```
event_stalls         id, event_id, code, position, size, fee_cents, power, status
stall_applications   id, stall_id?, event_id, supplier_id, status, applied_at, decided_at
```

### Quotes, agreements, signatures
```
quotes            id, booking_id?, event_id?, from_party, to_party, status,
                  subtotal_cents, tax_cents, total_cents, valid_until, terms
quote_lines       id, quote_id, description, unit, qty, unit_amount_cents, supplier_service_id?
agreements        id, quote_id, kind, body_md, version, status,
                  guest_lock_at, guest_lock_count, cancellation_policy_id
signatures        id, agreement_id, party, signed_by_user_id, signed_at, ip, user_agent
```

An agreement is an immutable rendered document with a version. Changing terms
creates a new version requiring re-signature — that is the whole point of a
contract, and a mutable one is worthless in a dispute.

## 5. Booking lifecycle

```
enquiry ──► held ──► confirmed ──► in_progress ──► completed ──► settled
   │         │          │                              │
   │         ├─ expired │                              └─► disputed
   ├─ declined          ├─ cancelled_by_hirer
                        ├─ cancelled_by_owner
                        └─ no_show
```

- **enquiry → held**: the slot is provisionally locked with `hold_expires_at`.
  Holds expire, or the calendar silently fills with abandoned requests.
- **held → confirmed**: the owner approves. This is the approval gate every UK
  system has, and the one the user asked for ("get confirmation from the
  owner"). Confirmation may require a deposit, depending on `payment_terms`.
- **confirmed → completed → settled**: `pay_on_the_day` settles after play.

Every transition writes a `platform_events` row, per `docs/PLATFORM.md`, so
stats, notifications and the AI briefing subscribe rather than reimplement.

**Double-booking is a database problem, not an application one.** Use a
PostgreSQL exclusion constraint over `(space_id, tstzrange(starts_at, ends_at))`
for non-terminal statuses. Two secretaries confirming the same Saturday from two
phones is a race the app layer will lose.

## 6. Payments

The user's requirement — *pay on the day of the match played* — is one of four
terms the system must support, and it is the one with the most risk. Model all
four explicitly:

| Term | Deposit | Balance | For |
|---|---|---|---|
| `prepay` | — | Full, at confirmation | Casual, one-off, unknown hirer |
| `deposit_then_balance` | % at confirmation | Before or on the day | Parties, weddings, catering |
| `pay_on_the_day` | Optional | On/after completion | Trusted clubs, regular fixtures |
| `invoice` | — | Net terms after | Leagues, councils, block bookings |

Default `pay_on_the_day` to **known clubs only**, with a deposit for everyone
else. A no-show on an unsecured booking costs the owner the slot and the staff
who turned up. Per the research, a date-holding deposit is normally
non-refundable, and the cancellation policy must say so in the agreement before
it is signed, not after.

`guest_lock_at` + `guest_lock_count` implement the 7-days-out guest-count lock
with a per-added-guest rate, which is where catering disputes actually arise.

## 7. Contracts and agreements

Quote → accept → agreement → signature → obligations. The agreement is rendered
Markdown, versioned and immutable; signatures capture who, when, and from where.
A cancellation policy is a referenced object, not free text, so a refund can be
computed rather than argued.

## 8. RBAC

Three new permissions in the existing matrix (`domain/src/rbac.rs`):

- `ManageVenues` — define spaces, rates, availability. Club admin / secretary.
- `ApproveBookings` — confirm, decline, cancel. Club admin / secretary.
- `ManageSuppliers` — engage caterers, allocate stalls, sign agreements.

Captains get none of these by default: a captain may *request* a hire, and a
secretary approves it. That matches how clubs already work and matches the
existing matrix, where `ManageClubOps` sits with admin and secretary.

Supplier users are a new principal that is **not** a club member. They need
scoped access to their own quotes, documents and stalls, and nothing else —
this is the one place the current RBAC model does not stretch, and it needs
deciding before implementation.

## 9. Phasing

Do not build the marketplace first. Build the thing one club needs on Saturday.

1. **Hireable spaces + rate cards + availability.** Read-only browse. **Shipped
   (Phase 1):** migration `20260920000001_venue_hire_spaces.sql`, domain
   `venue_hire`, APIs under `/api/v1/hire/spaces`, `/venues/{id}/spaces`,
   `/spaces/{id}/…`, web `/hire` browse and `/clubs/[id]/hire` owner setup.
   Permissions: `ManageVenues`, `ApproveBookings`, `ManageSuppliers` (latter
   two reserved for later phases).
2. **Booking with owner approval**, holds, expiry, the exclusion constraint,
   `platform_events`. Pitch hire works end to end, all sports.
3. **Money**: deposits, pay-on-the-day, settlement, refunds against policy.
4. **Private hire**: pavilion/hall, headcount, non-sport purposes.
5. **Quotes, agreements, signatures.**
6. **Suppliers + compliance documents** — catering attached to a booking.
7. **Stalls + applications + site map** — BBQs, charity days, fairs.
8. **Discovery**: search spaces and suppliers across clubs. The marketplace, last,
   once there is supply worth searching.

Each phase ships to web and both apps, and is useful alone.

## 10. Decisions needed before any code

These are commercial and legal, not technical, and they change the schema:

1. **Does Fishers touch the money?** Taking payment from a hirer and paying a
   club or caterer is regulated money transmission in the UK. Stripe Connect
   with the club as the merchant of record is the usual answer, but this needs
   confirming with an accountant and quite possibly the FCA position checking.
   Escrow — which the marketplace research recommends for high-value advance
   commitments — is a materially bigger regulatory step than pass-through.
2. **Commission, or subscription?** It changes whether a booking needs a fee
   ledger at all.
3. **Can non-Fishers venues and suppliers join?** If yes, suppliers are a
   first-class principal with their own onboarding and identity. If no, the
   model stays inside clubs and is much simpler.
4. **Who carries liability** when a hire goes wrong — the club, or the platform?
   Drives what the agreement template must say.
5. **VAT** on hire and catering, which differs by whether the club is VAT
   registered and whether the let is exempt. This affects `quote_lines`.

I can draft the schema and the API against any of these answers, but guessing
at 1 and 5 would produce a system that has to be rebuilt once a real accountant
looks at it.
