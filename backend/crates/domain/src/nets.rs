//! Cricket nets lane/time-slot auto-splitting (spec §3.4).
//!
//! Given confirmed players, a number of lanes and a max per lane, splits the
//! session into as few time slots as needed and balances players across lanes
//! within each slot (e.g. 18 players, 3 lanes × 3 → two slots: 6:00–7:00 and
//! 7:00–8:00, three lanes of three in each).

use chrono::{DateTime, Utc};

#[derive(Debug, Clone, PartialEq)]
pub struct LaneSlot<T> {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    /// One inner vec per lane (lane 1 first).
    pub lanes: Vec<Vec<T>>,
}

/// Split `players` into time slots and lane groups.
///
/// Players are taken in the given order (e.g. RSVP order). Returns an empty
/// vec when there is nothing to schedule or the configuration is degenerate
/// (no lanes, zero capacity, or a non-positive session window).
pub fn assign_lanes<T: Clone>(
    players: &[T],
    lanes: u32,
    max_per_lane: u32,
    session_start: DateTime<Utc>,
    session_end: DateTime<Utc>,
) -> Vec<LaneSlot<T>> {
    if players.is_empty() || lanes == 0 || max_per_lane == 0 || session_end <= session_start {
        return Vec::new();
    }

    let capacity_per_slot = (lanes as usize) * (max_per_lane as usize);
    let n_slots = players.len().div_ceil(capacity_per_slot);
    let slot_len = (session_end - session_start) / (n_slots as i32);

    players
        .chunks(capacity_per_slot)
        .enumerate()
        .map(|(slot_idx, chunk)| {
            let mut lane_groups: Vec<Vec<T>> = vec![Vec::new(); lanes as usize];
            // Round-robin keeps lanes balanced; a chunk never exceeds
            // lanes * max_per_lane, so no lane can exceed max_per_lane.
            for (i, player) in chunk.iter().enumerate() {
                lane_groups[i % lanes as usize].push(player.clone());
            }
            let start = session_start + slot_len * (slot_idx as i32);
            let end = if slot_idx + 1 == n_slots {
                session_end // absorb rounding into the last slot
            } else {
                start + slot_len
            };
            LaneSlot {
                start,
                end,
                lanes: lane_groups,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn utc(h: u32, mi: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 6, 3, h, mi, 0).unwrap()
    }

    fn players(n: usize) -> Vec<String> {
        (1..=n).map(|i| format!("p{i}")).collect()
    }

    #[test]
    fn eighteen_players_three_lanes_of_three_two_slots() {
        let slots = assign_lanes(&players(18), 3, 3, utc(18, 0), utc(20, 0));
        assert_eq!(slots.len(), 2);
        assert_eq!(slots[0].start, utc(18, 0));
        assert_eq!(slots[0].end, utc(19, 0));
        assert_eq!(slots[1].start, utc(19, 0));
        assert_eq!(slots[1].end, utc(20, 0));
        for slot in &slots {
            assert_eq!(slot.lanes.len(), 3);
            for lane in &slot.lanes {
                assert_eq!(lane.len(), 3);
            }
        }
        // Everyone is scheduled exactly once.
        let all: Vec<_> = slots
            .iter()
            .flat_map(|s| s.lanes.iter().flatten().cloned())
            .collect();
        assert_eq!(all.len(), 18);
    }

    #[test]
    fn everyone_fits_in_one_slot_when_under_capacity() {
        let slots = assign_lanes(&players(7), 4, 2, utc(18, 0), utc(20, 0));
        assert_eq!(slots.len(), 1);
        assert_eq!(slots[0].start, utc(18, 0));
        assert_eq!(slots[0].end, utc(20, 0));
        let sizes: Vec<usize> = slots[0].lanes.iter().map(|l| l.len()).collect();
        assert_eq!(sizes, vec![2, 2, 2, 1]); // balanced round-robin
    }

    #[test]
    fn three_slots_with_uneven_final_slot() {
        // 20 players, capacity 9 per slot -> 3 slots (9, 9, 2), 40 min each.
        let slots = assign_lanes(&players(20), 3, 3, utc(18, 0), utc(20, 0));
        assert_eq!(slots.len(), 3);
        assert_eq!(slots[0].start, utc(18, 0));
        assert_eq!(slots[0].end, utc(18, 40));
        assert_eq!(slots[1].end, utc(19, 20));
        assert_eq!(slots[2].end, utc(20, 0));
        let last_sizes: Vec<usize> = slots[2].lanes.iter().map(|l| l.len()).collect();
        assert_eq!(last_sizes, vec![1, 1, 0]);
    }

    #[test]
    fn lane_never_exceeds_max_per_lane() {
        for n in 1..40 {
            let slots = assign_lanes(&players(n), 3, 2, utc(18, 0), utc(20, 0));
            for slot in &slots {
                for lane in &slot.lanes {
                    assert!(lane.len() <= 2);
                }
            }
        }
    }

    #[test]
    fn degenerate_configs_return_empty() {
        assert!(assign_lanes(&players(5), 0, 3, utc(18, 0), utc(20, 0)).is_empty());
        assert!(assign_lanes(&players(5), 3, 0, utc(18, 0), utc(20, 0)).is_empty());
        assert!(assign_lanes(&players(0), 3, 3, utc(18, 0), utc(20, 0)).is_empty());
        assert!(assign_lanes(&players(5), 3, 3, utc(20, 0), utc(18, 0)).is_empty());
    }
}
