import SwiftUI

/// A four, a six or a wicket — the ball that just happened, if it was one.
struct Moment: Equatable {
    enum Kind { case four, six, wicket }

    let kind: Kind
    let who: String
    var detail: String?

    var word: String {
        switch kind {
        case .four: return "FOUR"
        case .six: return "SIX"
        case .wicket: return "OUT!"
        }
    }

    var lasts: Duration {
        switch kind {
        case .four: return .milliseconds(1900)
        case .six: return .milliseconds(2100)
        case .wicket: return .milliseconds(2500)
        }
    }

    /// Worked out by comparing the match before and after, never guessed from
    /// a run total: a four is the striker's `fours` going up, which a four
    /// *run* does not do; a six is `sixes`; a wicket is the innings' count.
    /// Only a new ball can set one off — a first load, a new innings and an
    /// undo never do.
    static func between(_ before: MatchState, _ after: MatchState) -> Moment? {
        guard let now = after.innings.last,
              let then = before.innings.first(where: { $0.index == now.index }),
              now.deliveries.count > then.deliveries.count
        else { return nil }

        if now.wickets > then.wickets {
            let out = now.batters.first { batter in
                batter.out && !(then.batters.first { $0.playerId == batter.playerId }?.out ?? false)
            }
            return Moment(
                kind: .wicket,
                who: out.map { after.name(for: $0.playerId) } ?? "Wicket",
                detail: out.map { after.dismissalText($0) }
            )
        }
        for batter in now.batters {
            let earlier = then.batters.first { $0.playerId == batter.playerId }
            if batter.sixes > (earlier?.sixes ?? 0) {
                return Moment(kind: .six, who: after.name(for: batter.playerId))
            }
            if batter.fours > (earlier?.fours ?? 0) {
                return Moment(kind: .four, who: after.name(for: batter.playerId))
            }
        }
        return nil
    }
}

/// A beat of celebration for the scorer, the players following, anyone
/// watching the match.
///
/// Laid over the top of the screen with taps going straight through, so it
/// never gets between the scorer and the next ball. Reduced motion gets a
/// plain fade; VoiceOver hears it said once.
struct MomentsBanner: View {
    let state: MatchState

    @State private var moment: Moment?
    @State private var count = 0

    var body: some View {
        ZStack {
            if let moment {
                MomentCard(moment: moment)
                    .id(count)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .allowsHitTesting(false)
        .onChange(of: state) { before, after in
            guard let found = Moment.between(before, after) else { return }
            moment = found
            count += 1
            AccessibilityNotification.Announcement(
                "\(found.kind == .wicket ? "Wicket" : found.kind == .six ? "Six" : "Four") — \(found.who)"
            ).post()
        }
        .task(id: count) {
            guard let shown = moment else { return }
            try? await Task.sleep(for: shown.lasts)
            withAnimation(.easeOut(duration: 0.25)) { moment = nil }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: count)
    }
}

private struct MomentCard: View {
    let moment: Moment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var played = false

    private var colors: [Color] {
        switch moment.kind {
        case .four: return [Color(hex: 0x2F80ED), Color(hex: 0x1A56B8)]
        case .six: return [Color(hex: 0xFFB347), Color(hex: 0xF2711C), Color(hex: 0xC2410C)]
        case .wicket: return [Color(hex: 0xD8453A), Color(hex: 0x8E2418)]
        }
    }

    private var go: Bool { played || reduceMotion }

    var body: some View {
        VStack(spacing: 2) {
            if moment.kind == .wicket { stumps }
            Text(moment.word)
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .tracking(3)
                .shadow(color: .black.opacity(0.18), radius: 0, y: 3)
                .scaleEffect(moment.kind == .four || go ? 1 : 1.6)
                .offset(x: moment.kind == .four && !go ? -60 : 0)
            Text(moment.who)
                .font(.headline)
            if let detail = moment.detail {
                Text(detail)
                    .font(.subheadline)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.vertical, 22)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                if moment.kind == .four { rope }
                if moment.kind == .six { sparks }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
        .scaleEffect(moment.kind == .six && !go ? 0.6 : 1)
        .opacity(go ? 1 : 0)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { played = true }
        }
    }

    /// The ball racing along the ground to the rope.
    private var rope: some View {
        GeometryReader { geo in
            Capsule()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.85), .white], startPoint: .leading, endPoint: .trailing))
                .frame(width: go ? geo.size.width : 0, height: 3)
                .overlay(alignment: .trailing) {
                    Circle().fill(.white).frame(width: 13, height: 13).shadow(color: .white, radius: 6)
                }
                .position(x: (go ? geo.size.width : 0) / 2, y: geo.size.height - 12)
                .animation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.9).delay(0.15), value: played)
        }
    }

    /// Sparks bursting out from the middle.
    private var sparks: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                Circle()
                    .fill(Color(hex: 0xFFF4D6))
                    .frame(width: 6, height: 6)
                    .offset(y: go ? -90 : 0)
                    .rotationEffect(.degrees(Double(i) * 36))
                    .opacity(go && !reduceMotion ? 0 : 1)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 1).delay(0.2), value: played)
    }

    /// Three stumps and two bails; the bails are what fly.
    private var stumps: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 9) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 6, height: 48)
                }
            }
            .padding(.top, 8)
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2.5).fill(.white).frame(width: 18, height: 5)
                    .rotationEffect(.degrees(go && !reduceMotion ? -40 : 0))
                    .offset(x: go && !reduceMotion ? -22 : 0, y: go && !reduceMotion ? -18 : 0)
                RoundedRectangle(cornerRadius: 2.5).fill(.white).frame(width: 18, height: 5)
                    .rotationEffect(.degrees(go && !reduceMotion ? 50 : 0))
                    .offset(x: go && !reduceMotion ? 24 : 0, y: go && !reduceMotion ? -22 : 0)
            }
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.6, 0.4, 1, duration: 0.9).delay(0.2), value: played)
        }
        .frame(height: 58)
        .padding(.bottom, 4)
    }
}
