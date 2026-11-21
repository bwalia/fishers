//! Club bank details at rest.
//!
//! The account number is sealed with AES-256-GCM before it reaches the
//! database, with the club's id as associated data — so a ciphertext copied
//! onto another club's row will not open. A database dump or a backup on its
//! own gives nobody an account number.
//!
//! Keys:
//!
//! * `PAYOUT_DETAILS_KEY` — 32 bytes as 64 hex characters (`openssl rand -hex
//!   32`). When it is set, everything new is sealed with it.
//! * Otherwise a key derived from `JWT_SECRET`, kept apart from the signing
//!   key by HMAC with its own label. It is always available for reading, so
//!   rows sealed before a dedicated key arrived still open.
//!
//! Each row stores the id of the key that sealed it (`key_id`, a short hash of
//! the key, never the key). If that key is gone — the JWT secret rotated with
//! no dedicated key set — the details read as unavailable and the secretary is
//! asked to enter them again. Nothing panics and nothing is guessed.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use hmac::{Hmac, Mac};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

const NONCE_LEN: usize = 12;

/// What is sealed. JSON so another method (an IBAN, a UPI id) is one more
/// field rather than a new format.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SealedDetails {
    pub account_number: String,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum CryptoError {
    #[error("the key that sealed these details is not configured")]
    UnknownKey,
    #[error("the sealed details could not be opened")]
    Corrupt,
}

#[derive(Clone)]
pub struct PayoutCrypto {
    /// `(key_id, key)`; the first one seals.
    keys: Vec<(String, [u8; 32])>,
    fingerprint_key: [u8; 32],
}

impl std::fmt::Debug for PayoutCrypto {
    // Never print a key, even by accident in a debug log.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PayoutCrypto")
            .field("keys", &self.keys.iter().map(|(id, _)| id.as_str()).collect::<Vec<_>>())
            .finish()
    }
}

fn derive(secret: &[u8], label: &str) -> [u8; 32] {
    let mut mac = <HmacSha256 as Mac>::new_from_slice(secret).expect("HMAC takes any key length");
    mac.update(label.as_bytes());
    mac.finalize().into_bytes().into()
}

fn key_id(prefix: &str, key: &[u8; 32]) -> String {
    let digest = Sha256::digest(key);
    format!("{prefix}{}", hex::encode(&digest[..4]))
}

impl PayoutCrypto {
    pub fn from_env(jwt_secret: &str) -> Self {
        let dedicated = std::env::var("PAYOUT_DETAILS_KEY").ok().and_then(|raw| {
            let raw = raw.trim();
            if raw.is_empty() {
                return None;
            }
            match hex::decode(raw).ok().and_then(|b| <[u8; 32]>::try_from(b).ok()) {
                Some(key) => Some(key),
                None => {
                    tracing::error!(
                        "PAYOUT_DETAILS_KEY is not 64 hex characters — ignoring it and \
                         sealing bank details with the key derived from JWT_SECRET"
                    );
                    None
                }
            }
        });
        Self::new(dedicated, jwt_secret)
    }

    pub fn new(dedicated: Option<[u8; 32]>, jwt_secret: &str) -> Self {
        let derived = derive(jwt_secret.as_bytes(), "fishers payout details v1");
        let mut keys = Vec::new();
        if let Some(key) = dedicated {
            keys.push((key_id("k", &key), key));
        }
        keys.push((key_id("j", &derived), derived));
        Self {
            keys,
            fingerprint_key: derive(jwt_secret.as_bytes(), "fishers payout fingerprint v1"),
        }
    }

    /// Seal for one club. Returns `(nonce ‖ ciphertext, key_id)`.
    pub fn seal(&self, club_id: Uuid, details: &SealedDetails) -> (Vec<u8>, String) {
        let (id, key) = &self.keys[0];
        let cipher = Aes256Gcm::new_from_slice(key).expect("32-byte key");
        let mut nonce = [0u8; NONCE_LEN];
        rand::rngs::OsRng.fill_bytes(&mut nonce);
        let plaintext = serde_json::to_vec(details).expect("serialisable");
        let sealed = cipher
            .encrypt(Nonce::from_slice(&nonce), Payload { msg: &plaintext, aad: club_id.as_bytes() })
            .expect("AES-GCM encryption does not fail for in-memory input");
        let mut out = nonce.to_vec();
        out.extend_from_slice(&sealed);
        (out, id.clone())
    }

