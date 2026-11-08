import SwiftUI

/// Top-level destinations — HIG recommends 3–5 tabs.
struct MainTabView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject private var push = PushRegistrar.shared

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
        // A tapped `season_closed` push opens that season on My game. A sheet
        // over whichever tab is showing, rather than a jump to Profile: the
        // tabs each own their navigation stack, and pushing into another
        // tab's stack from here would leave it somewhere its back button does
        // not explain.
        .sheet(item: $push.pendingSeason) { link in
            NavigationStack {
                SeasonStatsView(tab: link.clubTab ? .club : .mine, season: link.season, clubId: link.clubId)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(t("sh.done")) { push.pendingSeason = nil }
                        }
                    }
            }
        }
    }
}
