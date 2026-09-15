import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if !session.isAuthenticated {
                AuthView()
            } else if session.needsQuickStart {
                // A sport and a number, both skippable — the rest of the
                // profile is asked for later, never up front.
                QuickStartView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: session.needsQuickStart)
        .task {
            await session.bootstrap()
        }
    }
}
