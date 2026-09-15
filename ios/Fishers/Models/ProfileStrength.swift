import Foundation

/// How much of a profile is filled in, and what is worth adding next.
///
/// Nothing here is required to use the app — a name and a sport are enough to
/// be picked and to start a match. The rest is what makes a player someone a
/// captain recognises, so it is counted and asked for, never demanded.
struct ProfileStrength: Equatable {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let weight: Int
        let done: Bool
    }

    let items: [Item]

    init(_ user: PublicUser) {
        let main = user.primaryProfile
        items = [
            Item(id: "name", title: "Your name", weight: 10, done: !user.name.trimmingCharacters(in: .whitespaces).isEmpty),
            Item(id: "sport", title: "What you play", weight: 15, done: main != nil),
            Item(id: "phone", title: "Your mobile number", weight: 10, done: user.phone?.nonEmpty != nil),
            Item(id: "photo", title: "A photo", weight: 15, done: user.avatarUrl?.nonEmpty != nil),
            Item(id: "standard", title: "The standard you play at", weight: 15, done: main?.tier != nil),
            Item(id: "position", title: "Your position", weight: 10, done: main?.position?.nonEmpty != nil),
            // Same order and weights as the API's count, so both say the same next thing.
            Item(id: "verified", title: "A confirmed email or number", weight: 10, done: user.isVerified),
            Item(id: "area", title: "Where you're based", weight: 5,
                 done: user.location?.area?.nonEmpty != nil || user.location?.postcode?.nonEmpty != nil),
            Item(id: "travel", title: "How you get to games", weight: 5, done: user.location?.transport != nil),
            Item(id: "emergency", title: "An emergency contact", weight: 5, done: user.emergencyContact?.nonEmpty != nil),
        ]
    }

    var percent: Int { items.filter(\.done).reduce(0) { $0 + $1.weight } }
    var isComplete: Bool { percent >= 100 }
    var missing: [Item] { items.filter { !$0.done } }

    /// "Add a photo, the standard you play at and your position" — the three
    /// that count most, in plain words.
    var nextUp: String {
        let top = missing.sorted { $0.weight > $1.weight }.prefix(3).map { $0.title.prefix(1).lowercased() + $0.title.dropFirst() }
        switch top.count {
        case 0: return ""
        case 1: return "Add \(top[0])"
        default: return "Add " + top.dropLast().joined(separator: ", ") + " and " + top.last!
        }
    }
}
