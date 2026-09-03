import Foundation

enum AvailabilityStatus: String, Codable, CaseIterable {
    case available
    case maybe
    case unavailable

    var label: String { rawValue.capitalized }

    /// Cycle order used by the tap-to-toggle calendar.
    var next: AvailabilityStatus {
        switch self {
        case .available: return .maybe
        case .maybe: return .unavailable
        case .unavailable: return .available
        }
    }
}

/// One user's availability for one calendar day. `date` is a "yyyy-MM-dd" string
/// (date-only, no timezone ambiguity over the wire).
struct Availability: Codable, Identifiable, Hashable {
    var id: UUID
    var userId: UUID
    var date: String
    var status: AvailabilityStatus
    var note: String?
    var recurrenceRule: String?

    var day: Date? { DayFormatter.date(from: date) }
}

enum DayFormatter {
    static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        return df
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
