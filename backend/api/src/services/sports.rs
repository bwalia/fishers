//! Which sports this deployment offers.
//!
//! Gully Cricket is a cricket app and should offer cricket until the rest are
//! finished; Fishers is a multi-sport app and offers all of them. Neither is a
//! smaller version of the other, so the list comes from the brand's own Helm
//! values rather than from a default somebody has to remember to override.
//!
//! **Unset means every sport.** That is what every ring did before this module
//! existed, and a brand that says nothing should keep what it had rather than
//! quietly lose six sports because a value was missed in a chart. The brand
//! that wants fewer says so.
//!
//! This gates what is *offered*, never what is read. A club that already plays
//! football keeps its fixtures, its stats and its badge whatever this says —
//! turning a sport off is a decision about new clubs, not a way to break the
//! ones that exist. Enforcement therefore lives on create, and nowhere else.

use std::collections::BTreeSet;

use fishers_domain::SportType;

#[derive(Debug, Clone)]
pub struct Sports {
    enabled: BTreeSet<&'static str>,
}

impl Sports {
    /// `SPORTS_ENABLED`, a comma-separated list of wire spellings.
    ///
    /// An unreadable name is dropped with a warning rather than taken as "no
    /// sports": a typo in a chart should cost one sport, loudly, instead of
    /// emptying every picker in the product. A list that turns out empty for
    /// any reason falls back to all of them, for the same reason.
    pub fn from_env() -> Self {
        let raw = std::env::var("SPORTS_ENABLED").unwrap_or_default();
        if raw.trim().is_empty() {
            return Self::all();
        }
        let mut enabled = BTreeSet::new();
        for name in raw.split(',').map(str::trim).filter(|n| !n.is_empty()) {
            match SportType::parse(name) {
                Some(sport) => {
                    enabled.insert(sport.as_str());
                }
                None => tracing::warn!(
                    sport = name,
                    "SPORTS_ENABLED names a sport that does not exist; ignoring it"
                ),
            }
        }
        if enabled.is_empty() {
            tracing::warn!("SPORTS_ENABLED named nothing recognisable; offering every sport");
            return Self::all();
        }
        tracing::info!(sports = ?enabled, "sports on offer");
        Self { enabled }
    }

    fn all() -> Self {
        Self { enabled: SportType::ALL.into_iter().map(SportType::as_str).collect() }
    }

    /// Whether a new club or fixture may be created in this sport.
    pub fn allows(&self, sport: SportType) -> bool {
        self.enabled.contains(sport.as_str())
    }

    /// The first chosen sport this deployment does not offer, if any.
    ///
    /// Returns the sport rather than a bool so the refusal can name it: being
    /// told "football is not available yet" is actionable, and "invalid
    /// request" is the kind of message people screenshot and send to support.
    ///
    /// No HTTP vocabulary here on purpose — the same reasoning as the Apple
    /// and Google services next door, which hand back a string and let the
    /// route decide what status it deserves.
    pub fn first_rejected(&self, chosen: &[SportType]) -> Option<SportType> {
        chosen.iter().copied().find(|sport| !self.allows(*sport))
    }

    /// What a picker should show, in `SportType::ALL` order so cricket leads
    /// and the order never depends on how the chart happened to spell it.
    pub fn offered(&self) -> Vec<&'static str> {
        SportType::ALL
            .into_iter()
            .map(SportType::as_str)
            .filter(|name| self.enabled.contains(name))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gate(list: &[&'static str]) -> Sports {
        Sports { enabled: list.iter().copied().collect() }
    }

    #[test]
    fn unset_offers_everything() {
        let all = Sports::all();
        assert_eq!(all.offered().len(), SportType::ALL.len());
        assert!(all.allows(SportType::Football));
    }

    #[test]
    fn a_cricket_only_brand_offers_cricket_only() {
        let only = gate(&["cricket"]);
        assert_eq!(only.offered(), vec!["cricket"]);
        assert!(only.allows(SportType::Cricket));
        assert!(!only.allows(SportType::Football));
    }

    #[test]
    fn offered_follows_all_order_not_insertion_order() {
        // Spelled backwards in the chart; cricket still leads.
        let some = gate(&["tennis", "cricket", "football"]);
        assert_eq!(some.offered(), vec!["cricket", "football", "tennis"]);
    }

    #[test]
    fn rejection_names_the_sport_rather_than_just_failing() {
        let only = gate(&["cricket"]);
        assert_eq!(only.first_rejected(&[SportType::Cricket]), None);
        assert_eq!(
            only.first_rejected(&[SportType::Cricket, SportType::Football]),
            Some(SportType::Football)
        );
    }

    #[test]
    fn padel_still_means_paddle() {
        // Both apps spelled it "padel" before the enums were lined up, and
        // profiles saved then still say it.
        assert_eq!(SportType::parse("padel"), Some(SportType::Paddle));
        assert_eq!(SportType::parse("  PADDLE "), Some(SportType::Paddle));
        assert_eq!(SportType::parse("quidditch"), None);
    }
}
