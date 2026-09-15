import SwiftUI

/// The one screen between signing up and the app: what you play, and a number
/// your captain can reach you on. Both can be skipped.
///
/// Everything else a profile holds — standard, position, photo, travel — waits
/// for a quiet moment. The point of the first minute is to get somebody into a
/// club and a match, not to fill in a form.
struct QuickStartView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var role: RoleIntent?
    @State private var sports: [Sport] = []
    @State private var phone = ""
    @State private var saving = false
    @State private var error: String?

    /// Asked here only if signup did not — somebody who signed in to an
    /// account made before the question existed.
    private var asksRole: Bool { session.user?.intent == nil }
    private var asksPhone: Bool { session.user?.phone?.nonEmpty == nil }
    private var firstName: String {
        session.user?.name.split(separator: " ").first.map(String.init) ?? "there"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FishersTheme.space3) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hi \(firstName)")
                            .font(FishersTheme.display)
                        Text("Two quick things and you're in. Everything else can wait until you have a minute.")
                            .font(FishersTheme.subhead)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if asksRole {
                        question("I'm here to…") {
                            RoleChooserView(selection: $role, compact: true)
                        }
                    }

                    question("What do you play?", note: sports.count > 1 ? "\(sports[0].label) is your main sport — the first one you picked." : nil) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                            ForEach(Sport.allCases) { sport in
                                sportChip(sport)
                            }
                        }
                    }

                    if asksPhone {
                        question("Your mobile number", note: "So your captain can reach you on match day. Only your clubs see it.") {
                            TextField("07700 900123", text: $phone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .font(FishersTheme.body)
                                .padding(.horizontal, 14)
                                .frame(minHeight: FishersTheme.minTap)
                                .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    if let error {
                        Text(error)
                            .font(FishersTheme.footnote)
                            .foregroundStyle(FishersTheme.unavailable)
                    }
                }
                .padding(FishersTheme.space2)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FishersTheme.mist.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    Button {
                        Task { await finish() }
                    } label: {
                        Group {
                            if saving { ProgressView() } else { Text("Continue").font(FishersTheme.headline) }
                        }
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(saving || sports.isEmpty)

                    Button("Skip for now") { Task { await skip() } }
                        .font(FishersTheme.subhead.weight(.semibold))
                        .frame(minHeight: FishersTheme.minTap)
                        .disabled(saving)
                }
                .padding(.horizontal, FishersTheme.space2)
                .padding(.top, 8)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FishersBrandHeader(style: .inline)
                }
            }
        }
        .tint(FishersTheme.accent)
        .onAppear {
            role = session.user?.intent
            phone = session.user?.phone ?? ""
        }
    }

    private func question<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(FishersTheme.headline)
            content()
            if let note {
                Text(note)
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sportChip(_ sport: Sport) -> some View {
        let on = sports.contains(sport)
        return Button {
            if let index = sports.firstIndex(of: sport) { sports.remove(at: index) } else { sports.append(sport) }
        } label: {
            Label(sport.label, systemImage: sport.systemImage)
                .font(FishersTheme.subhead.weight(on ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                .foregroundStyle(on ? .white : .primary)
                .background(on ? FishersTheme.pitch : FishersTheme.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? .clear : FishersTheme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func finish() async {
        guard let user = session.user else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            if let role, role != user.intent { try await session.setRoleIntent(role) }
            var update = ProfileUpdate(
                name: user.name,
                sportProfiles: sports.map { SportProfile(sport: $0.rawValue) },
                primarySport: sports.first?.rawValue
            )
            update.phone = phone.nonEmpty
            try await session.saveProfile(update)
            session.finishQuickStart()
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }

    /// Straight in. The role still counts if they picked one — it decides
    /// whether Home offers a club or a profile link.
    private func skip() async {
        saving = true
        defer { saving = false }
        if let role, role != session.user?.intent { try? await session.setRoleIntent(role) }
        session.finishQuickStart()
    }
}

/// Right after the quick start, for a player: the link that gets them into a
/// club, and why.
struct WelcomeShareSheet: View {
    let userId: UUID
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(FishersTheme.pitch)
                            .accessibilityHidden(true)
                        Text("You're in. Now get picked.")
                            .font(FishersTheme.title)
                        Text("Send your profile link to your club's secretary or captain — on WhatsApp is fine. They add you in one tap, and your fixtures show up here.")
                            .font(FishersTheme.subhead)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section {
                    ShareProfileView(userId: userId)
                        .padding(.vertical, 4)
                } footer: {
                    Text("They see your name, photo and what you play — not your email or number.")
                }
            }
            .fishersList()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}
