import SwiftUI

extension AvailabilityStatus {
    var color: Color {
        switch self {
        case .available: return .green
        case .maybe: return .orange
        case .unavailable: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .maybe: return "questionmark.circle.fill"
        case .unavailable: return "xmark.circle.fill"
        }
    }
}

extension RSVPStatus {
    var color: Color {
        switch self {
        case .going: return .green
        case .maybe: return .orange
        case .notGoing: return .red
        }
    }
}

extension EventSubtype {
    var color: Color {
        switch self {
        case .nets: return .blue
        case .friendly: return .purple
        case .leagueMatch: return .indigo
        case .social: return .pink
        case .generic: return .teal
        }
    }
}

func sportIcon(_ sport: String) -> String {
    switch sport.lowercased() {
    case "cricket": return "figure.cricket"
    case "football": return "soccerball"
    case "badminton": return "figure.badminton"
    case "padel", "paddle", "pickleball", "tennis": return "tennis.racket"
    default: return "sportscourt"
    }
}

struct AvatarView: View {
    let user: User
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.2))
            Text(user.initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: size, height: size)
    }
}

struct SubtypeBadge: View {
    let subtype: EventSubtype

    var body: some View {
        Label(subtype.label, systemImage: subtype.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(subtype.color.opacity(0.15), in: Capsule())
            .foregroundStyle(subtype.color)
    }
}

struct EventRow: View {
    let event: Event

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(event.startAt, format: .dateTime.day())
                    .font(.title3.bold())
                Text(event.startAt, format: .dateTime.month(.abbreviated))
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(event.startAt, format: .dateTime.hour().minute())
                    if let venue = event.venue {
                        Text("·")
                        Text(venue.name).lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                SubtypeBadge(subtype: event.eventSubtype)
            }
            Spacer()
            if event.hasFee {
                Text((event.feeAmount ?? 0).money(event.currency ?? "GBP"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
    }
}
