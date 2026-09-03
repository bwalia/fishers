//! Fee-splitting helpers ("£8 each, 11 confirmed").
//!
//! All amounts are integer minor units (pence).

/// Split `total_pence` across `payers`, distributing the remainder one penny
/// at a time to the first payers so the shares always sum to the total.
///
/// Returns an empty vec for zero payers, and zero shares for a non-positive
/// total.
pub fn split_fee(total_pence: i64, payers: usize) -> Vec<i64> {
    if payers == 0 {
        return Vec::new();
    }
    if total_pence <= 0 {
        return vec![0; payers];
    }
    let n = payers as i64;
    let base = total_pence / n;
    let remainder = (total_pence % n) as usize;
    (0..payers)
        .map(|i| if i < remainder { base + 1 } else { base })
        .collect()
}

/// The share for one payer when a total is split evenly (largest share,
/// i.e. what the organiser should quote: "£8 each").
pub fn share_per_head(total_pence: i64, payers: usize) -> i64 {
    split_fee(total_pence, payers).first().copied().unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_evenly_when_divisible() {
        assert_eq!(split_fee(8800, 11), vec![800; 11]);
    }

    #[test]
    fn distributes_remainder_to_first_payers() {
        let shares = split_fee(1000, 3);
        assert_eq!(shares, vec![334, 333, 333]);
        assert_eq!(shares.iter().sum::<i64>(), 1000);
    }

    #[test]
    fn single_payer_pays_everything() {
        assert_eq!(split_fee(999, 1), vec![999]);
    }

    #[test]
    fn zero_payers_yields_empty() {
        assert!(split_fee(1000, 0).is_empty());
    }

    #[test]
    fn non_positive_total_yields_zero_shares() {
        assert_eq!(split_fee(0, 4), vec![0; 4]);
        assert_eq!(split_fee(-500, 2), vec![0; 2]);
    }

    #[test]
    fn shares_always_sum_to_total() {
        for total in [1, 7, 100, 12345, 99999] {
            for payers in 1..=20 {
                let shares = split_fee(total, payers);
                assert_eq!(shares.iter().sum::<i64>(), total, "total={total} payers={payers}");
                let max = shares.iter().max().unwrap();
                let min = shares.iter().min().unwrap();
                assert!(max - min <= 1, "shares must differ by at most 1p");
            }
        }
    }

    #[test]
    fn per_head_quote() {
        assert_eq!(share_per_head(8800, 11), 800);
        assert_eq!(share_per_head(1000, 3), 334);
    }
}
