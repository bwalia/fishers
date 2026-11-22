//! Pay links: one bill's pay page, opened from a WhatsApp message with no
//! sign-in.
//!
//! The token is the link's id and an HMAC of it under a key of its own
//! (derived from `JWT_SECRET` with a separate label). Nothing usable is stored:
//! the database holds the id, and the token is minted again whenever the
//! secretary shares the link. A copy of the database therefore opens no link,
//! and a token cannot be guessed or edited into another one — any change to it
//! fails the MAC, checked in constant time.
//!
//! What a link can do is deliberately small: show one bill's names, amounts
//! and the club's bank details, and record "I've paid" — a claim a treasurer
//! still has to confirm against the bank. It can never confirm anything.

use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use axum::http::HeaderMap;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

/// How many bytes of the MAC travel in the token. 96 bits: unguessable, and
/// the whole token stays 38 characters — short enough for a WhatsApp message.
const MAC_LEN: usize = 12;

#[derive(Clone)]
pub struct PayLinkKeys {
    key: [u8; 32],
    ip_key: [u8; 32],
}

impl std::fmt::Debug for PayLinkKeys {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("PayLinkKeys(..)")
    }
}

fn derive(secret: &[u8], label: &str) -> [u8; 32] {
    let mut mac = <HmacSha256 as Mac>::new_from_slice(secret).expect("any key length");
    mac.update(label.as_bytes());
    mac.finalize().into_bytes().into()
}

impl PayLinkKeys {
    pub fn new(jwt_secret: &str) -> Self {
        Self {
            key: derive(jwt_secret.as_bytes(), "fishers pay link v1"),
            ip_key: derive(jwt_secret.as_bytes(), "fishers pay link ip v1"),
        }
    }

    fn mac(&self, id: Uuid) -> [u8; 32] {
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&self.key).expect("any key length");
        mac.update(b"paylink|");
        mac.update(id.as_bytes());
        mac.finalize().into_bytes().into()
    }

    /// The token for link `id`.
    pub fn mint(&self, id: Uuid) -> String {
        let mut raw = id.as_bytes().to_vec();
        raw.extend_from_slice(&self.mac(id)[..MAC_LEN]);
        URL_SAFE_NO_PAD.encode(raw)
    }

    /// The link a token names, if the token is genuine.
    pub fn open(&self, token: &str) -> Option<Uuid> {
        if token.len() > 64 {
            return None;
        }
        let raw = URL_SAFE_NO_PAD.decode(token.trim()).ok()?;
        if raw.len() != 16 + MAC_LEN {
            return None;
        }
        let id = Uuid::from_slice(&raw[..16]).ok()?;
        let expected = self.mac(id);
        // Constant time: how much of a forged MAC matched must not leak.
        let mut diff = 0u8;
        for (a, b) in raw[16..].iter().zip(&expected[..MAC_LEN]) {
            diff |= a ^ b;
        }
        (diff == 0).then_some(id)
    }

    /// The secret handed to whoever said "I've paid" on a link, and only to
    /// them: taking it back or adding its screenshot needs it, so somebody
    /// else holding the same link can't.
    pub fn claim_secret(&self, payment_id: Uuid) -> String {
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&self.key).expect("any key length");
        mac.update(b"claim|");
        mac.update(payment_id.as_bytes());
        hex::encode(&mac.finalize().into_bytes()[..16])
    }

    /// Whether `given` is that claim's secret, compared in constant time.
    pub fn claim_secret_ok(&self, payment_id: Uuid, given: Option<&str>) -> bool {
        let Some(given) = given else { return false };
        let want = self.claim_secret(payment_id);
        want.len() == given.len() && want.bytes().zip(given.bytes()).fold(0u8, |d, (a, b)| d | (a ^ b)) == 0
    }

    /// The caller's address, hashed: enough to see one phone hammering a
    /// link in the audit trail, never an address kept in the clear.
    pub fn ip_hash(&self, headers: &HeaderMap) -> String {
        let ip = client_ip(headers);
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&self.ip_key).expect("any key length");
        mac.update(ip.as_bytes());
        hex::encode(&mac.finalize().into_bytes()[..8])
    }
}

/// How many proxies in front of the API append to `X-Forwarded-For` and can
/// be trusted to: the caller is that many entries from the right. 1 (the
/// default) is the ingress alone. Today Traefik doesn't trust the edge
/// proxy's header, so every caller arrives as the edge's address — which is
/// why the limits keyed on this are always per link or per number, never per
/// address alone.
fn trusted_hops() -> usize {
    static HOPS: std::sync::OnceLock<usize> = std::sync::OnceLock::new();
    *HOPS.get_or_init(|| {
        std::env::var("TRUSTED_PROXY_HOPS").ok().and_then(|v| v.parse().ok()).filter(|n| (1..=5).contains(n)).unwrap_or(1)
    })
}

