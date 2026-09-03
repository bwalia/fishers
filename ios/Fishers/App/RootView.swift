import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if !app.isSignedIn {
                AuthView()
            } else if app.needsProfileSetup {
                // Setting up the profile is the first stage of the app — no
                // calendar, no squads, until we know how someone plays.
                ProfileSetupView()
            } else {
                MainTabView()
            }
        }
        .animation(.snappy, value: app.isSignedIn)
        .animation(.snappy, value: app.needsProfileSetup)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            CalendarTabView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            ClubsView()
                .tabItem { Label("Clubs", systemImage: "person.3.fill") }
            ShopView()
                .tabItem { Label("Shop", systemImage: "cart.fill") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootView()
        .environment(AppState(demoMode: true))
}
