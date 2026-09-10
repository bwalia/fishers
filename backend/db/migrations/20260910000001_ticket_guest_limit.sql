-- The booking screen has to know how many guests a member may bring, or it
-- offers a field the server always refuses. `guests_allowed` has been on
-- `events` all along; the summary the screen reads never carried it.

DROP VIEW IF EXISTS event_ticket_summary;

CREATE VIEW event_ticket_summary AS
SELECT
    e.id AS event_id,
    e.title,
    e.ticket_capacity,
    e.ticket_price_cents,
    e.guests_allowed,
    COUNT(t.id) FILTER (WHERE t.status <> 'cancelled') AS bookings,
    COALESCE(SUM(1 + t.guests) FILTER (WHERE t.status <> 'cancelled'), 0) AS headcount,
    COALESCE(SUM(t.amount_cents) FILTER (WHERE t.status = 'paid'), 0) AS collected_cents,
    COALESCE(SUM(t.amount_cents) FILTER (WHERE t.status = 'reserved'), 0) AS outstanding_cents
FROM events e
LEFT JOIN event_tickets t ON t.event_id = e.id
GROUP BY e.id, e.title, e.ticket_capacity, e.ticket_price_cents, e.guests_allowed;
