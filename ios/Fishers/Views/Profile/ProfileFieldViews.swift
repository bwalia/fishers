import SwiftUI

/// Enum options the pickers below can render generically.
protocol LabeledOption: Hashable, Identifiable, CaseIterable {
    var label: String { get }
}

extension SkillTier: LabeledOption {}
extension Division: LabeledOption {}
extension AgeGroup: LabeledOption {}
extension TransportMode: LabeledOption {}
extension Sport: LabeledOption {}

// MARK: - Chrome

struct ProfileAvatar: View {
    let user: PublicUser
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().fill(FishersTheme.pitch.gradient)
            Text(user.initials.isEmpty ? "?" : user.initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct ProfileErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FishersTheme.unavailable, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Building blocks

struct SelectableChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? FishersTheme.accent : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Dropdown for an optional enum choice, with a "Not set" entry.
struct OptionMenu<Option: LabeledOption>: View where Option.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Option?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Not set").tag(Option?.none)
            ForEach(Array(Option.allCases)) { option in
                Text(option.label).tag(Option?.some(option))
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Sports

struct SportSelectGrid: View {
    @Bindable var form: ProfileFormModel

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Sport.allCases) { sport in
                Button {
                    form.toggle(sport)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: sport.systemImage)
                            .font(.title2)
                        Text(sport.label)
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(form.isSelected(sport) ? FishersTheme.accent.opacity(0.16) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(form.isSelected(sport) ? FishersTheme.accent : .clear, lineWidth: 2)
                    )
                    .foregroundStyle(form.isSelected(sport) ? FishersTheme.accent : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PositionChips: View {
    let sport: Sport
    @Binding var position: String?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(sport.positions, id: \.self) { option in
                SelectableChip(title: option, isSelected: position == option) {
                    position = position == option ? nil : option
                }
            }
        }
    }
}

/// The level ladder — each rung explains itself, and the one above is the target.
struct TierSelector: View {
    @Binding var tier: SkillTier?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(SkillTier.allCases) { option in
                Button {
                    tier = option
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: tier == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(tier == option ? FishersTheme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.subheadline.weight(.semibold))
                            Text(option.blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tier == option ? FishersTheme.accent.opacity(0.12) : Color.secondary.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Shows how far the player is from the division they are aiming at.
struct DivisionLadder: View {
    let current: Division?
    let target: Division?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Division.allCases) { division in
                    Capsule()
                        .fill(color(for: division))
                        .frame(height: 6)
                }
            }
            if let climb {
                Text(climb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var climb: String? {
        guard let current, let target, target.rank > current.rank else { return nil }
        let steps = target.rank - current.rank
        return "\(steps) division\(steps == 1 ? "" : "s") to climb — \(current.shortLabel) to \(target.shortLabel)"
    }

    private func color(for division: Division) -> Color {
        guard let current else { return Color.secondary.opacity(0.15) }
        if division.rank <= current.rank { return FishersTheme.accent }
        if let target, division.rank <= target.rank { return FishersTheme.accent.opacity(0.3) }
        return Color.secondary.opacity(0.15)
    }
}

// MARK: - Stats

/// Renders one stat from `SportStats.fields(for:)`. Keeps the stats form
/// generic so a new sport needs a catalog entry and nothing else.
struct StatFieldRow: View {
    let field: StatField
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch field.kind {
            case .choice(let options):
                Picker(field.label, selection: $value) {
                    Text("Not set").tag("")
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
            case .integer(let range):
                LabeledContent(field.label) {
                    TextField("—", text: clamped(to: range))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            case .decimal(let placeholder):
                LabeledContent(field.label) {
                    TextField(placeholder, text: $value)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            case .text(let placeholder):
                LabeledContent(field.label) {
                    TextField(placeholder, text: $value)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let footnote = field.footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Digits only, held inside the catalog's range so averages and shirt
    /// numbers can't be typed into nonsense.
    private func clamped(to range: ClosedRange<Int>) -> Binding<String> {
        Binding(
            get: { value },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                guard !digits.isEmpty else { value = ""; return }
                let number = min(max(Int(digits) ?? range.lowerBound, range.lowerBound), range.upperBound)
                value = String(number)
            }
        )
    }
}

struct SportStatsSection: View {
    let sport: Sport
    @Bindable var form: ProfileFormModel

    var body: some View {
        ForEach(SportStats.fields(for: sport)) { field in
            StatFieldRow(field: field, value: form.statBinding(sport, field.key))
        }
    }
}

// MARK: - Logistics

struct WeekdayPicker: View {
    @Binding var selected: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.pickerOrder) { day in
                let isOn = selected.contains(day.rawValue)
                Button {
                    if isOn { selected.remove(day.rawValue) } else { selected.insert(day.rawValue) }
                } label: {
                    Text(day.shortLabel)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isOn ? FishersTheme.accent : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Reliability

extension ReliabilityBand {
    var color: Color {
        switch self {
        case .unproven: return .secondary
        case .patchy: return .orange
        case .dependable: return .blue
        case .rockSolid: return .green
        }
    }
}

struct ReliabilityRing: View {
    let reliability: ReliabilityScore
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: size * 0.11)
            Circle()
                // An unproven player has no score to draw yet.
                .trim(from: 0, to: reliability.band == .unproven ? 0 : reliability.fraction)
                .stroke(reliability.band.color, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(reliability.band == .unproven ? "–" : "\(reliability.score)")
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                Text("rel")
                    .font(.system(size: size * 0.15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(
            reliability.band == .unproven
                ? "Reliability unproven, not enough games yet"
                : "Reliability \(reliability.score) out of 100, \(reliability.band.label)"
        )
    }
}

/// The breakdown a player sees for their own score.
struct ReliabilityCard: View {
    let reliability: ReliabilityScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ReliabilityRing(reliability: reliability, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Label(reliability.band.label, systemImage: reliability.band.systemImage)
                        .font(.headline)
                        .foregroundStyle(reliability.band.color)
                    Text(reliability.band.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            if reliability.band == .unproven {
                Text("Answer invites, turn up and pay your fees — after \(ReliabilityScore.minimumSample) games this becomes a score captains can weigh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
            MeterRow(label: "Turned up when going", value: reliability.attendanceRate)
            MeterRow(label: "Answered the invite", value: reliability.responseRate)
            MeterRow(label: "Paid match fees", value: reliability.paymentRate)
            HStack {
                Text("Late drop-outs")
                Spacer()
                Text("\(reliability.lateCancellations)")
                    .foregroundStyle(reliability.lateCancellations > 0 ? .orange : .secondary)
            }
            .font(.caption)
            }
            Text("Based on \(reliability.sampleSize) invite\(reliability.sampleSize == 1 ? "" : "s"). Captains see this when picking a squad.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private struct MeterRow: View {
        let label: String
        let value: Double

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                    Spacer()
                    Text("\(Int((value * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.caption)
                ProgressView(value: min(max(value, 0), 1))
                    .tint(FishersTheme.accent)
            }
        }
    }
}