/// The caller as the trusted proxies saw them. Entries further left are
/// whatever the client sent and prove nothing. Used only to throttle and to
/// hash for the audit trail.
pub fn client_ip(headers: &HeaderMap) -> String {
    forwarded_for(headers.get("x-forwarded-for").and_then(|v| v.to_str().ok()), trusted_hops())
        .or_else(|| headers.get("x-real-ip").and_then(|v| v.to_str().ok()).map(str::to_string))
        .unwrap_or_else(|| "local".to_string())
}

fn forwarded_for(header: Option<&str>, hops: usize) -> Option<String> {
    let entries: Vec<&str> = header?.split(',').map(str::trim).filter(|s| !s.is_empty()).collect();
    // Fewer entries than proxies: the leftmost is the best there is.
    let at = entries.len().saturating_sub(hops);
    entries.get(at).map(|s| s.to_string())
}

/// A sliding-window limit per key, in this process. Each API replica keeps
/// its own, which is enough to blunt somebody hammering a link; the database
/// limits (one open claim per person) are what hold across replicas.
pub struct Throttle {
    limit: usize,
    window: Duration,
    seen: Mutex<HashMap<String, VecDeque<Instant>>>,
}

impl Throttle {
    pub fn new(limit: usize, window: Duration) -> Self {
        Self { limit, window, seen: Mutex::new(HashMap::new()) }
    }

    /// Counts this request; false once `key` is over the limit.
    pub fn allow(&self, key: &str) -> bool {
        let Ok(mut seen) = self.seen.lock() else { return true };
        let now = Instant::now();
        if seen.len() > 10_000 {
            seen.retain(|_, hits| hits.back().is_some_and(|t| now.duration_since(*t) < self.window));
        }
        let hits = seen.entry(key.to_string()).or_default();
        while hits.front().is_some_and(|t| now.duration_since(*t) >= self.window) {
            hits.pop_front();
        }
        if hits.len() >= self.limit {
            return false;
        }
        hits.push_back(now);
        true
    }
}

/// A stable short fingerprint of a token, for throttle keys and logs, so the
/// token itself is never written anywhere.
pub fn token_fingerprint(token: &str) -> String {
    hex::encode(&Sha256::digest(token.as_bytes())[..6])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_caller_is_counted_from_the_trusted_end() {
        let h = Some("6.6.6.6, 81.2.3.4, 10.42.0.7");
        assert_eq!(forwarded_for(h, 1).as_deref(), Some("10.42.0.7"));
        assert_eq!(forwarded_for(h, 2).as_deref(), Some("81.2.3.4"));
        assert_eq!(forwarded_for(h, 5).as_deref(), Some("6.6.6.6"));
        assert_eq!(forwarded_for(Some(""), 1), None);
        assert_eq!(forwarded_for(None, 1), None);
    }

    #[test]
    fn a_minted_token_opens_its_own_link() {
        let keys = PayLinkKeys::new("secret");
        let id = Uuid::new_v4();
        let token = keys.mint(id);
        assert!(token.len() <= 40, "{token} is too long for a message");
        assert_eq!(keys.open(&token), Some(id));
    }

    /// Changing any character, or minting with another key, opens nothing.
    #[test]
    fn a_forged_or_edited_token_opens_nothing() {
        let keys = PayLinkKeys::new("secret");
        let token = keys.mint(Uuid::new_v4());
        for i in 0..token.len() {
            let mut chars: Vec<char> = token.chars().collect();
            chars[i] = if chars[i] == 'A' { 'B' } else { 'A' };
            let edited: String = chars.into_iter().collect();
            if edited != token {
                assert_eq!(keys.open(&edited), None, "edited at {i}");
            }
        }
        assert_eq!(PayLinkKeys::new("other").open(&token), None);
        assert_eq!(keys.open(""), None);
        assert_eq!(keys.open(&"A".repeat(500)), None);
    }

    #[test]
    fn the_ingress_address_is_the_last_one_appended() {
        let mut h = HeaderMap::new();
        h.insert("x-forwarded-for", "6.6.6.6, 203.0.113.9".parse().unwrap());
        assert_eq!(client_ip(&h), "203.0.113.9");
        assert_eq!(client_ip(&HeaderMap::new()), "local");
    }

    #[test]
    fn a_throttle_stops_at_its_limit_per_key() {
        let t = Throttle::new(3, Duration::from_secs(60));
        assert!(t.allow("a") && t.allow("a") && t.allow("a"));
        assert!(!t.allow("a"));
        assert!(t.allow("b"), "another key has its own allowance");
    }

    #[test]
    fn addresses_are_hashed_not_kept() {
        let keys = PayLinkKeys::new("secret");
        let mut h = HeaderMap::new();
        h.insert("x-forwarded-for", "203.0.113.9".parse().unwrap());
        let hash = keys.ip_hash(&h);
        assert!(!hash.contains("203"));
        assert_eq!(hash.len(), 16);
    }
}
