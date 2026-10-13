import SwiftUI

/// Top-level destinations — HIG recommends 3–5 tabs.
struct MainTabView: View {
    @EnvironmentObject private var language: LanguageStore

    var body: some View {
        TabView {
            HomeFeedView()
                .tabItem { Label(language.t("nav.home"), systemImage: "house") }
            FixturesView()
                .tabItem { Label(language.t("nav.fixtures"), systemImage: "calendar") }
            ChatListView()
                .tabItem { Label(language.t("nav.chats"), systemImage: "bubble.left.and.bubble.right") }
            ClubsTeamsView()
                .tabItem { Label(language.t("nav.clubs"), systemImage: "person.3") }
            ProfileView()
                .tabItem { Label(language.t("nav.profile"), systemImage: "person.crop.circle") }
        }
        .tint(FishersTheme.accent)
        .overlay(alignment: .top) { LiveAlerts() }
    }
}
