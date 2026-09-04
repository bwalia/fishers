import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if !session.isAuthenticated {
                AuthView()
            } else if session.needsProfileSetup {
                // Setting up the profile is the first stage of the app — no
                // fixtures, no squads, until we know how someone plays.
                ProfileSetupView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: session.needsProfileSetup)
        .task {
            await session.bootstrap()
        }
    }
}
