import SwiftUI

/// First run of the app: before anyone sees a calendar or a squad list they set
/// up who they are, what they play, at what level, and how they get to games.
struct ProfileSetupView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var form = ProfileFormModel(user: nil)
    @State private var stepIndex = 0
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didPrefill = false

    enum Step: Hashable {
        case about
        case sports
        case sport(Sport)
        case logistics
        case reliability
    }

    /// One step per chosen sport, so each gets its own level, league and stats.
    private var steps: [Step] {
        [.about, .sports] + form.selectedSports.map(Step.sport) + [.logistics, .reliability]
    }

    /// Steps appear and disappear as sports are picked, so the index is always
    /// read through a clamp.
    private var clampedIndex: Int { min(max(stepIndex, 0), steps.count - 1) }

    private var currentStep: Step { steps[clampedIndex] }

    private var isLastStep: Bool { clampedIndex >= steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch currentStep {
                case .about:
                    AboutForm(form: form)
                case .sports:
                    SportsPicker(form: form)
                case .sport(let sport):
                    SportDetailForm(sport: sport, form: form)
                case .logistics:
                    LogisticsForm(form: form)
                case .reliability:
                    ReliabilityStep(form: form, reliability: session.user?.reliability)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .task {
            guard !didPrefill else { return }
            didPrefill = true
            form = ProfileFormModel(user: session.user)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            FishersBrandHeader(style: .bar)

            HStack {
                Text("Step \(clampedIndex + 1) of \(steps.count)")
                    .font(FishersTheme.overline)
                    .tracking(0.5)
                    .foregroundStyle(FishersTheme.muted)
                Spacer()
                if case .sport(let sport) = currentStep {
                    Label(sport.label, systemImage: sport.systemImage)
                        .font(FishersTheme.caption)
                        .foregroundStyle(FishersTheme.accent)
                }
            }
            ProgressView(value: Double(stepIndex + 1), total: Double(steps.count))
                .tint(FishersTheme.accent)
            Text(title)
                .font(FishersTheme.title)
                .foregroundStyle(FishersTheme.ink)
            Text(subtitle)
                .font(FishersTheme.callout)
                .foregroundStyle(FishersTheme.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 10)
        .background(FishersTheme.cream)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                ProfileErrorBanner(message: errorMessage)
            }
            HStack(spacing: 12) {
                if clampedIndex > 0 {
                    Button("Back") {
                        withAnimation(.snappy) { stepIndex = clampedIndex - 1 }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button(action: advance) {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(isLastStep ? "Finish setup" : "Continue")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving || !canAdvance)
            }
        }
        .padding()
        .background(.bar)
    }

    private var title: String {
        switch currentStep {
        case .about: return "Let's set you up"
        case .sports: return "What do you play?"
        case .sport(let sport): return "Your \(sport.label.lowercased())"
        case .logistics: return "Getting to games"
        case .reliability: return "How selection works"
        }
    }

    private var subtitle: String {
        switch currentStep {
        case .about:
            return "Captains see your name and contact details when they pick a squad."
        case .sports:
            return "Pick everything you play. Each sport gets its own level, league and stats."
        case .sport(let sport):
            return sport.usesDivisions
                ? "Your standard, the division you play in, and the stats you want on your card."
                : "Your standard, preferred format, and the stats you want on your card."
        case .logistics:
            return "Where you're based, how far you'll travel, and whether you can offer lifts."
        case .reliability:
            return "Turning up is a stat too. Here's how yours is worked out."
        }
    }

    private var canAdvance: Bool {
        switch currentStep {
        case .about: return form.isNameValid
        case .sports: return form.hasSports
        case .sport(let sport): return form.isDetailComplete(sport)
        case .logistics, .reliability: return true
        }
    }

    private func advance() {
        errorMessage = nil
        guard isLastStep else {
            withAnimation(.snappy) { stepIndex = clampedIndex + 1 }
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await session.saveProfile(form.update)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Steps

private struct ReliabilityStep: View {
    @Bindable var form: ProfileFormModel
    let reliability: ReliabilityScore?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your reliability score")
                        .font(.headline)
                    Text("Every invite you answer, game you turn up to and fee you pay feeds one number. Captains weigh it alongside your level when they pick a squad.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        WeightRow(weight: "50%", label: "Turning up when you said you would")
                        WeightRow(weight: "25%", label: "Answering invites before the deadline")
                        WeightRow(weight: "25%", label: "Paying match fees")
                        WeightRow(weight: "−5", label: "Each late drop-out")
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                if let reliability, reliability.sampleSize > 0 {
                    ReliabilityCard(reliability: reliability)
                        .padding()
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    Label("You start unproven — three games is enough for a score.", systemImage: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("You're set up as")
                        .font(.headline)
                    ForEach(form.selectedSports) { sport in
                        let detail = form.detail(for: sport)
                        HStack(spacing: 10) {
                            Image(systemName: sport.systemImage)
                                .frame(width: 22)
                                .foregroundStyle(FishersTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sport.label).font(.subheadline.weight(.semibold))
                                Text(summary(for: detail))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if form.primarySport == sport {
                                Text("Main")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(FishersTheme.accent.opacity(0.15), in: Capsule())
                                    .foregroundStyle(FishersTheme.accent)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func summary(for detail: SportProfile) -> String {
        [detail.tier?.label, detail.position, detail.division?.label]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private struct WeightRow: View {
        let weight: String
        let label: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(weight)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(FishersTheme.accent)
                    .frame(width: 44, alignment: .leading)
                Text(label)
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
        }
    }
}