    pub fn open(&self, club_id: Uuid, sealed: &[u8], key_id: &str) -> Result<SealedDetails, CryptoError> {
        let (_, key) = self.keys.iter().find(|(id, _)| id == key_id).ok_or(CryptoError::UnknownKey)?;
        if sealed.len() <= NONCE_LEN {
            return Err(CryptoError::Corrupt);
        }
        let (nonce, body) = sealed.split_at(NONCE_LEN);
        let cipher = Aes256Gcm::new_from_slice(key).expect("32-byte key");
        let plaintext = cipher
            .decrypt(Nonce::from_slice(nonce), Payload { msg: body, aad: club_id.as_bytes() })
            .map_err(|_| CryptoError::Corrupt)?;
        serde_json::from_slice(&plaintext).map_err(|_| CryptoError::Corrupt)
    }

    /// The same account always gives the same fingerprint, so a club entering
    /// its current details again is told so, without decrypting anything.
    pub fn fingerprint(&self, club_id: Uuid, sort_code: &str, account_number: &str) -> String {
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&self.fingerprint_key).expect("any key length");
        mac.update(club_id.as_bytes());
        mac.update(b"|uk_bank|");
        mac.update(sort_code.as_bytes());
        mac.update(b"|");
        mac.update(account_number.as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn details() -> SealedDetails {
        SealedDetails { account_number: "12345678".into() }
    }

    #[test]
    fn sealed_details_open_again() {
        let crypto = PayoutCrypto::new(None, "jwt");
        let club = Uuid::new_v4();
        let (sealed, id) = crypto.seal(club, &details());
        assert_eq!(crypto.open(club, &sealed, &id).unwrap(), details());
        assert!(!sealed.windows(8).any(|w| w == b"12345678"), "plaintext leaked");
    }

    /// Copying one club's sealed details onto another club's row must not work.
    #[test]
    fn details_sealed_for_one_club_do_not_open_for_another() {
        let crypto = PayoutCrypto::new(None, "jwt");
        let (sealed, id) = crypto.seal(Uuid::new_v4(), &details());
        assert_eq!(crypto.open(Uuid::new_v4(), &sealed, &id), Err(CryptoError::Corrupt));
    }

    #[test]
    fn a_tampered_byte_is_refused() {
        let crypto = PayoutCrypto::new(None, "jwt");
        let club = Uuid::new_v4();
        let (mut sealed, id) = crypto.seal(club, &details());
        let last = sealed.len() - 1;
        sealed[last] ^= 1;
        assert_eq!(crypto.open(club, &sealed, &id), Err(CryptoError::Corrupt));
    }

    /// A dedicated key seals new rows; rows sealed before it still open.
    #[test]
    fn adding_a_dedicated_key_keeps_old_rows_readable() {
        let club = Uuid::new_v4();
        let before = PayoutCrypto::new(None, "jwt");
        let (old, old_id) = before.seal(club, &details());
        let after = PayoutCrypto::new(Some([7u8; 32]), "jwt");
        let (new, new_id) = after.seal(club, &details());
        assert_ne!(old_id, new_id);
        assert!(new_id.starts_with('k') && old_id.starts_with('j'));
        assert_eq!(after.open(club, &old, &old_id).unwrap(), details());
        assert_eq!(after.open(club, &new, &new_id).unwrap(), details());
    }

    /// Rotating the JWT secret with no dedicated key loses the derived key:
    /// that reads as "unknown key", which the API turns into "enter them again".
    #[test]
    fn a_lost_key_is_reported_not_guessed() {
        let club = Uuid::new_v4();
        let (sealed, id) = PayoutCrypto::new(None, "old secret").seal(club, &details());
        assert_eq!(
            PayoutCrypto::new(None, "new secret").open(club, &sealed, &id),
            Err(CryptoError::UnknownKey)
        );
    }

    #[test]
    fn fingerprints_match_the_same_account_only() {
        let crypto = PayoutCrypto::new(None, "jwt");
        let club = Uuid::new_v4();
        let a = crypto.fingerprint(club, "123456", "12345678");
        assert_eq!(a, crypto.fingerprint(club, "123456", "12345678"));
        assert_ne!(a, crypto.fingerprint(club, "123456", "12345679"));
        assert_ne!(a, crypto.fingerprint(Uuid::new_v4(), "123456", "12345678"));
    }

    #[test]
    fn debug_output_never_shows_a_key() {
        let crypto = PayoutCrypto::new(Some([0xAB; 32]), "jwt");
        let shown = format!("{crypto:?}");
        assert!(!shown.to_lowercase().contains("abab"));
    }
}
