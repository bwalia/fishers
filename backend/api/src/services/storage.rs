//! Object storage for the things people upload — profile pictures today.
//!
//! MinIO speaks S3, so this signs requests the S3 way (SigV4). That is done by
//! hand rather than with the AWS SDK: everything it needs — HMAC-SHA256, hex,
//! an HTTP client — is already a dependency, and a single signed PUT is a
//! short, readable function next to a very large one.

use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, Clone)]
pub struct Storage {
    endpoint: String,
    bucket: String,
    region: String,
    access_key: String,
    secret_key: String,
    /// Where a browser fetches the object from, which is not always where the
    /// API writes it — in Docker the API talks to `minio:9000` while the
    /// browser needs `localhost:9002`.
    public_base: String,
    client: reqwest::Client,
}

impl Storage {
    /// `None` when the environment does not describe a bucket, so a developer
    /// without MinIO running gets a clear "uploads are not configured" rather
    /// than a confusing connection error.
    pub fn from_env() -> Option<Self> {
        let endpoint = std::env::var("S3_ENDPOINT").ok()?;
        let bucket = std::env::var("S3_BUCKET").ok()?;
        let access_key = std::env::var("S3_ACCESS_KEY").ok()?;
        let secret_key = std::env::var("S3_SECRET_KEY").ok()?;
        let public_base = std::env::var("S3_PUBLIC_BASE")
            .unwrap_or_else(|_| format!("{}/{}", endpoint.trim_end_matches('/'), bucket));
        Some(Self {
            endpoint: endpoint.trim_end_matches('/').to_string(),
            bucket,
            region: std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".into()),
            access_key,
            secret_key,
            public_base: public_base.trim_end_matches('/').to_string(),
            client: reqwest::Client::new(),
        })
    }

    pub fn public_url(&self, key: &str) -> String {
        format!("{}/{}", self.public_base, key)
    }

    /// Store one object. Overwrites whatever was at that key.
    pub async fn put(
        &self,
        key: &str,
        content_type: &str,
        body: Vec<u8>,
    ) -> anyhow::Result<String> {
        let now = chrono::Utc::now();
        let stamp = now.format("%Y%m%dT%H%M%SZ").to_string();
        let date = now.format("%Y%m%d").to_string();
        let payload_hash = hex::encode(Sha256::digest(&body));

        let url = format!("{}/{}/{}", self.endpoint, self.bucket, key);
        let host = url
            .split("://")
            .nth(1)
            .and_then(|rest| rest.split('/').next())
            .unwrap_or_default()
            .to_string();

        // Canonical request. The signed headers are kept to the three that
        // must be signed, in the order SigV4 demands (lowercase, sorted).
        let canonical = format!(
            "PUT\n/{}/{}\n\ncontent-type:{content_type}\nhost:{host}\nx-amz-content-sha256:{payload_hash}\nx-amz-date:{stamp}\n\ncontent-type;host;x-amz-content-sha256;x-amz-date\n{payload_hash}",
            self.bucket,
            uri_encode_path(key),
        );
        let scope = format!("{date}/{}/s3/aws4_request", self.region);
        let to_sign = format!(
            "AWS4-HMAC-SHA256\n{stamp}\n{scope}\n{}",
            hex::encode(Sha256::digest(canonical.as_bytes()))
        );

        // The signing key is derived one HMAC at a time, each keyed by the last.
        let mut signing = sign(format!("AWS4{}", self.secret_key).as_bytes(), date.as_bytes());
        signing = sign(&signing, self.region.as_bytes());
        signing = sign(&signing, b"s3");
        signing = sign(&signing, b"aws4_request");
        let signature = hex::encode(sign(&signing, to_sign.as_bytes()));

        let authorization = format!(
            "AWS4-HMAC-SHA256 Credential={}/{scope}, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature={signature}",
            self.access_key
        );

        let res = self
            .client
            .put(&url)
            .header("content-type", content_type)
            .header("x-amz-date", &stamp)
            .header("x-amz-content-sha256", &payload_hash)
            .header("authorization", authorization)
            .body(body)
            .send()
            .await?;

        if !res.status().is_success() {
            let status = res.status();
            let detail = res.text().await.unwrap_or_default();
            anyhow::bail!("storage rejected the upload ({status}): {detail}");
        }
        Ok(self.public_url(key))
    }
}

fn sign(key: &[u8], msg: &[u8]) -> Vec<u8> {
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC takes a key of any length");
    mac.update(msg);
    mac.finalize().into_bytes().to_vec()
}

/// S3 signs the *encoded* path, and encodes every byte that is not unreserved
/// — except the slashes between segments.
fn uri_encode_path(path: &str) -> String {
    path.split('/')
        .map(|segment| {
            segment
                .bytes()
                .map(|b| match b {
                    b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                        (b as char).to_string()
                    }
                    other => format!("%{other:02X}"),
                })
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("/")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_signing_key_chain_matches_the_aws_worked_example() {
        // From the AWS SigV4 documentation's own test vector, so a mistake in
        // the derivation shows up here rather than as a 403 from MinIO.
        let mut k = sign(b"AWS4wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", b"20150830");
        k = sign(&k, b"us-east-1");
        k = sign(&k, b"iam");
        k = sign(&k, b"aws4_request");
        assert_eq!(
            hex::encode(k),
            "c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9"
        );
    }

    #[test]
    fn a_path_is_encoded_but_its_slashes_survive() {
        assert_eq!(uri_encode_path("avatars/a b.png"), "avatars/a%20b.png");
        assert_eq!(uri_encode_path("a/b/c.jpg"), "a/b/c.jpg");
        // A key is built from a uuid, but never trust that it always will be.
        assert_eq!(uri_encode_path("x/+&?.png"), "x/%2B%26%3F.png");
    }
}
