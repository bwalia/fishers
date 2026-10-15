import SwiftUI

/// "Your profile is 35% complete" — with the few things worth adding next, a
/// way to add them, and a way to be reminded instead. Gone at 100%.
struct ProfileStrengthSection: View {
    let user: PublicUser
    let onComplete: () -> Void
    /// Home offers a reminder; Profile, where the person already is, does not.
    var offersReminder = true

    @State private var reminder: String?

    private var strength: ProfileStrength { ProfileStrength(user) }

    var body: some View {
        if !strength.isComplete {
            Section {
                HStack(spacing: 14) {
                    ProfileStrengthRing(percent: strength.percent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("rest.profile_percent_complete", vars: ["percent": strength.percent]))
                            .font(FishersTheme.headline)
                        Text(t("rest.so_captains_can_see", vars: ["what": strength.nextUp]))
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)

                HStack(spacing: 10) {
                    Button(action: onComplete) {
                        Text(t("rest.complete_profile"))
                            .font(FishersTheme.subhead.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)

                    if offersReminder {
                        Button {
                            Task {
                                reminder = await ProfileReminder.requestAndSchedule(for: user)
                                    ? tr("We'll remind you tomorrow evening.")
                                    : "Turn on notifications for \(Brand.name) in Settings to get a reminder."
                            }
                        } label: {
                            Text(t("rest.remind_me_later"))
                                .font(FishersTheme.subhead.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .disabled(reminder != nil)
                    }
                }

                if let reminder {
                    Label(reminder, systemImage: "bell")
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ProfileStrengthRing: View {
    let percent: Int
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().stroke(FishersTheme.hairline, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(FishersTheme.pitch, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .frame(width: size, height: size)
        .accessibilityLabel(t("rest.profile_percent_aria", vars: ["percent": percent]))
    }
}
