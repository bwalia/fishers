import Foundation

/// What the API says this deployment's pickers should offer.
struct SportsOnOffer: Decodable {
    /// What a new club or team may be started in.
    let offered: [String]
    /// Every sport the API knows a name for. Sent beside `offered` so a club
    /// that already plays football still renders with a name and a badge on a
    /// deployment that has stopped offering it.
    let all: [String]
}

/// Which sports the pickers offer.
///
/// Gully Cricket ships cricket while the rest are finished; Fishers is a
/// multi-sport app and offers all of them. The server is the authority
/// because the answer is per brand and per ring — baked into the app, turning
/// a finished sport on would mean an App Store release and a week of waiting.
///
/// Starts as every sport rather than none. A picker with nothing in it is a
/// dead end, this is one small request against an API the app is already
/// talking to, and the server refuses a sport it does not offer regardless —
/// so the worst a stale list costs is a refusal that names the sport.
@Observable
final class OfferedSports {
    static let shared = OfferedSports()

    private(set) var sports: [Sport] = Sport.allCases

    /// Asked once a launch. Both pickers ask on appear and the answer cannot
    /// differ between them.
    private var asked = false

    private init() {}

    @MainActor
    func load() async {
        guard !asked else { return }
        asked = true
        guard let answer = try? await FishersAPI.offeredSports() else {
            // One flat moment on a train should not settle this for the whole
            // launch; the next picker asks again.
            asked = false
            return
        }
        let offered = answer.offered.compactMap(Sport.named)
        // An answer nobody can read is worse than no answer: an empty grid is
        // the one outcome with no way forward.
        guard !offered.isEmpty else { return }
        sports = offered
    }
}
